import AppKit
import SwiftUI

// The 0.5.0 indicator pill, as a prototype next to today's `IndicatorPillView` (docs/research/ui-redesign.md, "Pill"):
// one glass capsule that changes shape, no status words, words only when the owner must know or can act. The owner
// approves it in the gallery (`PillPrototypeGallery`); the prototype goes when the pill is rebuilt on it.

/// The prototype pill: one `NSGlassEffectView` capsule centred in the view, sized to the look. Nothing in it has glass
/// of its own. At idle it does no work: no timer, display link or animation; hover is a tracking area.
final class PillPrototypeView: NSView {
    enum Action {
        case click, cancel, stop, button
    }

    var look = PillLook.idle {
        didSet {
            guard look != oldValue else { return }
            apply(from: oldValue)
        }
    }
    /// Vertical at a side edge, for a look that can stand vertical.
    var isAtSideEdge = false {
        didSet { if isAtSideEdge != oldValue { apply(from: look) } }
    }
    /// The keys the idle bar shows on hover; empty: no hover state.
    var hoverKeys: [String] = []
    var level: CGFloat {
        get { bars.level }
        set { bars.level = newValue }
    }
    var onAction: ((Action) -> Void)?

    private let glass = NSGlassEffectView()
    private let stack = NSStackView()
    private let bars = PillBars()
    private let wand = PillPrototypeView.symbolView("wand.and.sparkles", color: .labelColor)
    private let warning = PillPrototypeView.symbolView("exclamationmark.triangle.fill", color: .systemOrange)
    private let check = PillPrototypeView.symbolView("checkmark", color: .systemGreen, weight: .semibold)
    private let label = NSTextField(labelWithString: "")
    private let elapsed = NSTextField(labelWithString: "")
    private let keycaps = NSHostingView(rootView: PillKeycaps())
    private let cancel = PillFillButtonHost(rootView: PillFillButton(face: .symbol("xmark", label: "Cancel")))
    private let stop = PillFillButtonHost(
        rootView: PillFillButton(face: .symbol("stop.fill", label: "Stop"), isProminent: true))
    private let button = PillFillButtonHost(rootView: PillFillButton())

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        // At the pill's longest the words truncate before anything else gives way.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        elapsed.font = .monospacedDigitSystemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
        elapsed.textColor = .secondaryLabelColor
        for view in [label, elapsed] {
            view.setAccessibilityElement(false)
        }
        keycaps.sizingOptions = .intrinsicContentSize
        for host in [cancel, stop, button] {
            host.sizingOptions = .intrinsicContentSize
        }
        cancel.rootView.onClick = { [weak self] in self?.onAction?(.cancel) }
        stop.rootView.onClick = { [weak self] in self?.onAction?(.stop) }
        button.rootView.onClick = { [weak self] in self?.onAction?(.button) }
        stack.spacing = PillGeometry.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        glass.contentView = container
        addSubview(glass)
        addTrackingArea(
            NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        apply(from: look)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillPrototypeView is built in code")
    }

