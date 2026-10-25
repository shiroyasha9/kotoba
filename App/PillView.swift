import AppKit
import KotobaCore
import SwiftUI

/// The indicator pill (docs/research/ui-redesign.md, "Pill"): one `NSGlassEffectView` capsule that changes shape, no
/// status words, words only when the owner must know something or can act. The view covers the pill window's room
/// (`IndicatorPlacement.room`), so the capsule changes shape inside it and the window does not move. Nothing in it has
/// glass of its own. A look change flows the glass to its new shape with one spring (`morph`). At idle it does no work:
/// no timer, display link or animation; hover is a tracking area.
final class PillView: NSView {
    enum Action {
        /// A click on the capsule, not on a button.
        case click
        case cancel
        case stop
        /// The look's fix or Undo button.
        case button
    }

    var look = PillLook.idle {
        didSet {
            guard look != oldValue else { return }
            apply(from: oldValue)
        }
    }
    /// Where the pill sits: the capsule's edge and centre line in the room, and vertical at a side edge for a look
    /// that can stand vertical.
    var anchor = IndicatorAnchor.bottomCenter {
        didSet { if anchor != oldValue { apply(from: look) } }
    }
    /// A click on the capsule is a chord tap (`PillContent.click`); VoiceOver gets the idle pill as a button then.
    var isClickable = false {
        didSet { if isClickable != oldValue { updateAccessibility() } }
    }
    var level: CGFloat {
        get { bars.level }
        set { bars.level = newValue }
    }
    /// How many levels a second come in (`PillBars.levelsPerSecond`).
    var levelsPerSecond: Double {
        get { bars.levelsPerSecond }
        set { bars.levelsPerSecond = newValue }
    }
    var onAction: ((Action) -> Void)?
    /// The pointer entered (true) or left (false) the capsule.
    var onHoverChanged: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragMoved: ((NSPoint) -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?

    /// The capsule, the pill's one glass: the navigation layer, and nothing in it has glass of its own. Its frame is
    /// the look's shape in the room.
    let glass = CapsuleGlass()
    /// The content, along the capsule.
    let stack = NSStackView()
    /// The glass's content view: the stack, the lone check, and an item fading out where it was after its look ended.
    let glassContent = NSView()
    private let bars = PillBars()
    private let wand = PillView.symbolView("wand.and.sparkles", color: .labelColor)
    private let warning = PillView.symbolView("exclamationmark.triangle.fill", color: .systemOrange)
    let check = PillView.symbolView("checkmark", color: .systemGreen, weight: .semibold)
    private let label = NSTextField(labelWithString: "")
    private let elapsed = NSTextField(labelWithString: "")
    private let keycaps = NSHostingView(rootView: PillKeycaps())
    private let cancel = PillButtonHost(
        rootView: PillButton(face: .symbol("xmark", label: StatusText.cancelLabel)))
    private let stop = PillButtonHost(
        rootView: PillButton(face: .symbol("stop.fill", label: StatusText.stopLabel), isProminent: true))
    private let button = PillButtonHost(rootView: PillButton())
    /// Counts the recording's time while it shows; nil otherwise.
    private var clock: Task<Void, Never>?
    var pressStart: NSPoint?
    var isDragging = false
    var isHovering = false
    var hoverArea: NSTrackingArea?

    override init(frame: NSRect) {
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
        // Each item keeps its own layer while it is out of the glass, so its fade-in (`fade`) has a layer to run on
        // when it comes back.
        for view in [label, elapsed, keycaps, wand, warning, cancel, stop, button] as [NSView] {
            view.wantsLayer = true
        }
        keycaps.sizingOptions = .intrinsicContentSize
        keycaps.setAccessibilityElement(false)
        // A button and the keycaps keep their full width; only the words give way, so a message too long for the pill
        // truncates its words every time, and the snapshot check sees it (owner trial: the button gave way on the first
        // layout and not on the next).
        for host in [cancel, stop, button] {
            host.sizingOptions = .intrinsicContentSize
        }
        for view in [cancel, stop, button, keycaps] as [NSView] {
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        cancel.rootView.onClick = { [weak self] in self?.onAction?(.cancel) }
        stop.rootView.onClick = { [weak self] in self?.onAction?(.stop) }
        button.rootView.onClick = { [weak self] in self?.onAction?(.button) }
        stack.spacing = PillGeometry.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        glassContent.addSubview(stack)
        // The content keeps the size of the look's capsule, centred, so it never reflows while the glass morphs (a
        // reflow cut the words to "No sound fro…" mid-morph, owner trial 2026-10-24).
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: glassContent.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: glassContent.centerYAnchor), stackWidth, stackHeight,
        ])
        // The lone check is centred by its image's frame, not through the stack: the stack centres a symbol's
        // alignment rect, which sits off its drawn centre.
        check.frame = glassContent.bounds
        check.autoresizingMask = [.width, .height]
        check.imageAlignment = .alignCenter
        glassContent.addSubview(check)
        glass.contentView = glassContent
        addSubview(glass)
        apply(from: look)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillView is built in code")
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

    var isVertical: Bool { IndicatorPlacement.isVertical(at: anchor, hasWords: look.hasWords) }

    private lazy var stackWidth = stack.widthAnchor.constraint(equalToConstant: 0)
    private lazy var stackHeight = stack.heightAnchor.constraint(equalToConstant: 0)
    /// What the look's content needs along the capsule, ends included; set by `apply`.
    private(set) var contentLength: CGFloat = 0

