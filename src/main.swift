import AppKit
import UniformTypeIdentifiers

// Inspect the same bundle localization used by the UI, without opening a window.
if CommandLine.arguments.contains("--print-localization") {
    let url = Bundle.main.url(forResource: "Localizable", withExtension: "strings")!
    let data = try Data(contentsOf: url)
    let table = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: String]
    let values = table.mapValues { $0 }
    let result: [String: Any] = [
        "preferredLocalizations": Bundle.main.preferredLocalizations,
        "developmentLocalization": Bundle.main.developmentLocalization ?? "",
        "displayName": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") ?? "",
        "strings": values,
        "samples": [
            "onePage": LP("row.completed", 1, "sample.pdf"),
            "manyPages": LP("row.completed", 3, "sample.pdf"),
            "onePending": LP("status.processing", 1),
            "manyPending": LP("status.processing", 3),
            "oneDone": LP("status.completed", 1),
            "manyDone": LP("status.completed", 3),
            "errors": L("status.with_errors", 2, 1)
        ]
    ]
    let output = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(output)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

// This mode is useful for repeatable integration checks of the shipped bundle.
if let modeIndex = CommandLine.arguments.firstIndex(of: "--convert") {
    let paths = Array(CommandLine.arguments.dropFirst(modeIndex + 1))
    let converter = Converter()
    let results: [ConversionResult] = paths.map { path in
        do {
            let result = try converter.convert(URL(fileURLWithPath: path))
            return ConversionResult(input: path, output: result.url.path, pages: result.pages, error: nil)
        } catch {
            return ConversionResult(input: path, output: nil, pages: nil, error: error.localizedDescription)
        }
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(results) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    exit(!paths.isEmpty && results.allSatisfy { $0.error == nil } ? 0 : 1)
}

final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var isHighlighted = false { didSet { needsDisplay = true } }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = files(sender).contains { ["doc", "docx"].contains($0.pathExtension.lowercased()) }
        isHighlighted = accepted
        return accepted ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { isHighlighted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        let urls = files(sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHighlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 16, yRadius: 16).fill()
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 8), xRadius: 16, yRadius: 16)
            border.lineWidth = 2
            border.stroke()
        }
    }
}

final class FileRow: NSStackView {
    let state = NSTextField(labelWithString: L("waiting"))
    let revealButton = NSButton()
    var output: URL?

    init(url: URL) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 12
        edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let icon = NSImageView(image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let text = NSStackView()
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        let title = NSTextField(labelWithString: url.lastPathComponent)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.toolTip = url.path
        state.font = .systemFont(ofSize: 11)
        state.textColor = .secondaryLabelColor
        state.lineBreakMode = .byTruncatingTail
        text.addArrangedSubview(title)
        text.addArrangedSubview(state)
        revealButton.image = NSImage(systemSymbolName: "folder", accessibilityDescription: L("reveal.accessibility"))
        revealButton.bezelStyle = .texturedRounded
        revealButton.toolTip = L("reveal.tooltip")
        revealButton.target = self
        revealButton.action = #selector(reveal)
        revealButton.isHidden = true
        addArrangedSubview(icon)
        addArrangedSubview(text)
        addArrangedSubview(revealButton)
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func reveal() {
        if let output { NSWorkspace.shared.activateFileViewerSelecting([output]) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let rows = NSStackView()
    let status = NSTextField(labelWithString: L("status.initial"))
    let spinner = NSProgressIndicator()
    let queue = DispatchQueue(label: "hu.kobak.pdf-keszito.convert", qos: .userInitiated)
    var pending = Set<String>()
    var outstanding = 0
    var successes = 0
    var failures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func setupMenu() {
        let bar = NSMenu()
        let appMenuItem = NSMenuItem()
        bar.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("menu.about"), action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        let files = NSMenuItem()
        let fileMenu = NSMenu(title: L("menu.file"))
        let openItem = NSMenuItem(title: L("menu.open"), action: #selector(selectFiles), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(withTitle: L("menu.close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        files.submenu = fileMenu
        bar.addItem(files)
        NSApplication.shared.mainMenu = bar
    }
    func setupWindow() {
        guard window == nil else { return }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = L("app.name")
        window.minSize = NSSize(width: 500, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.center()
        let root = DropView()
        root.onDrop = { [weak self] in self?.enqueue($0) }
        window.contentView = root
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])

        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")!
        let icon = NSImageView(image: NSImage(contentsOf: iconURL)!)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.heightAnchor.constraint(equalToConstant: 58).isActive = true
        stack.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: L("window.headline"))
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        stack.addArrangedSubview(title)
        let hint = NSTextField(labelWithString: L("window.hint"))
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        let button = NSButton(title: L("window.choose"), target: self, action: #selector(selectFiles))
        button.bezelStyle = .rounded
        button.controlSize = .large
        stack.addArrangedSubview(button)
        stack.setCustomSpacing(20, after: button)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rows)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            rows.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rows.topAnchor.constraint(equalTo: document.topAnchor),
            rows.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        footer.addArrangedSubview(spinner)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        footer.addArrangedSubview(status)
        stack.addArrangedSubview(footer)
        let note = NSTextField(labelWithString: L("window.collision_note"))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(note)
        window.makeKeyAndOrderFront(nil)
    }
    @objc func selectFiles() {
        let panel = NSOpenPanel()
        panel.title = L("panel.title")
        panel.prompt = L("panel.prompt")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "doc")!, UTType(filenameExtension: "docx")!]
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.enqueue(panel.urls) }
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { setupWindow() }
        enqueue(urls)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
    func enqueue(_ urls: [URL]) {
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        if outstanding == 0 { successes = 0; failures = 0 }
        for url in urls {
            let key = url.standardizedFileURL.path
            guard !pending.contains(key) else { continue }
            pending.insert(key)
            outstanding += 1
            let row = FileRow(url: url)
            rows.insertArrangedSubview(row, at: 0)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            queue.async { [weak self] in
                DispatchQueue.main.async { row.state.stringValue = L("row.processing") }
                let result = Result { try Converter().convert(url) }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pending.remove(key)
                    self.outstanding -= 1
                    switch result {
                    case .success(let converted):
                        self.successes += 1
                        row.output = converted.url
                        row.state.stringValue = LP("row.completed", converted.pages, converted.url.lastPathComponent)
                        row.state.toolTip = converted.url.path
                        row.state.textColor = .systemGreen
                        row.revealButton.isHidden = false
                    case .failure(let error):
                        self.failures += 1
                        row.state.stringValue = error.localizedDescription
                        row.state.toolTip = error.localizedDescription
                        row.state.textColor = .systemRed
                    }
                    self.updateStatus()
                }
            }
        }
        updateStatus()
    }
    func updateStatus() {
        if outstanding > 0 {
            spinner.startAnimation(nil)
            status.stringValue = LP("status.processing", outstanding)
        } else {
            spinner.stopAnimation(nil)
            status.stringValue = failures == 0 ? LP("status.completed", successes) : L("status.with_errors", successes, failures)
            NSSound(named: failures == 0 ? "Glass" : "Basso")?.play()
        }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if outstanding > 0 { sender.orderOut(nil); return false }
        NSApplication.shared.terminate(nil)
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard outstanding > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("quit.title")
        alert.informativeText = L("quit.message")
        alert.addButton(withTitle: L("ok"))
        alert.runModal()
        return .terminateCancel
    }
    @objc func about() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: L("app.name"),
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: L("about.credits"))
        ])
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