    private static func symbolView(_ name: String, color: NSColor, weight: NSFont.Weight? = nil) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage())
        // The same text style as the words beside it, so symbol and text weights match; the lone check is bolder.
        var configuration = NSImage.SymbolConfiguration(textStyle: .body, scale: weight == nil ? .medium : .large)
        if let weight {
            configuration = configuration.applying(.init(pointSize: 0, weight: weight, scale: .large))
        }
        view.symbolConfiguration = configuration
        view.contentTintColor = color
        view.setAccessibilityElement(false)
        return view
    }

    var isVertical: Bool { isAtSideEdge && look.canStandVertical }

    /// The capsule's size for the look: idle is the bar, done a circle, the rest as long as the content.
    var shapeSize: NSSize {
        let height = PillGeometry.height
        switch look {
        case .idle:
            return isVertical
                ? NSSize(width: PillGeometry.idleThickness, height: PillGeometry.idleLength)
                : NSSize(width: PillGeometry.idleLength, height: PillGeometry.idleThickness)
        case .done: return NSSize(width: height, height: height)
        default:
            let fitting = stack.fittingSize
            let length = min(PillGeometry.maxLength, max(height, isVertical ? fitting.height : fitting.width))
            return isVertical ? NSSize(width: height, height: length) : NSSize(width: length, height: height)
        }
    }

    override var intrinsicContentSize: NSSize { shapeSize }

    override func layout() {
        super.layout()
        if !isMorphing {
            placeGlass()
        }
    }

    private var isMorphing = false

    private func placeGlass() {
        let size = shapeSize
        glass.frame = NSRect(
            x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width,
            height: size.height)
        glass.cornerRadius = min(size.width, size.height) / 2
    }

    /// Shows the views the look needs, in order, and moves the capsule to its new shape: animated on screen, at once
    /// offscreen and for the first look.
    private func apply(from old: PillLook) {
        bars.isVertical = isVertical
        bars.isSweeping = look == .processing
        let views = views(for: look)
        stack.orientation = isVertical ? .vertical : .horizontal
        stack.alignment = isVertical ? .centerX : .centerY
        stack.setViews(views, in: .center)
        stack.edgeInsets = edgeInsets(for: views)
        drawCheck(isShown: look == .done && old != .done)
        toolTip = look == .idle || look.isHover ? StatusText.idlePillHelp : nil
        setAccessibilityRole(look == .idle || look.isHover ? .button : .group)
        setAccessibilityLabel(look.accessibilityLabel)
        NSAccessibility.post(element: self, notification: .layoutChanged)
        invalidateIntrinsicContentSize()
        morph()
    }

    /// The views `look` shows, in order, filled with its words.
    private func views(for look: PillLook) -> [NSView] {
        switch look {
        case .idle: return []
        case .done: return [check]
        case .processing:
            bars.color = .controlAccentColor
            return [bars]
        case .hover(let keys):
            keycaps.rootView = PillKeycaps(keys: keys, axis: isVertical ? .vertical : .horizontal)
            return [keycaps]
        case .recording(let recording): return views(for: recording)
        case .message(let message):
            label.stringValue = message.text
            button.rootView.face = .text(message.button ?? "")
            return (message.isProblem ? [warning] : []) + [label] + (message.button == nil ? [] : [button])
        }
    }

    private func views(for recording: PillRecording) -> [NSView] {
        bars.color = recording.isSilent ? .systemOrange : .controlAccentColor
        var views: [NSView] = []
        // Silent and hands-free, the words and Choose Mic… need Cancel's room; Esc still cancels.
        if recording.isHandsFree, !recording.isSilent { views.append(cancel) }
        if recording.isCleaned { views.append(wand) }
        views.append(bars)
        if let time = recording.elapsed {
            elapsed.stringValue = time.formatted(.time(pattern: .minuteSecond))
            views.append(elapsed)
        }
        if recording.isSilent {
            label.stringValue = StatusText.noSound
            button.rootView.face = .text("Choose Mic…")
            views += [label, button]
        }
        if recording.isHandsFree { views.append(stop) }
        return views
    }

    /// The ends: a button keeps `inset` from the capsule's end, anything else `endPadding`.
    private func edgeInsets(for views: [NSView]) -> NSEdgeInsets {
        func end(_ view: NSView?) -> CGFloat {
            view is PillFillButtonHost ? PillGeometry.inset : PillGeometry.endPadding
        }
        let first = end(views.first)
        let last = end(views.last)
        return isVertical
            ? NSEdgeInsets(top: first, left: 0, bottom: last, right: 0)
            : NSEdgeInsets(top: 0, left: first, bottom: 0, right: last)
    }

    /// The check draws itself on (SF Symbols' draw effect) when a dictation is pasted; a one-shot animation.
    private func drawCheck(isShown: Bool) {
        check.removeAllSymbolEffects(animated: false)
        guard isShown, window != nil else { return }
        check.addSymbolEffect(.drawOn, animated: false)
        check.removeSymbolEffect(ofType: .drawOn, animated: true)
    }

    /// The glass moves to the new shape with one animation per change; offscreen it jumps.
    private func morph() {
        guard window?.isVisible == true else {
            needsLayout = true
            return
        }
        layoutSubtreeIfNeeded()
        isMorphing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            context.allowsImplicitAnimation = true
            placeGlass()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.isMorphing = false }
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        true
    }

    /// The buttons the look shows; the bars, words and symbols are in the pill's label.
    override func accessibilityChildren() -> [Any]? {
        stack.arrangedSubviews.filter { $0 is PillFillButtonHost && !$0.isHidden }
    }

    override func accessibilityPerformPress() -> Bool {
        guard accessibilityRole() == .button else { return false }
        onAction?(.click)
        return true
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        if look == .idle, !hoverKeys.isEmpty {
            look = .hover(keys: hoverKeys)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if look.isHover, !hoverKeys.isEmpty {
            look = .idle
        }
    }

    override func mouseUp(with event: NSEvent) {
        onAction?(.click)
    }

    /// Every layer under the pill with a running animation: the idle-cost check wants none at idle.
    var animatedLayers: [CALayer] {
        // A view's layer is also its parent view's sublayer, so each layer counts once.
        var seen = Set<ObjectIdentifier>()
        func walk(_ layer: CALayer) -> [CALayer] {
            guard seen.insert(ObjectIdentifier(layer)).inserted else { return [] }
            let own = (layer.animationKeys() ?? []).isEmpty ? [] : [layer]
            return own + (layer.sublayers ?? []).flatMap(walk)
        }
        func walk(_ view: NSView) -> [CALayer] {
            (view.layer.map(walk) ?? []) + view.subviews.flatMap(walk)
        }
        return walk(self)
    }

    /// The content is longer than the capsule, so an end item sits outside it. Valid after layout.
    var isOverflowing: Bool {
        isVertical
            ? stack.frame.height > glass.bounds.height + 0.5 : stack.frame.width > glass.bounds.width + 0.5
    }

    /// The words end in "…" because the pill is at its longest. Valid after layout.
    var isTextTruncated: Bool {
        stack.arrangedSubviews.contains(label) && label.intrinsicContentSize.width > label.frame.width + 0.5
    }
}
