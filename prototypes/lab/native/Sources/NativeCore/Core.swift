import Foundation

public struct Item: Codable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let keywords: String
    public let kind: String
    public init(id: String, title: String, subtitle: String = "", keywords: String = "", kind: String = "command") {
        self.id = id; self.title = title; self.subtitle = subtitle; self.keywords = keywords; self.kind = kind
    }
}
public struct Catalog: Decodable { public let protocolVersion: Int; public let status: String; public let items: [Item] }
public struct LabError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public struct Selection {
    public var items: [Item] = []
    public var query = "" { didSet { index = 0 } }
    public var index = 0
    public private(set) var busy = false
    public init() {}
    public var filtered: [Item] {
        let tokens = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        return items.filter { item in
            let haystack = "\(item.title) \(item.subtitle) \(item.keywords)".lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }
    public mutating func move(_ delta: Int) { index = max(0, min(max(0, filtered.count - 1), index + delta)) }
    public mutating func begin(composing: Bool = false) -> Item? {
        guard !busy, !composing, filtered.indices.contains(index) else { return nil }
        busy = true; return filtered[index]
    }
    public mutating func finish() { busy = false }
}
public enum Wire {
    public static func catalog(_ data: Data) throws -> [Item] {
        let value = try JSONDecoder().decode(Catalog.self, from: data)
        guard value.protocolVersion == 1, value.status == "ok", Set(value.items.map(\.id)).count == value.items.count else { throw LabError("Invalid catalog protocol/status or duplicate IDs") }
        return value.items
    }
    public static func result(_ data: Data, request: String, action: String) throws -> String {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["protocolVersion"] as? Int == 1,
              value["requestID"] as? String == request,
              value["actionID"] as? String == action,
              let status = value["status"] as? String,
              let message = value["message"] as? String else { throw LabError("Invalid or mismatched helper response") }
        if status == "error" { throw LabError("\(value["errorCode"] as? String ?? "error"): \(message)") }
        guard status == "ok" else { throw LabError("Invalid helper status: \(status)") }
        if let details = value["data"], JSONSerialization.isValidJSONObject(details),
           let pretty = try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]), let text = String(data: pretty, encoding: .utf8) { return message + "\n\n" + text }
        return message
    }
}
public struct Helper {
    public let config: String
    public let executable: String
    public init(config: String) throws {
        self.config = URL(fileURLWithPath: config).standardizedFileURL.path
        let data = try Data(contentsOf: URL(fileURLWithPath: self.config))
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], value["protocolVersion"] as? Int == 1,
              let path = value["helperPath"] as? String, path.hasPrefix("/") else { throw LabError("Config needs protocolVersion 1 and absolute helperPath") }
        executable = path
    }
    public func call(_ arguments: [String]) async throws -> Data {
        let path = executable, configPath = config
        return try await Task.detached { try Self.perform(path: path, configPath: configPath, arguments: arguments) }.value
    }
    private static func perform(path: String, configPath: String, arguments: [String]) throws -> Data {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tethr-native-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let out = dir.appendingPathComponent("stdout"), err = dir.appendingPathComponent("stderr")
            FileManager.default.createFile(atPath: out.path, contents: nil)
            FileManager.default.createFile(atPath: err.path, contents: nil)
            let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
            defer { try? output.close(); try? errors.close() }
            let process = Process(), done = DispatchSemaphore(value: 0)
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--config", configPath] + arguments
            process.standardOutput = output; process.standardError = errors
            process.terminationHandler = { _ in done.signal() }
            try process.run()
            guard done.wait(timeout: .now() + 30) == .success else {
                process.terminate()
                throw LabError("Helper timed out; outcome unknown. No automatic retry.")
            }
            let data = try Data(contentsOf: out)
            guard process.terminationStatus == 0 else {
                let diagnostic = (try? String(contentsOf: err, encoding: .utf8)) ?? ""
                let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw LabError("Helper exit \(process.terminationStatus): \(response?["message"] as? String ?? diagnostic)")
            }
            return data
    }
}
