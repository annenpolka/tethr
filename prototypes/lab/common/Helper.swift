import AppKit
import Foundation
import Darwin

struct AppEntry: Codable {
    let id: String
    let title: String
    let subtitle: String
    let keywords: String
    let bundleID: String
    let path: String?
}
struct Config: Decodable {
    let protocolVersion: Int
    let helperPath: String
    let stateDir: String
    let cwd: String
    let tmuxPath: String
    let apps: [AppEntry]
}
struct LabError: Error {
    let code: String
    let message: String
}
struct ProcessResult { let status: Int32; let stdout: String; let stderr: String }

func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
}
func atomicJSON(_ object: Any, at path: String) throws {
    try jsonData(object).write(to: URL(fileURLWithPath: path), options: .atomic)
}
func readJSON(_ path: String) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any] else {
        throw LabError(code: "invalid-record", message: "記録を読み取れません。")
    }
    return value
}
func emit(_ value: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    } catch {
        FileHandle.standardError.write(Data("JSON encoding failed: \(error)\n".utf8))
        exit(1)
    }
}
func option(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func waitUntil(seconds: Double, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if predicate() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    return predicate()
}
func run(_ executable: String, _ arguments: [String], cwd: String? = nil, seconds: Double = 8) throws -> ProcessResult {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tethr-capture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    let outURL = temp.appendingPathComponent("stdout")
    let errURL = temp.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let out = try FileHandle(forWritingTo: outURL)
    let err = try FileHandle(forWritingTo: errURL)
    defer { try? out.close(); try? err.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "TMUX")
    environment.removeValue(forKey: "TMUX_PANE")
    environment.removeValue(forKey: "ENV")
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = out
    process.standardError = err
    try process.run()
    if !waitUntil(seconds: seconds, { !process.isRunning }) {
        process.terminate()
        if !waitUntil(seconds: 1, { !process.isRunning }) { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        throw LabError(code: "process-timeout", message: "処理の終了を確認できませんでした。自動再実行はしていません。")
    }
    process.waitUntilExit()
    try out.synchronize()
    try err.synchronize()
    return ProcessResult(status: process.terminationStatus,
        stdout: String(decoding: try Data(contentsOf: outURL), as: UTF8.self),
        stderr: String(decoding: try Data(contentsOf: errURL), as: UTF8.self))
}

final class Backend {
    let config: Config
    let socket: String
    init(config: Config) throws {
        guard config.protocolVersion == 1,
              [config.helperPath, config.stateDir, config.cwd, config.tmuxPath].allSatisfy({ $0.hasPrefix("/") }) else {
            throw LabError(code: "invalid-config", message: "設定の版と絶対パスを確認してください。")
        }
        self.config = config
        // UNIX domain socket names have a short limit on macOS. Keep state under /tmp.
        self.socket = config.stateDir + "/tmux.sock"
        guard socket.utf8.count < 100 else {
            throw LabError(code: "socket-path-too-long", message: "stateDirには短い絶対パスを指定してください。")
        }
        try FileManager.default.createDirectory(atPath: config.stateDir + "/requests", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: config.stateDir + "/receipts", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: config.stateDir + "/receiver", withIntermediateDirectories: true)
    }
    func catalog() -> [[String: Any]] {
        var values: [[String: Any]] = [
            ["id": "terminal.step", "title": "同じシェルで続ける", "subtitle": "試験用 tmux の状態を確認・更新", "keywords": "terminal shell tmux ターミナル 続き", "kind": "terminal"],
            ["id": "command.git-status", "title": "変更状況を見る", "subtitle": config.cwd, "keywords": "git status changes 変更 リポジトリ", "kind": "command"]
        ]
        values += config.apps.map { ["id": $0.id, "title": $0.title, "subtitle": $0.subtitle, "keywords": $0.keywords, "kind": "application"] }
        return values
    }
    func tmux(_ args: [String]) throws -> ProcessResult {
        try run(config.tmuxPath, ["-S", socket, "-f", "/dev/null"] + args)
    }
    func tmuxOK(_ args: [String]) throws -> String {
        let value = try tmux(args)
        guard value.status == 0 else { throw LabError(code: "tmux-failed", message: "試験用 tmux: " + value.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return value.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func identity(paneID: String = "tethr-lab:0.0") throws -> [String] {
        let text = try tmuxOK(["display-message", "-p", "-t", paneID, "#{pane_id}\t#{pane_pid}\t#{pid}\t#{start_time}"])
        let parts = text.components(separatedBy: "\t")
        guard parts.count == 4 else { throw LabError(code: "invalid-identity", message: "シェルを識別できません。") }
        return parts
    }
    func send(_ line: String, paneID: String) throws {
        _ = try tmuxOK(["send-keys", "-t", paneID, "-l", line])
        _ = try tmuxOK(["send-keys", "-t", paneID, "Enter"])
    }
    func withLock<T>(_ body: () throws -> T) throws -> T {
        let fd = open(config.stateDir + "/lock", O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LabError(code: "lock-failed", message: "状態ファイルを開けません。") }
        defer { close(fd) }
        guard waitUntil(seconds: 10, { flock(fd, LOCK_EX | LOCK_NB) == 0 }) else {
            throw LabError(code: "busy", message: "別の操作が進行中です。")
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    func ensureShell() throws -> [String: Any] {
        let metaPath = config.stateDir + "/shell.json"
        if FileManager.default.fileExists(atPath: metaPath) {
            let meta = try readJSON(metaPath)
            guard let expected = meta["identity"] as? [String], expected.count == 4,
                  expected[0].range(of: "^%[0-9]+$", options: .regularExpression) != nil else {
                throw LabError(code: "invalid-identity", message: "保存されたpane識別情報が不正です。")
            }
            let current = try identity(paneID: expected[0])
            guard current == expected else {
                throw LabError(code: "stale-shell", message: "元の試験用シェルが変わりました。別シェルへ自動送信しません。")
            }
            return meta
        }
        let has = try tmux(["has-session", "-t", "tethr-lab"])
        guard has.status != 0 else { throw LabError(code: "unowned-session", message: "識別記録のない試験セッションがあります。操作しません。") }
        _ = try tmuxOK(["new-session", "-d", "-s", "tethr-lab", "-c", config.cwd, "/bin/sh"])
        let initial = try identity()
        let nonce = UUID().uuidString
        let readyPath = config.stateDir + "/ready.json"
        // These values and this function live in the original interactive shell; they are not exported.
        let initialization = "stty -echo; TETHR_SHELL_NONCE=\(quote(nonce)); TETHR_COUNTER=0; tethr_emit() { \(quote(config.helperPath)) receipt --output \"$1\" --request-id \"$2\" --nonce \"$TETHR_SHELL_NONCE\" --counter \"$TETHR_COUNTER\" --shell-pid \"$$\"; }; tethr_step() { TETHR_COUNTER=$((TETHR_COUNTER + 1)); tethr_emit \"$1\" \"$2\"; }; tethr_emit \(quote(readyPath)) ready"
        try send(initialization, paneID: initial[0])
        guard waitUntil(seconds: 5, { FileManager.default.fileExists(atPath: readyPath) }) else {
            throw LabError(code: "shell-ready-timeout", message: "試験用シェルの準備を確認できません。")
        }
        let ready = try readJSON(readyPath)
        guard ready["shellNonce"] as? String == nonce,
              ready["shellPID"] as? Int == Int(initial[1]),
              ready["parentPID"] as? Int == Int(initial[1]) else {
            throw LabError(code: "shell-witness-failed", message: "元のシェルからの応答を確認できません。")
        }
        let metadata: [String: Any] = ["identity": initial, "shellNonce": nonce, "counter": 0]
        try atomicJSON(metadata, at: metaPath)
        return metadata
    }
    func step(requestID: String) throws -> [String: Any] {
        try withLock {
            var meta = try ensureShell()
            let path = config.stateDir + "/receipts/" + requestID + ".json"
            guard !FileManager.default.fileExists(atPath: path) else {
                throw LabError(code: "duplicate-request", message: "同じ依頼は実行済みです。再実行しません。")
            }
            guard let savedIdentity = meta["identity"] as? [String], let paneID = savedIdentity.first else {
                throw LabError(code: "invalid-identity", message: "送信先paneを識別できません。")
            }
            try send("tethr_step \(quote(path)) \(quote(requestID))", paneID: paneID)
            guard waitUntil(seconds: 5, { FileManager.default.fileExists(atPath: path) }) else {
                throw LabError(code: "receipt-timeout", message: "受信を確認できません。実行状態は不明のため再送していません。")
            }
            let receipt = try readJSON(path)
            let ident = try identity(paneID: paneID)
            let next = (meta["counter"] as? Int ?? -1) + 1
            guard receipt["requestID"] as? String == requestID,
                  receipt["shellNonce"] as? String == meta["shellNonce"] as? String,
                  receipt["shellPID"] as? Int == Int(ident[1]),
                  receipt["parentPID"] as? Int == Int(ident[1]),
                  receipt["counter"] as? Int == next,
                  ident == meta["identity"] as? [String] else {
                throw LabError(code: "receipt-mismatch", message: "期待したシェルの継続を確認できません。")
            }
            meta["counter"] = next
            try atomicJSON(meta, at: config.stateDir + "/shell.json")
            return receipt
        }
    }
    func raiseApp(_ entry: AppEntry) throws -> [String: Any] {
        let targetURL: URL
        if let path = entry.path { targetURL = URL(fileURLWithPath: path) }
        else if let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID) { targetURL = found }
        else { throw LabError(code: "app-not-found", message: "対象アプリが見つかりません。") }
        guard Bundle(url: targetURL)?.bundleIdentifier == entry.bundleID else {
            throw LabError(code: "app-identity-mismatch", message: "アプリの識別情報が一致しません。")
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleID)
        guard running.count <= 1 else { throw LabError(code: "ambiguous-app", message: "複数の実行インスタンスがあります。対象を一つにしてください。") }
        let wasRunning = !running.isEmpty
        var target = running.first
        #if LAB_FAULTS
        if ProcessInfo.processInfo.environment["TETHR_LAB_FAULT"] == "noop-activation" {
            return ["bundleID": entry.bundleID, "pid": target?.processIdentifier ?? -1,
                    "wasRunning": wasRunning, "frontmostObserved": true, "faultInjected": "noop-activation"]
        }
        #endif
        if let existing = target {
            _ = existing.activate(options: [])
        } else {
            let open = NSWorkspace.OpenConfiguration()
            open.activates = true
            open.createsNewApplicationInstance = false
            if entry.bundleID.hasPrefix("com.tethr.lab.receiver-") {
                open.environment = ["TETHR_LAB_RECEIPTS": config.stateDir + "/receiver"]
            }
            var done = false
            var launchError: Error?
            NSWorkspace.shared.openApplication(at: targetURL, configuration: open) { app, error in
                // NSWorkspace invokes completion on a concurrent queue. Confine
                // shared launch state to the main queue, serviced by waitUntil.
                DispatchQueue.main.async {
                    target = app
                    launchError = error
                    done = true
                }
            }
            guard waitUntil(seconds: 8, { done }) else { throw LabError(code: "launch-timeout", message: "起動完了を確認できません。") }
            if let launchError { throw LabError(code: "launch-failed", message: "起動できません: \(launchError.localizedDescription)") }
        }
        guard let target else { throw LabError(code: "app-unavailable", message: "対象アプリを取得できません。") }
        let frontmost = waitUntil(seconds: 4) { NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier }
        guard frontmost else { throw LabError(code: "activation-not-observed", message: "アプリへの切り替えを確認できませんでした。") }
        return ["bundleID": entry.bundleID, "pid": target.processIdentifier, "wasRunning": wasRunning, "frontmostObserved": frontmost]
    }
    func dispatch(id: String, requestID: String) throws -> [String: Any] {
        guard requestID.range(of: "^[A-Za-z0-9_-]{1,100}$", options: .regularExpression) != nil else {
            throw LabError(code: "invalid-request", message: "依頼の識別子が不正です。")
        }
        guard let item = catalog().first(where: { $0["id"] as? String == id }) else {
            throw LabError(code: "unknown-action", message: "操作が見つかりません。")
        }
        let requestPath = config.stateDir + "/requests/" + requestID + ".json"
        // O_EXCL reserves the request before any side effect, including across helper processes.
        let fd = open(requestPath, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw LabError(code: "duplicate-request", message: "この依頼は受付済みです。自動再実行しません。") }
        close(fd)
        let data: [String: Any]
        let message: String
        do {
            if id == "terminal.step" {
                data = try step(requestID: requestID)
                message = "同じシェルで \(data["counter"] ?? "?") 回目の操作\n\(data["cwd"] ?? "")\nシェル PID: \(data["shellPID"] ?? "?")"
            } else if id == "command.git-status" {
                let value = try run("/usr/bin/git", ["-C", config.cwd, "status", "--short", "--untracked-files=normal"])
                guard value.status == 0 else { throw LabError(code: "git-failed", message: value.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
                data = ["stdout": value.stdout, "stderr": value.stderr, "exitCode": value.status, "cwd": config.cwd]
                message = value.stdout.isEmpty ? "変更はありません。" : value.stdout
            } else if let app = config.apps.first(where: { $0.id == id }) {
                data = try raiseApp(app)
                message = "\(app.title)に切り替えました。"
            } else { throw LabError(code: "unknown-action", message: "操作が見つかりません。") }
            let response: [String: Any] = ["protocolVersion": 1, "status": "ok", "requestID": requestID,
                "actionID": id, "title": item["title"] ?? id, "message": message, "data": data]
            try atomicJSON(response, at: requestPath)
            return response
        } catch {
            let lab = error as? LabError
            let record: [String: Any] = ["protocolVersion": 1, "status": "error", "requestID": requestID,
                "actionID": id, "errorCode": lab?.code ?? "internal-error", "message": lab?.message ?? error.localizedDescription]
            try? atomicJSON(record, at: requestPath)
            throw error
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
var actionID = ""
var requestID = ""
do {
    if arguments.first == "receipt" {
        guard let path = option(arguments, "--output"),
              let nonce = option(arguments, "--nonce"),
              let counterText = option(arguments, "--counter"), let counter = Int(counterText),
              let shellText = option(arguments, "--shell-pid"), let shell = Int(shellText),
              let request = option(arguments, "--request-id") else {
            throw LabError(code: "receipt-arguments", message: "receipt arguments missing")
        }
        try atomicJSON(["requestID": request, "shellNonce": nonce, "counter": counter,
            "shellPID": shell, "parentPID": Int(getppid()), "processID": Int(getpid()),
            "cwd": FileManager.default.currentDirectoryPath,
            "uptimeNanoseconds": String(DispatchTime.now().uptimeNanoseconds)], at: path)
        exit(0)
    }
    guard let configPath = option(arguments, "--config"), let ci = arguments.firstIndex(of: "--config"), ci + 2 < arguments.count else {
        throw LabError(code: "arguments", message: "--config PATH catalog または dispatch ACTION --request-id ID を指定してください。")
    }
    let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: configPath)))
    let backend = try Backend(config: config)
    let command = arguments[ci + 2]
    if command == "catalog" { emit(["protocolVersion": 1, "status": "ok", "items": backend.catalog()]) }
    else if command == "dispatch", ci + 3 < arguments.count {
        actionID = arguments[ci + 3]
        requestID = option(arguments, "--request-id") ?? ""
        emit(try backend.dispatch(id: actionID, requestID: requestID))
    } else { throw LabError(code: "unknown-command", message: "不明な操作です。") }
} catch {
    let lab = error as? LabError
    emit(["protocolVersion": 1, "status": "error", "requestID": requestID, "actionID": actionID,
        "message": lab?.message ?? error.localizedDescription, "errorCode": lab?.code ?? "internal-error"])
    exit(1)
}
