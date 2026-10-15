import AppKit
import KotobaCore

/// The one button a pill can carry. AppDelegate maps each action to its handler.
enum PillAction: Sendable {
    case undo
    case retry
    case addKey
    case openSpeechSettings
    case addCredit
    case copy
    case allowPasting
    case openMicrophoneSettings

    var title: String {
        switch self {
        case .undo: "Undo"
        case .retry: "Retry"
        case .addKey: "Add Key…"
        case .openSpeechSettings: "Settings…"
        case .addCredit: "Add Credit…"
        case .copy: "Copy"
        case .allowPasting: "Allow Pasting…"
        case .openMicrophoneSettings: "Open System Settings…"
        }
    }
}

/// The pill's content view: the glass, the state row and the drag handling. Everything except the
/// action button is a drag handle; a press that does not move past the drag threshold does nothing.
final class IndicatorPillView: NSView {
    enum Layout {
        /// The state dot, the text, the level and the action button in a row.
        case horizontal
        /// The state dot over a vertical level, at a side edge.
        case vertical
        /// A small round waveform under the pointer.
        case drag
    }

    /// What the pill shows.
    struct Content {
        var text = ""
        var color = NSColor.secondaryLabelColor
        var toolTip: String?
        var showsMeter = false
        var showsSpinner = false
        /// Only the state dot and the level, so the pill stands vertical at a side edge.
        var isCompact = false
        var action: PillAction?
        /// A message that hides after a few seconds.
        var hidesSoon = false
    }

    var level: CGFloat {
        get { meter.level }
        set { meter.level = newValue }
    }
    var onAction: ((PillAction) -> Void)?
    /// The pointer entered (true) or left (false) the pill.
    var onHoverChanged: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var content = Content() {
        didSet {
            label.stringValue = content.text
            toolTip = content.toolTip
            actionButton.title = content.action?.title ?? ""
            updateDotColor()
            applyLayout()
        }
    }
    var layout = Layout.horizontal {
        didSet { applyLayout() }
    }

    private let meter = LevelMeter()
    private let stack = NSStackView()
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let actionButton = FirstClickButton()
    private let spinner = NSProgressIndicator()
    private let dragIcon = NSImageView()
    private var pressStart: NSPoint?
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        // At the pill's widest the text truncates before anything else gives way.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        actionButton.bezelStyle = .glass
        actionButton.controlSize = .small
        actionButton.onClick = { [weak self] in
            guard let action = self?.content.action else { return }
            self?.onAction?(action)
        }
        dragIcon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "kotoba")
        dragIcon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        dragIcon.contentTintColor = .labelColor

        // Centered in both orientations; hidden views leave the stack.
        stack.setViews([dot, label, meter, spinner, actionButton, dragIcon], in: .center)
        stack.spacing = 8
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
        ])

        let glass = NSGlassEffectView(frame: bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = IndicatorPlacement.cornerRadius
        glass.contentView = stack
        addSubview(glass)
        // kotoba is never the active app, so hover must work while it is inactive.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        applyLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IndicatorPillView is built in code")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateDotColor()
    }

    private func updateDotColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dot.layer?.backgroundColor = content.color.cgColor
        }
    }

    /// The width the horizontal layout needs for the current content.
    var fittingWidth: CGFloat {
        stack.fittingSize.width
    }

    /// The label is narrower than its text, so the text ends in "…". Valid after layout.
    var isTextTruncated: Bool {
        !label.isHidden && label.intrinsicContentSize.width > label.frame.width + 0.5
    }

    private func applyLayout() {
        let isDrag = layout == .drag
        stack.orientation = layout == .vertical ? .vertical : .horizontal
        stack.alignment = layout == .vertical ? .centerX : .centerY
        stack.edgeInsets =
            switch layout {
            case .horizontal: NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            case .vertical: NSEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
            case .drag: NSEdgeInsets()
            }
        meter.isVertical = layout == .vertical
        dot.isHidden = isDrag
        label.isHidden = layout != .horizontal
        meter.isHidden = isDrag || !content.showsMeter
        actionButton.isHidden = layout != .horizontal || content.action == nil
        spinner.isHidden = isDrag || !content.showsSpinner
        if spinner.isHidden {
            spinner.stopAnimation(nil)
        } else {
            spinner.startAnimation(nil)
        }
        dragIcon.isHidden = !isDrag
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: actionButton) ? hit : self
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        pressStart = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressStart else { return }
        let point = NSEvent.mouseLocation
        if !isDragging {
            guard IndicatorPlacement.isDrag(from: ScreenPoint(pressStart), to: ScreenPoint(point)) else { return }
            isDragging = true
            onDragBegan?()
        }
        onDragMoved?(point)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?(NSEvent.mouseLocation)
        }
        pressStart = nil
        isDragging = false
    }
}

/// A bar whose filled part follows the mic level: left to right, or bottom to top when vertical.
private final class LevelMeter: NSView {
    private static let length: CGFloat = 56
    private static let thickness: CGFloat = 6

    private let fill = CALayer()
    private lazy var horizontalConstraints = [
        widthAnchor.constraint(equalToConstant: Self.length),
        heightAnchor.constraint(equalToConstant: Self.thickness),
    ]
    private lazy var verticalConstraints = [
        widthAnchor.constraint(equalToConstant: Self.thickness),
        heightAnchor.constraint(equalToConstant: Self.length),
    ]

    var level: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    var isVertical = false {
        didSet {
            guard isVertical != oldValue else { return }
            NSLayoutConstraint.deactivate(isVertical ? horizontalConstraints : verticalConstraints)
            NSLayoutConstraint.activate(isVertical ? verticalConstraints : horizontalConstraints)
            needsLayout = true
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        fill.cornerRadius = 3
        fill.backgroundColor = NSColor.labelColor.cgColor
        layer?.addSublayer(fill)
        NSLayoutConstraint.activate(horizontalConstraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LevelMeter is built in code")
    }

    override func layout() {
        super.layout()
        let level = max(0, min(1, level))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        fill.frame =
            isVertical
            ? CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * level)
            : CGRect(x: 0, y: 0, width: bounds.width * level, height: bounds.height)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            fill.backgroundColor = NSColor.labelColor.cgColor
        }
    }
}

/// A button that acts on the first click in a window that is not key, so a pill action works
/// without activating kotoba.
private final class FirstClickButton: NSButton {
    var onClick: (() -> Void)?

    convenience init() {
        self.init(frame: .zero)
        target = self
        action = #selector(clicked)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    @objc private func clicked() {
        onClick?()
    }
}
