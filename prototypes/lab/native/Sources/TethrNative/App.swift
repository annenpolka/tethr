import AppKit
import NativeCore

@MainActor
final class ActionPanel: NSPanel {
    var runAction: (() -> Void)?
    var moveAction: ((Int) -> Void)?
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
    override func keyDown(with event: NSEvent) {
        // The field editor owns IME and search editing commands.
        if let editor = firstResponder as? NSTextView, editor.isEditable { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53: orderOut(nil)
        case 36, 76: runAction?()
        case 125: moveAction?(1)
        case 126: moveAction?(-1)
        default: super.keyDown(with: event)
        }
    }
}
@MainActor
final class Delegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var panel: ActionPanel!
    let search = NSTextField(string: "")
    let table = NSTableView()
    let output = NSTextView()
    let run = NSButton(title: "実行 ↵", target: nil, action: nil)
    var model = Selection()
    var helper: Helper?
    var loading = true

    func installMenus() {
        let menuBar = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Tethr Native")
        applicationMenu.addItem(withTitle: "Tethr Nativeを非表示", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Tethr Nativeを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        menuBar.addItem(applicationItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        menuBar.addItem(editItem)
        NSApp.mainMenu = menuBar
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenus()
        panel = ActionPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.runAction = { [weak self] in self?.execute() }
        panel.moveAction = { [weak self] delta in self?.model.move(delta); self?.refresh() }
        panel.title = "tethr · Native AppKit"; panel.isReleasedWhenClosed = false
        // Keep the launched panel visible if activation is delayed or denied.
        // This is not a promise that a window manager treats it as floating.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.minSize = NSSize(width: 540, height: 400)
        search.placeholderString = "操作を検索 — terminal / git / app"; search.delegate = self
        search.identifier = NSUserInterfaceItemIdentifier("tethr.search")
        search.setAccessibilityIdentifier("tethr.search")
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions")); column.title = "操作"
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 50
        table.delegate = self; table.dataSource = self; table.allowsEmptySelection = false
        table.setAccessibilityIdentifier("tethr.results")
        let results = NSScrollView(); results.documentView = table; results.hasVerticalScroller = true
        output.isEditable = false; output.isSelectable = true; output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        output.setAccessibilityIdentifier("tethr.output")
        let detail = NSScrollView(); detail.documentView = output; detail.hasVerticalScroller = true
        output.autoresizingMask = [.width]; output.isVerticallyResizable = true; output.isHorizontallyResizable = false
        output.textContainer?.widthTracksTextView = true
        run.target = self; run.action = #selector(execute); run.isEnabled = false
        let stack = NSStackView(views: [search, results, run, detail]); stack.orientation = .vertical; stack.spacing = 12; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false; panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor, constant: -16),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor), results.widthAnchor.constraint(equalTo: stack.widthAnchor), detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            results.heightAnchor.constraint(equalToConstant: 190), detail.heightAnchor.constraint(greaterThanOrEqualToConstant: 130)
        ])
        panel.center(); show()
        Task { @MainActor in await load() }
    }
    func show() { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: false); panel.makeFirstResponder(search) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func numberOfRows(in tableView: NSTableView) -> Int { model.filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = model.filtered[row]
        let field = NSTextField(wrappingLabelWithString: item.title + "\n" + item.subtitle)
        field.font = .systemFont(ofSize: 13); field.setAccessibilityIdentifier(item.id)
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) { if table.selectedRow >= 0 { model.index = table.selectedRow } }
    func refresh() {
        dispatchPrecondition(condition: .onQueue(.main))
        table.reloadData()
        if !model.filtered.isEmpty { table.selectRowIndexes(IndexSet(integer: model.index), byExtendingSelection: false); table.scrollRowToVisible(model.index) }
        run.isEnabled = !loading && !model.busy && !model.filtered.isEmpty
    }
    func controlTextDidChange(_ obj: Notification) { model.query = search.stringValue; refresh() }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        if commandSelector == #selector(NSResponder.moveDown(_:)) { model.move(1); refresh(); return true }
        if commandSelector == #selector(NSResponder.moveUp(_:)) { model.move(-1); refresh(); return true }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { execute(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { panel.orderOut(nil); return true }
        return false
    }
    func display(_ text: String, error: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))
        output.string = text; output.textColor = error ? .systemRed : .labelColor }
    func load() async {
        do {
            let args = CommandLine.arguments
            let flag = args.firstIndex(of: "--config")
            let path = flag.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? ProcessInfo.processInfo.environment["TETHR_LAB_CONFIG"]
            guard let path else { throw LabError("Set TETHR_LAB_CONFIG or pass --config PATH, then relaunch.") }
            display("設定と操作一覧を読み込み中…")
            // File access may wait on the OS. Never block the AppKit main actor.
            let client = try await Task.detached { try Helper(config: path) }.value
            helper = client
            model.items = try Wire.catalog(await client.call(["catalog"]))
            display("操作を選び Enter。↑↓ 選択 / Esc 非表示。\nアプリ操作後は自動で前面へ戻りません。")
        } catch { display(error.localizedDescription, error: true) }
        loading = false; refresh()
    }
    @objc func execute() {
        guard let helper, !loading else { return }
        let composing = (search.currentEditor() as? NSTextView)?.hasMarkedText() ?? false
        guard let item = model.begin(composing: composing) else { return }
        let request = UUID().uuidString
        display("実行中: " + item.title); refresh()
        if item.kind == "application" || item.id.hasPrefix("app.") { panel.orderOut(nil) }
        Task { @MainActor in
            do { display(try Wire.result(await helper.call(["dispatch", item.id, "--request-id", request]), request: request, action: item.id)) }
            catch { display(error.localizedDescription, error: true) }
            model.finish(); refresh()
        }
    }
}
@main
struct NativeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
