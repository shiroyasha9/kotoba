import AppKit

/// A window of the demo's own, one of three plain kinds: a chat with its reply field, a terminal with a coding agent's
/// prompt, and a message with To and Subject. macOS draws all of it: the title bar, the glass toolbar, the text and the
/// caret. No app's icons, names or branding.
@MainActor
final class DemoWindow {
    enum Kind {
        case chat
        case terminal
        case message
    }

    let window: NSWindow
    private let body = NSTextView()
    private let caret = NSTextInsertionIndicator()
    private var toolbarTools: DemoToolbar?
    /// The text before the dictation, and the dictation, in the body's own font and color.
    private let before: NSAttributedString
    private let dictation: NSAttributedString
    /// The window on the stage, one capture for each text and caret.
    private var images: [State: CGImage] = [:]

    private struct State: Hashable {
        let isPasted: Bool
        let showsCaret: Bool
    }

    init(_ kind: Kind, dictation text: String, frame: NSRect, appearance: NSAppearance) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: frame.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        // A terminal keeps its own dark colors in either appearance, as most do.
        window.appearance = kind == .terminal ? NSAppearance(named: .darkAqua) : appearance
        let font: NSFont =
            kind == .terminal ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 16)
        dictation = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        before = Self.opening(of: kind, font: font)
        switch kind {
        case .chat:
            window.title = "Sam Rivera"
            toolbarTools = DemoToolbar([.flexibleSpace, .init("video"), .init("info")])
        case .terminal:
            window.title = "app"
        case .message:
            window.title = "Re: Friday review"
            toolbarTools = DemoToolbar([.init("send"), .flexibleSpace, .init("attach"), .init("format")])
        }
        if let toolbarTools {
            let toolbar = NSToolbar(identifier: "demo")
            toolbar.delegate = toolbarTools
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }
        window.setFrame(NSRect(origin: .zero, size: frame.size), display: false)
        let paper = Paper(
            frame: NSRect(origin: .zero, size: frame.size),
            color: kind == .terminal ? NSColor(srgbRed: 0.1, green: 0.11, blue: 0.13, alpha: 1) : .textBackgroundColor)
        window.contentView = paper
        let top = paper.bounds.height - window.contentLayoutRect.maxY
        body.font = font
        body.textColor = .labelColor
        body.drawsBackground = false
        switch kind {
        case .chat: layOutChat(in: paper, top: top)
        case .terminal:
            body.frame = NSRect(x: 0, y: top + 4, width: paper.bounds.width, height: paper.bounds.height - top - 4)
            body.textContainerInset = NSSize(width: 10, height: 8)
            paper.addSubview(body)
        case .message: layOutMessage(in: paper, top: top)
        }
        caret.displayMode = .hidden
        caret.color = kind == .terminal ? .labelColor : .controlAccentColor
        body.addSubview(caret)
        window.makeFirstResponder(body)
    }

    /// The text before the dictation: the agent's prompt in the terminal, the greeting in the message.
    private static func opening(of kind: Kind, font: NSFont) -> NSAttributedString {
        let ink: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let dim: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        switch kind {
        case .chat:
            return NSAttributedString()
        case .terminal:
            let lines = NSMutableAttributedString(string: "~/app on main\n$ agent\n", attributes: dim)
            lines.append(
                NSAttributedString(string: "Ready. Describe a change, or ask about the code.\n\n", attributes: ink))
            lines.append(NSAttributedString(string: "› ", attributes: dim))
            return lines
        case .message:
            return NSAttributedString(string: "Hi Maya,\n\n", attributes: ink)
        }
    }

    /// Two bubbles, the other person's question last, and the reply field at the bottom.
    private func layOutChat(in paper: NSView, top: CGFloat) {
        let width = paper.bounds.width
        var y = top + 18
        for (text, isMine) in [("Pushing the last fixes now.", true), ("Is the new onboarding ready to test?", false)] {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 15)
            label.textColor = isMine ? .white : .labelColor
            label.sizeToFit()
            let bubble = NSBox(
                frame: NSRect(
                    x: isMine ? width - label.frame.width - 44 : 16, y: y, width: label.frame.width + 28,
                    height: label.frame.height + 14))
            bubble.boxType = .custom
            bubble.borderWidth = 0
            bubble.cornerRadius = bubble.frame.height / 2
            bubble.fillColor = isMine ? .controlAccentColor : .secondarySystemFill
            bubble.contentViewMargins = NSSize(width: 14, height: 7)
            bubble.contentView = label
            paper.addSubview(bubble)
            y = bubble.frame.maxY + 8
        }
        let field = NSBox(frame: NSRect(x: 16, y: paper.bounds.height - 60, width: width - 32, height: 42))
        field.boxType = .custom
        field.borderColor = .separatorColor
        field.borderWidth = 1
        field.cornerRadius = 21
        field.fillColor = .clear
        paper.addSubview(field)
        body.frame = field.frame.insetBy(dx: 8, dy: 0)
        body.textContainerInset = NSSize(width: 4, height: 11)
        paper.addSubview(body)
    }

    /// To and Subject, each on a row with a line under it, and the body.
    private func layOutMessage(in paper: NSView, top: CGFloat) {
        let width = paper.bounds.width
        var y = top
        for (name, value) in [("To:", "Maya Chen"), ("Subject:", "Re: Friday review")] {
            let label = NSTextField(labelWithString: name)
            label.font = .systemFont(ofSize: 14)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(labelWithString: value)
            field.font = .systemFont(ofSize: 14)
            label.sizeToFit()
            field.sizeToFit()
            label.setFrameOrigin(NSPoint(x: 20, y: y + (36 - label.frame.height) / 2))
            field.setFrameOrigin(NSPoint(x: label.frame.maxX + 6, y: y + (36 - field.frame.height) / 2))
            let line = NSBox(frame: NSRect(x: 20, y: y + 36, width: width - 20, height: 1))
            line.boxType = .separator
            paper.addSubview(label)
            paper.addSubview(field)
            paper.addSubview(line)
            y += 37
        }
        body.frame = NSRect(x: 0, y: y + 6, width: width, height: paper.bounds.height - y - 6)
        body.textContainerInset = NSSize(width: 15, height: 8)
        paper.addSubview(body)
    }

    /// The window before or after the paste on the stage, with the caret at the text's end, shown or not.
    func onStage(isPasted: Bool, showsCaret: Bool, isDark: Bool) throws -> CGImage {
        let state = State(isPasted: isPasted, showsCaret: showsCaret)
        if let image = images[state] { return image }
        show(isPasted: isPasted, showsCaret: showsCaret)
        let image = try HeroDemo.onStage(window, isDark: isDark)
        images[state] = image
        return image
    }

    private func show(isPasted: Bool, showsCaret: Bool) {
        let text = NSMutableAttributedString(attributedString: before)
        if isPasted {
            text.append(dictation)
        }
        body.textStorage?.setAttributedString(text)
        let end = text.length
        body.setSelectedRange(NSRange(location: end, length: 0))
        body.layoutManager?.ensureLayout(for: body.textContainer ?? NSTextContainer())
        let screen = body.firstRect(forCharacterRange: NSRange(location: end, length: 0), actualRange: nil)
        let rect = body.convert(window.convertFromScreen(screen), from: nil)
        caret.frame = NSRect(x: rect.minX, y: rect.minY, width: 2, height: rect.height)
        caret.displayMode = showsCaret ? .visible : .hidden
        window.layoutIfNeeded()
        // The caret fades in and out on screen; a frame shows it on or off.
        SnapshotCapture.endAnimations(in: window)
    }
}

/// The window's background, edge to edge under the glass toolbar.
private final class Paper: NSView {
    private let color: NSColor

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Paper is built in code")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

/// The toolbar's tools, in order, each an SF Symbol.
private final class DemoToolbar: NSObject, NSToolbarDelegate {
    private static let tools = [
        "send": ("paperplane", "Send"), "attach": ("paperclip", "Attach"), "format": ("textformat", "Format"),
        "video": ("video", "Video Call"), "info": ("info.circle", "Info"),
    ]
    private let items: [NSToolbarItem.Identifier]

    init(_ items: [NSToolbarItem.Identifier]) {
        self.items = items
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let (symbol, label) = Self.tools[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.isBordered = true
        // A tool with an action draws enabled.
        item.target = self
        item.action = #selector(use)
        return item
    }

    @objc private func use(_ sender: Any?) {}
}