    /// The capsule's size for the look: idle is the bar, done and a drag a circle, the rest as long as the content.
    var shapeSize: NSSize {
        let height = PillGeometry.height
        switch look {
        case .idle:
            return isVertical
                ? NSSize(width: PillGeometry.idleThickness, height: PillGeometry.idleLength)
                : NSSize(width: PillGeometry.idleLength, height: PillGeometry.idleThickness)
        case .done, .dragged: return NSSize(width: height, height: height)
        default:
            let length = min(PillGeometry.maxLength, max(height, contentLength))
            return isVertical ? NSSize(width: height, height: length) : NSSize(width: length, height: height)
        }
    }

    /// The capsule's frame in the view for the look: on the anchor's centre line (`IndicatorPlacement.capsule`).
    var capsuleFrame: NSRect {
        let size = shapeSize
        return NSRect(
            IndicatorPlacement.capsule(
                width: size.width, height: size.height, at: anchor, thickness: PillGeometry.height,
                in: ScreenRect(bounds)))
    }

    /// The room the glass was last placed in.
    private var placedRoom: NSRect?

    /// A new room (an anchor change, a drop, a screen change) puts the capsule at its place at once, mid-morph too. A
    /// look change moves it with the morph's spring, which a layout pass in the same room must not cut short.
    override func layout() {
        super.layout()
        if bounds != placedRoom {
            placeGlass()
        }
    }

    /// The glass frame's one owner: the look's capsule in the view's bounds now.
    func placeGlass() {
        placedRoom = bounds
        glass.frame = capsuleFrame
    }

    /// Shows the views the look needs, in order, and moves the capsule to its new shape: animated on screen, at once
    /// offscreen and for the first look.
    private func apply(from old: PillLook) {
        bars.isVertical = isVertical
        bars.isSweeping = look.isProcessing
        let before = stack.arrangedSubviews
        let places = before.map { (view: $0, offset: offset(of: $0), frame: stack.convert($0.frame, to: glassContent)) }
        let (text, face) = (label.stringValue, button.rootView.face)
        let views = views(for: look)
        // The words or the button's title changed: new content, though the view is the same.
        let renewed = [label: label.stringValue != text, button: button.rootView.face != face]
        // An item fading out after an earlier change, wanted again: back into the stack, fading in from where it is.
        let returning = views.filter { $0.superview === glassContent }
        for view in returning {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
        }
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
        runClock()
        updateAccessibility()
        morph(
            Change(
                staying: places.filter { views.contains($0.view) && renewed[$0.view] != true }.map {
                    ($0.view, $0.offset)
                },
                entering: views.filter { !before.contains($0) || renewed[$0] == true },
                returning: returning,
                leaving: places.filter { !views.contains($0.view) }.map { ($0.view, $0.frame) }))
        // Last: the hover it finds can change the look (the idle bar's keys), and that change runs its own apply.
        trackHover()
    }

    /// The content's natural length along the capsule, ends included: the stack's fitting size without the look's
    /// size.
    private func naturalLength() -> CGFloat {
        NSLayoutConstraint.deactivate([stackWidth, stackHeight])
        defer { NSLayoutConstraint.activate([stackWidth, stackHeight]) }
        let fitting = stack.fittingSize
        return isVertical ? fitting.height : fitting.width
    }
}

// MARK: Content

extension PillView {
    /// The views `look` shows, in order, filled with its words.
    private func views(for look: PillLook) -> [NSView] {
        switch look {
        case .idle, .done, .dragged: return []
        case .processing:
            bars.color = PillBars.level
            return [bars]
        case .hover(let keys):
            // A chord never shows alone: the word says what it starts (owner, 2026-10-25).
            keycaps.rootView = PillKeycaps(keys: keys)
            label.stringValue = StatusText.dictate
            return [label, keycaps]
        case .recording(let recording): return views(for: recording)
        case .message(let message):
            return (message.isProblem ? [warning] : []) + words(message)
        }
    }

    private func views(for recording: PillRecording) -> [NSView] {
        bars.color = recording.isSilent ? .systemOrange : PillBars.level
        var views: [NSView] = []
        if recording.showsCancel { views.append(cancel) }
        if recording.isCleaned { views.append(wand) }
        if recording.showsBars { views.append(bars) }
        if let from = recording.timedFrom {
            elapsed.stringValue = Self.time(since: from)
            views.append(elapsed)
        }
        if let words = recording.words { views += self.words(words) }
        if recording.isHandsFree { views.append(stop) }
        return views
    }

    /// The words, and their button when they have one.
    private func words(_ message: PillMessage) -> [NSView] {
        label.stringValue = message.text
        guard let action = message.action else { return [label] }
        button.rootView.face = .text(action.title)
        return [label, button]
    }

    /// The ends: a button keeps `inset` from the capsule's end, anything else `endPadding`.
    private func edgeInsets(for views: [NSView]) -> NSEdgeInsets {
        func end(_ view: NSView?) -> CGFloat {
            view is PillButtonHost ? PillGeometry.inset : PillGeometry.endPadding
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

    /// The recording's time, once a second while it shows: the clock sleeps to the next whole second and wakes for it
    /// alone. Every other look runs no clock.
    private func runClock() {
        guard case .recording(let recording) = look, let from = recording.timedFrom else {
            clock?.cancel()
            clock = nil
            return
        }
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                let next = from + .seconds(Int((ContinuousClock.now - from) / .seconds(1)) + 1)
                do {
                    try await ContinuousClock().sleep(until: next)
                } catch {
                    return
                }
                self?.tick(since: from)
            }
        }
    }

    /// The next second. A time with one more digit (100:00) makes the capsule longer.
    private func tick(since start: ContinuousClock.Instant) {
        let time = Self.time(since: start)
        let isLonger = time.count != elapsed.stringValue.count
        elapsed.stringValue = time
        if isLonger {
            apply(from: look)
        }
    }

    private static func time(since start: ContinuousClock.Instant) -> String {
        (ContinuousClock.now - start).formatted(.time(pattern: .minuteSecond))
    }
}
