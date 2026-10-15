import AppKit
import KotobaCore
import KotobaProviders

/// The pill's content view: the glass, the state row and the drag handling. Everything except the
/// Undo button is a drag handle; a press that does not move past the drag threshold does nothing.
final class IndicatorPillView: NSView {
    enum Layout {
        /// The state dot, the text, the level and Undo in a row.
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
        var showsMeter = false
        var showsSpinner = false
        /// Only the state dot and the level, so the pill stands vertical at a side edge.
        var isCompact = false
        var offersUndo = false
        /// A message that hides after a few seconds.
        var hidesSoon = false
    }

    var level: CGFloat {
        get { meter.level }
        set { meter.level = newValue }
    }
    var onUndo: (() -> Void)? {
        get { undoButton.onClick }
        set { undoButton.onClick = newValue }
    }
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var content = Content() {
        didSet {
            label.stringValue = content.text
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
    private let undoButton = FirstClickButton(title: "Undo")
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
        undoButton.bezelStyle = .glass
        undoButton.controlSize = .small
        dragIcon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "kotoba")
        dragIcon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        dragIcon.contentTintColor = .labelColor

        // Centered in both orientations; hidden views leave the stack.
        stack.setViews([dot, label, meter, spinner, undoButton, dragIcon], in: .center)
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
        undoButton.isHidden = layout != .horizontal || !content.offersUndo
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
        return hit.isDescendant(of: undoButton) ? hit : self
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

/// A button that acts on the first click in a window that is not key, so Undo works without
/// activating kotoba.
private final class FirstClickButton: NSButton {
    var onClick: (() -> Void)?

    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
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

// MARK: - Snapshots

extension IndicatorPanel {
    /// Each state the owner reads, at each anchor, plus the dragged pill.
    static func snapshots() -> [Snapshot] {
        let indicator = IndicatorPanel(longRecordingWarning: .seconds(600))
        struct Row {
            let name: String
            let state: DictationState
            var secureInput = false
        }
        let rows = [
            Row(name: "recording", state: .recording(isLong: false)),
            Row(name: "recording-long", state: .recording(isLong: true)),
            Row(name: "secure-input", state: .recording(isLong: false), secureInput: true),
            Row(name: "transcribing", state: .transcribing),
            Row(name: "failed", state: .failed(DictationID())),
            Row(name: "needs-key", state: .needsSetup(DictationID(), .key)),
            Row(name: "needs-endpoint", state: .needsSetup(DictationID(), .endpoint)),
            Row(name: "cancelled", state: .undoable),
        ]
        var snapshots = [
            Snapshot(name: "indicator-drag") { PillStandIn(content: .init(), anchor: nil) }
        ]
        for row in rows {
            // Azure has the longest name, so its texts are the widest.
            guard let content = indicator.content(for: row.state, secureInput: row.secureInput, provider: .azure)
            else { continue }
            for anchor in IndicatorAnchor.allCases {
                snapshots.append(
                    Snapshot(name: "indicator-\(row.name)-\(anchor.rawValue)") {
                        PillStandIn(content: content, anchor: anchor)
                    })
            }
        }
        return snapshots
    }
}

/// The pill over a capsule in the window color, since its glass does not render offscreen.
private final class PillStandIn: NSView {
    /// A nil anchor shows the dragged pill.
    init(content: IndicatorPillView.Content, anchor: IndicatorAnchor?) {
        let pill = IndicatorPillView(frame: .zero)
        pill.content = content
        pill.level = 0.6
        let frame: ScreenRect
        if let anchor {
            pill.layout =
                IndicatorPlacement.isVertical(at: anchor, isCompact: content.isCompact) ? .vertical : .horizontal
            // Only the size matters here, so any visible frame does.
            frame = IndicatorPlacement.frame(
                at: anchor, isCompact: content.isCompact, contentWidth: pill.fittingWidth,
                in: ScreenRect(x: 0, y: 0, width: 1512, height: 945))
        } else {
            pill.layout = .drag
            frame = IndicatorPlacement.dragFrame(centeredAt: ScreenPoint(x: 0, y: 0))
        }
        super.init(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        pill.frame = bounds
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillStandIn is built in code")
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = IndicatorPlacement.cornerRadius
        let capsule = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.controlBackgroundColor.setFill()
        capsule.fill()
        NSColor.separatorColor.setStroke()
        capsule.stroke()
    }
}
