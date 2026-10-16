import AppKit
import KotobaCore
import SwiftUI

/// The pill's own timer, the one its bar shows.
struct PillTimer {
    enum Kind {
        /// The pill hides when the time runs out: a message.
        case hidesPill
        /// The pipeline owns the time (the Esc Undo window): hover holds it there too, and the pipeline ends the pill.
        case followsUndoWindow
    }

    var duration: Duration
    var kind = Kind.hidesPill
}

/// The pill's content view: the glass, the state row, the countdown bar and the drag handling. Everything
/// except the action button is a drag handle; a press that does not move past the drag threshold is a click,
/// which starts or stops a dictation only on a clickable pill.
final class IndicatorPillView: NSView {
    enum Layout {
        /// The state dot, the text, the level and the action button in a row.
        case horizontal
        /// The state dot over a vertical level, at a side edge.
        case vertical
        /// A small round waveform: the idle pill, and the pill under the pointer during a drag.
        case round
    }

    /// What the pill shows.
    struct Content {
        var text = ""
        var color = NSColor.secondaryLabelColor
        /// An SF Symbol in place of the state dot.
        var symbol: String?
        var toolTip: String?
        var showsMeter = false
        var showsSpinner = false
        /// Only the state dot and the level, so the pill stands vertical at a side edge.
        var isCompact = false
        /// The small round idle pill.
        var isRound = false
        /// What a click on the pill (not its button) does, as a chord tap; nil: nothing.
        var click: PillClick?
        var action: PillAction?
        var timer: PillTimer?
    }

    var level: CGFloat {
        get { meter.level }
        set { meter.level = newValue }
    }
    var onAction: ((PillAction) -> Void)?
    /// A click on a clickable pill, not a drag.
    var onClick: (() -> Void)?
    /// The pointer entered (true) or left (false) the pill.
    var onHoverChanged: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var content = Content() {
        didSet {
            label.stringValue = content.text
            toolTip = content.toolTip
            actionButton.rootView.title = content.action?.title ?? ""
            symbolView.image = content.symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: nil)
            }
            // Interactive glass answers the pointer, so a clickable pill looks like one.
            if #available(macOS 27, *) {
                glass.effectIsInteractive = content.click != nil
            }
            updateColors()
            applyLayout()
            // The click button comes and goes with the state; VoiceOver reads the pill's children again.
            if content.click != oldValue.click {
                NSAccessibility.post(element: self, notification: .layoutChanged)
            }
        }
    }
    var layout = Layout.horizontal {
        didSet { applyLayout() }
    }
    /// The timer the bar shows; nil hides the bar. The bar shows only on a pill with a button.
    var countdown: Countdown? {
        didSet {
            bar.countdown = countdown
            applyLayout()
        }
    }

    private let glass = NSGlassEffectView()
    private let meter = LevelMeter()
    private let bar = CountdownBar()
    private let stack = NSStackView()
    /// Lifts the row while the bar shows under it.
    private lazy var stackBottom = stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    /// The glass's content: the row, and the bar under it.
    private let container = NSView()
    private let dot = NSImageView(
        image: NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) ?? NSImage())
    private let symbolView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let actionButton = FirstClickHostingView(rootView: PillButton())
    private lazy var tapElement = PillTapElement(pill: self)
    private let spinner = NSProgressIndicator()
    private let roundIcon = NSImageView()
    private var pressStart: NSPoint?
    private var isDragging = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        dot.symbolConfiguration = .init(pointSize: 10, weight: .regular)
        // The text says the state; VoiceOver would read the dot as "Circle" and the symbol by its name.
        dot.setAccessibilityElement(false)
        symbolView.setAccessibilityElement(false)
        symbolView.symbolConfiguration = .init(textStyle: .body)
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        // At the pill's widest the text truncates before anything else gives way.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        actionButton.sizingOptions = .intrinsicContentSize
        actionButton.rootView.onClick = { [weak self] in
            guard let action = self?.content.action else { return }
            self?.onAction?(action)
        }
        roundIcon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "kotoba")
        roundIcon.symbolConfiguration = .init(textStyle: .title3)
        roundIcon.contentTintColor = .labelColor

        // Centered in both orientations; hidden views leave the stack.
        stack.setViews([dot, symbolView, label, meter, spinner, actionButton, roundIcon], in: .center)
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        container.addSubview(bar)
        // The bar runs along the bottom between the capsule's round ends.
        let inset = IndicatorPlacement.cornerRadius
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stackBottom,
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
            bar.heightAnchor.constraint(equalToConstant: CountdownBar.thickness),
        ])

        glass.frame = bounds
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = IndicatorPlacement.cornerRadius
        glass.contentView = container
        addSubview(glass)
        trackPointer(isInside: false)
        applyLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("IndicatorPillView is built in code")
    }

    private func updateColors() {
        dot.contentTintColor = content.color
        symbolView.contentTintColor = content.color
        roundIcon.contentTintColor = content.isRound && layout == .round ? .secondaryLabelColor : .labelColor
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
        let isRound = layout == .round
        let isHorizontal = layout == .horizontal
        let showsBar = isHorizontal && content.action != nil && countdown != nil
        stack.orientation = layout == .vertical ? .vertical : .horizontal
        stack.alignment = layout == .vertical ? .centerX : .centerY
        stack.edgeInsets =
            switch layout {
            case .horizontal: NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
            case .vertical: NSEdgeInsets(top: 14, left: 0, bottom: 14, right: 0)
            case .round: NSEdgeInsets()
            }
        meter.isVertical = layout == .vertical
        dot.isHidden = isRound || content.symbol != nil
        symbolView.isHidden = isRound || content.symbol == nil
        label.isHidden = !isHorizontal
        meter.isHidden = isRound || !content.showsMeter
        actionButton.isHidden = !isHorizontal || content.action == nil
        bar.isHidden = !showsBar
        stackBottom.constant = showsBar ? -6 : 0
        spinner.isHidden = isRound || !content.showsSpinner
        if spinner.isHidden {
            spinner.stopAnimation(nil)
        } else {
            spinner.startAnimation(nil)
        }
        roundIcon.isHidden = !isRound
        updateColors()
    }

    // MARK: Accessibility

    /// The pill's click for VoiceOver: a button beside the pill's text and its action button, never around them, so
    /// "Choose Mic…" stays its own button with its own press. The waveform of the round idle pill is then left out: the
    /// button says what it does.
    override func accessibilityChildren() -> [Any]? {
        let children = super.accessibilityChildren() ?? []
        guard let click = content.click else { return children }
        tapElement.setAccessibilityLabel(StatusText.pillClickLabel(click))
        return [tapElement] + children.filter { $0 as AnyObject !== roundIcon && $0 as AnyObject !== roundIcon.cell }
    }

    // MARK: Mouse

    /// Starts hover tracking again. A pill that appears under a still pointer gets no mouse-entered event; with
    /// `isInside` the area assumes the pointer is in, so leaving still sends mouse-exited and ends a hold.
    func trackPointer(isInside: Bool) {
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // kotoba is never the active app, so hover must work while it is inactive.
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if isInside {
            options.insert(.assumeInside)
        }
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

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
        } else if pressStart != nil, content.click != nil {
            onClick?()
        }
        pressStart = nil
        isDragging = false
    }
}
