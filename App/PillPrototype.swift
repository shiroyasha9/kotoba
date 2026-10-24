import AppKit
import KotobaCore
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

    /// The capsule; read by hover (PillPrototypeInput.swift).
    let glass = NSGlassEffectView()
    /// The content; read by VoiceOver (PillPrototypeInput.swift).
    let stack = NSStackView()
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
        // A button and the keycaps keep their full width; only the words give way, so a message too long for the
        // pill truncates its words every time, and the snapshot check sees it (owner trial: the button gave way on
        // the first layout and not on the next).
        for host in [cancel, stop, button] as [NSView] + [keycaps] {
            (host as? PillFillButtonHost)?.sizingOptions = .intrinsicContentSize
            host.setContentCompressionResistancePriority(.required, for: .horizontal)
            host.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        cancel.rootView.onClick = { [weak self] in self?.onAction?(.cancel) }
        stop.rootView.onClick = { [weak self] in self?.onAction?(.stop) }
        button.rootView.onClick = { [weak self] in self?.onAction?(.button) }
        stack.spacing = PillGeometry.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        // The content keeps the size of the look's capsule, centred, so it never reflows while the glass morphs
        // (a reflow cut the words to "No sound fro…" mid-morph, owner trial 2026-10-24).
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor), stackWidth, stackHeight,
        ])
        // The lone check is centred by its image's frame, not through the stack: the stack centres a symbol's
        // alignment rect, which sits off its drawn centre.
        check.frame = container.bounds
        check.autoresizingMask = [.width, .height]
        check.imageAlignment = .alignCenter
        container.addSubview(check)
        glass.contentView = container
        addSubview(glass)
        // One area over the view, kept in its visible rect by AppKit: the pointer's moves decide hover.
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        )
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

    private lazy var stackWidth = stack.widthAnchor.constraint(equalToConstant: 0)
    private lazy var stackHeight = stack.heightAnchor.constraint(equalToConstant: 0)
    /// What the look's content needs along the capsule, ends included; set by `apply`.
    private var contentLength: CGFloat = 0

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
            let length = min(PillGeometry.maxLength, max(height, contentLength))
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
        let isNewContent = views != stack.arrangedSubviews
        stack.orientation = isVertical ? .vertical : .horizontal
        stack.alignment = isVertical ? .centerX : .centerY
        stack.setViews(views, in: .center)
        stack.edgeInsets = edgeInsets(for: views)
        contentLength = naturalLength()
        let size = shapeSize
        stackWidth.constant = size.width
        stackHeight.constant = size.height
        check.isHidden = look != .done
        drawCheck(isShown: look == .done && old != .done)
        toolTip = look == .idle || look.isHover ? StatusText.idlePillHelp : help(for: look)
        setAccessibilityRole(look == .idle || look.isHover ? .button : .group)
        setAccessibilityLabel(look.accessibilityLabel)
        NSAccessibility.post(element: self, notification: .layoutChanged)
        invalidateIntrinsicContentSize()
        morph(fadesContentIn: isNewContent)
    }

    /// The content's natural length along the capsule, ends included: the stack's fitting size without the
    /// look's size.
    private func naturalLength() -> CGFloat {
        NSLayoutConstraint.deactivate([stackWidth, stackHeight])
        defer { NSLayoutConstraint.activate([stackWidth, stackHeight]) }
        let fitting = stack.fittingSize
        return isVertical ? fitting.height : fitting.width
    }

    /// The views `look` shows, in order, filled with its words.
    private func views(for look: PillLook) -> [NSView] {
        switch look {
        case .idle: return []
        case .done: return []
        case .processing:
            bars.color = PillBars.level
            return [bars]
        case .hover(let keys):
            // A chord never shows alone: the word says what it starts (owner, 2026-10-25).
            keycaps.rootView = PillKeycaps(keys: keys)
            label.stringValue = PillLook.dictate
            return [label, keycaps]
        case .recording(let recording): return views(for: recording)
        case .message(let message):
            label.stringValue = message.text
            button.rootView.face = .text(message.button ?? "")
            return (message.isProblem ? [warning] : []) + [label] + (message.button == nil ? [] : [button])
        }
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

    /// The glass moves to the new shape with one animation per change; offscreen it jumps. New content fades in once
    /// the glass has its shape, so no item shows outside the glass mid-morph; the same content (a new level, the
    /// timer's next second) does not fade.
    private func morph(fadesContentIn: Bool) {
        guard window?.isVisible == true else {
            needsLayout = true
            return
        }
        layoutSubtreeIfNeeded()
        isMorphing = true
        if fadesContentIn {
            stack.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            context.allowsImplicitAnimation = true
            placeGlass()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isMorphing = false
                guard let stack = self?.stack, stack.alphaValue < 1 else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    stack.animator().alphaValue = 1
                }
            }
        }
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

    /// The content is longer than the capsule, so an item sits outside it. Valid after layout.
    var isOverflowing: Bool {
        let content = stack.arrangedSubviews.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        return !content.isNull && !stack.bounds.insetBy(dx: -0.5, dy: -0.5).contains(content)
    }

    /// The content needs more than the longest pill, so its words cannot all show.
    var isTooLong: Bool {
        contentLength > PillGeometry.maxLength + 0.5
    }

    /// The words end in "…" because the pill is at its longest. Valid after layout.
    var isTextTruncated: Bool {
        stack.arrangedSubviews.contains(label) && label.intrinsicContentSize.width > label.frame.width + 0.5
    }
}

// MARK: Content

extension PillPrototypeView {
    /// The help tag of a look with words that need the why: Secure Input.
    private func help(for look: PillLook) -> String? {
        guard case .recording(let recording) = look, recording.isSecureInputOn, !recording.isSilent else { return nil }
        return DictationState.secureInputHelp
    }

    private func views(for recording: PillRecording) -> [NSView] {
        bars.color = recording.isSilent ? .systemOrange : PillBars.level
        var views: [NSView] = []
        // Silent and hands-free, the words and Choose Mic… need Cancel's room; Esc still cancels.
        if recording.isHandsFree, !recording.isSilent { views.append(cancel) }
        if recording.isCleaned { views.append(wand) }
        views.append(bars)
        if let time = recording.elapsed {
            elapsed.stringValue = time.formatted(.time(pattern: .minuteSecond))
            views.append(elapsed)
        }
        if recording.isSecureInputOn, !recording.isSilent {
            label.stringValue = PillRecording.secureInput
            views.append(label)
        }
        if recording.isSilent {
            label.stringValue = StatusText.noSound
            button.rootView.face = .text("Choose Mic…")
            views += [label, button]
        }
        if recording.isHandsFree { views.append(stop) }
        return views
    }
}
