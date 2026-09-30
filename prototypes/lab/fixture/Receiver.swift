import AppKit
import Foundation

final class Recorder {
    let role = Bundle.main.bundleIdentifier ?? "receiver"
    let started = String(DispatchTime.now().uptimeNanoseconds)
    let directory: String
    var sequence = 0
    init() {
        directory = ProcessInfo.processInfo.environment["TETHR_LAB_RECEIPTS"] ?? NSTemporaryDirectory() + "tethr-receiver"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }
    func record(_ event: String, _ fields: [String: Any] = [:]) {
        sequence += 1
        var row = fields
        row["event"] = event
        row["bundleID"] = role
        row["pid"] = ProcessInfo.processInfo.processIdentifier
        row["processStart"] = started
        row["sequence"] = sequence
        row["time"] = String(DispatchTime.now().uptimeNanoseconds)
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        let file = directory + "/" + role + ".jsonl"
        if !FileManager.default.fileExists(atPath: file) { FileManager.default.createFile(atPath: file, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: file) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.write(Data([10]))
    }
}
let recorder = Recorder()
final class ReceiverText: NSTextView {
    var submissions = 0
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        recorder.record("received", ["text": string, "field": "receiver-input", "window": window?.windowNumber ?? -1])
    }
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        recorder.record("composition", ["hasMarkedText": hasMarkedText(), "text": self.string])
    }
    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) && !hasMarkedText() {
            submissions += 1
            recorder.record("submit", ["count": submissions, "text": string, "field": "receiver-input"])
        }
        super.doCommand(by: selector)
    }
}
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var input: ReceiverText!
    func applicationDidFinishLaunching(_ note: Notification) {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Receiver"
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = name
        window.identifier = NSUserInterfaceItemIdentifier("receiver-window")
        let root = NSView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        let label = NSTextField(labelWithString: "\(name) — 受信した文字を記録します")
        label.frame = NSRect(x: 22, y: 230, width: 475, height: 26)
        label.autoresizingMask = [.width, .minYMargin]
        root.addSubview(label)
        let scroll = NSScrollView(frame: NSRect(x: 22, y: 24, width: 476, height: 198))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        input = ReceiverText(frame: scroll.bounds)
        input.isRichText = false
        input.font = .monospacedSystemFont(ofSize: 19, weight: .regular)
        input.textContainerInset = NSSize(width: 12, height: 12)
        input.autoresizingMask = [.width]
        input.setAccessibilityIdentifier("receiver-input")
        scroll.documentView = input
        root.addSubview(scroll)
        window.contentView = root
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        NSApplication.shared.activate(ignoringOtherApps: true)
        recorder.record("started", ["window": window.windowNumber])
    }
    func applicationDidBecomeActive(_ note: Notification) { recorder.record("active") }
    func applicationDidResignActive(_ note: Notification) { recorder.record("inactive") }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        return true
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu()
let item = NSMenuItem()
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit Receiver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
item.submenu = appMenu
menu.addItem(item)
app.mainMenu = menu
let delegate = Delegate()
app.delegate = delegate
app.run()
