import AppKit
import KotobaCore

/// The floating recording indicator: a Liquid Glass pill with the state and the mic level, on the
/// screen that holds the focused window. It sits at one of three anchors (`IndicatorAnchor`), and
/// the owner drags it between them. It never takes focus: a click or drag on it does not activate
/// kotoba or move focus from the app the owner types in.
@MainActor
final class IndicatorPanel {
    private static let anchorKey = "indicator.anchor"

    /// Called when the owner clicks the pill's button.
    var onAction: ((PillAction) -> Void)?

    /// Saved in UserDefaults; setting it moves a visible pill there.
    var anchor: IndicatorAnchor {
        get {
            UserDefaults.standard.string(forKey: Self.anchorKey).flatMap(IndicatorAnchor.init) ?? .bottomCenter
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.anchorKey)
            place(animated: true)
        }
    }

    /// Built on first show and kept. Building it at launch costs about 4.8 MB and 158 ms, and a
    /// release after hide frees almost nothing (docs/research/memory-spike.md).
    private var built: (panel: NSPanel, pill: IndicatorPillView)?
    private var panel: NSPanel { build().panel }
    private var pill: IndicatorPillView { build().pill }
    /// The screen the pill shows on; chosen each time it appears.
    private var screen: NSScreen?
    private var dropTargets: DropTargets?
    /// The pill's horizontal content width when the drag began, for the bottom target.
    private var dropTargetWidth: CGFloat = 0
    private var screenObserver: (any NSObjectProtocol)?
    /// The pill's hide timer: running until its deadline, or held by hover with the time that was left.
    private enum HideTimer {
        case running(deadline: ContinuousClock.Instant, task: Task<Void, Never>)
        case paused(remaining: Duration)
    }

    private var hideTimer: HideTimer?
    private var isHovering = false
    private var isRecording = false

    /// Shows the text and the button `StatusText` gives `state`, or hides the pill when there is none.
    func show(_ state: DictationState, context: StatusContext) {
        cancelHide()
        let wasRecording = isRecording
        isRecording = if case .recording = state { true } else { false }
        guard let content = content(for: state, context: context) else {
            orderOut()
            return
        }
        pill.content = content
        let wasVisible = panel.isVisible
        // A new dictation follows the focused window, to another screen too.
        if !wasVisible || (isRecording && !wasRecording && dropTargets == nil) {
            screen = Self.focusedScreen()
        }
        place(animated: wasVisible)
        if !wasVisible {
            panel.orderFrontRegardless()
        }
        // A pill that appears under a still pointer gets no mouse-entered event.
        isHovering = panel.frame.contains(NSEvent.mouseLocation)
        if content.hidesSoon {
            // A pill with a button gives the owner time to reach it.
            hide(after: content.action == nil ? .seconds(4) : .seconds(8))
        }
    }

    func showLevel(_ level: Float) {
        built?.pill.level = CGFloat(level)
    }

    /// What the pill shows for `state`; nil hides it.
    func content(for state: DictationState, context: StatusContext) -> IndicatorPillView.Content? {
        let text = state.statusText(context) ?? ""
        let action = state.pillAction(context)
        switch state {
        case .idle:
            return nil
        case .recording(let isLong):
            // Only a plain "Listening" pill stands vertical at an edge; the others carry more words.
            let isPlain = !isLong && !context.isSecureInputOn
            return .init(
                text: text, color: .systemRed, toolTip: context.isSecureInputOn ? DictationState.secureInputHelp : nil,
                showsMeter: true, isCompact: isPlain)
        case .transcribing:
            return .init(text: text, color: .systemBlue, showsSpinner: true, isCompact: true)
        case .undoable:
            // The pipeline ends the Undo window itself, so no hide timer here.
            return .init(text: text, color: .secondaryLabelColor, action: action)
        case .failed, .needsSetup, .rejected, .cleanupFailed, .recovered, .copied, .captureFailed:
            return .init(
                text: text, color: state.isGoodOutcome ? .systemGreen : .systemOrange, action: action,
                hidesSoon: true)
        }
    }

    /// Hides the pill after `delay`, or holds the delay while the pointer is on the pill.
    private func hide(after delay: Duration) {
        cancelHide()
        guard !isHovering else {
            hideTimer = .paused(remaining: delay)
            return
        }
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            // A show() between the wake-up and here cancelled this timer; its pill stays.
            guard !Task.isCancelled else { return }
            self?.orderOut()
        }
        hideTimer = .running(deadline: .now + delay, task: task)
    }

    private func cancelHide() {
        if case .running(_, let task) = hideTimer {
            task.cancel()
        }
        hideTimer = nil
    }

    /// Hover holds a running hide timer; leaving restarts it with the time that was left.
    private func hoverChanged(isInside: Bool) {
        isHovering = isInside
        switch hideTimer {
        case .running(let deadline, let task) where isInside:
            task.cancel()
            hideTimer = .paused(remaining: max(ContinuousClock.now.duration(to: deadline), .seconds(1)))
        case .paused(let remaining) where !isInside:
            hide(after: remaining)
        default:
            break
        }
    }

    private func perform(_ action: PillAction) {
        onAction?(action)
        // The pipeline ends the Undo window itself; any other action is done with the pill.
        if action != .undo {
            cancelHide()
            orderOut()
        }
    }

    private func orderOut() {
        endDrag()
        guard let built else { return }
        built.panel.orderOut(nil)
        // Empty content also stops the spinner.
        built.pill.content = .init()
        screen = nil
    }

    private func build() -> (panel: NSPanel, pill: IndicatorPillView) {
        if let built {
            return built
        }
        let panel = Self.makeFloatingPanel(frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        panel.hidesOnDeactivate = false

        let pill = IndicatorPillView(frame: panel.contentLayoutRect)
        panel.contentView = pill
        pill.onAction = { [weak self] action in self?.perform(action) }
        pill.onHoverChanged = { [weak self] isInside in self?.hoverChanged(isInside: isInside) }
        pill.onDragBegan = { [weak self] in self?.beginDrag() }
        pill.onDragMoved = { [weak self] point in self?.moveDrag(to: point) }
        pill.onDragEnded = { [weak self] point in self?.endDrag(at: point) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
        built = (panel, pill)
        return (panel, pill)
    }

    /// A borderless, non-activating, clear panel that floats on every Space, for the pill and its drop targets.
    static func makeFloatingPanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    // MARK: Placement

    /// Moves the pill to its anchor on `screen`, horizontal or vertical to fit the content.
    private func place(animated: Bool) {
        guard built != nil, dropTargets == nil, let screen = screen ?? Self.focusedScreen() else { return }
        let anchor = anchor
        let isCompact = pill.content.isCompact
        pill.layout = IndicatorPlacement.isVertical(at: anchor, isCompact: isCompact) ? .vertical : .horizontal
        let frame = NSRect(
            IndicatorPlacement.frame(
                at: anchor, isCompact: isCompact, contentWidth: pill.fittingWidth, in: ScreenRect(screen.visibleFrame)))
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { [panel] context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func screenParametersChanged() {
        guard built?.panel.isVisible == true else { return }
        if let screen, !NSScreen.screens.contains(screen) {
            self.screen = Self.focusedScreen()
        }
        place(animated: false)
    }

    /// The screen that holds most of the frontmost app's front window, else the screen with the pointer.
    private static func focusedScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let window = frontmostWindowFrame(),
            let index = IndicatorPlacement.screenIndex(holding: window, among: screens.map { ScreenRect($0.frame) })
        {
            return screens[index]
        }
        let mouse = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    /// The window server lists windows front to back; bounds need no Screen Recording permission.
    private static func frontmostWindowFrame() -> ScreenRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let primary = NSScreen.screens.first,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            return IndicatorPlacement.screenRect(
                fromWindowServer: ScreenRect(rect), primaryScreenHeight: primary.frame.height)
        }
        return nil
    }

    // MARK: Drag

    private func beginDrag() {
        guard let screen else { return }
        dropTargetWidth = pill.fittingWidth
        pill.layout = .drag
        dropTargets = DropTargets(in: screen.visibleFrame, contentWidth: dropTargetWidth, below: panel)
    }

    private func moveDrag(to point: NSPoint) {
        guard let dropTargets else { return }
        panel.setFrame(NSRect(IndicatorPlacement.dragFrame(centeredAt: ScreenPoint(point))), display: true)
        if let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }), pointerScreen != screen {
            screen = pointerScreen
            dropTargets.close()
            self.dropTargets = DropTargets(
                in: pointerScreen.visibleFrame, contentWidth: dropTargetWidth, below: panel)
        }
        guard let screen else { return }
        self.dropTargets?.highlight(
            IndicatorPlacement.nearestAnchor(to: ScreenPoint(point), in: ScreenRect(screen.visibleFrame)))
    }

    /// Snaps to the anchor nearest `point` and saves it. Without a point (the pill hid during the
    /// drag) only the drop targets go.
    private func endDrag(at point: NSPoint? = nil) {
        guard let dropTargets else { return }
        dropTargets.close()
        self.dropTargets = nil
        guard let point, let screen else { return }
        anchor = IndicatorPlacement.nearestAnchor(to: ScreenPoint(point), in: ScreenRect(screen.visibleFrame))
    }
}

/// The three drop targets shown while the owner drags the pill: a faint glass shape at each anchor,
/// the nearest one tinted. They live only for the drag.
@MainActor
private final class DropTargets {
    private var targets: [IndicatorAnchor: (panel: NSPanel, glass: NSGlassEffectView)] = [:]

    init(in visibleFrame: NSRect, contentWidth: CGFloat, below pill: NSPanel) {
        for anchor in IndicatorAnchor.allCases {
            let frame = NSRect(
                IndicatorPlacement.frame(
                    at: anchor, isCompact: true, contentWidth: contentWidth, in: ScreenRect(visibleFrame)))
            let panel = IndicatorPanel.makeFloatingPanel(frame: frame)
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0.6
            let glass = NSGlassEffectView(frame: panel.contentLayoutRect)
            glass.style = .clear
            glass.cornerRadius = IndicatorPlacement.cornerRadius
            panel.contentView = glass
            panel.orderFrontRegardless()
            targets[anchor] = (panel, glass)
        }
        // The targets sit under the pill at the same window level.
        pill.orderFrontRegardless()
    }

    func highlight(_ nearest: IndicatorAnchor) {
        for (anchor, target) in targets {
            let isNearest = anchor == nearest
            target.glass.tintColor = isNearest ? .controlAccentColor : nil
            target.panel.alphaValue = isNearest ? 0.9 : 0.6
        }
    }

    func close() {
        for target in targets.values {
            target.panel.close()
        }
        targets = [:]
    }
}

extension ScreenPoint {
    init(_ point: NSPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension ScreenRect {
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}

extension NSRect {
    init(_ rect: ScreenRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension IndicatorAnchor {
    /// The menu title.
    var title: String {
        switch self {
        case .bottomCenter: "Bottom Center"
        case .left: "Left"
        case .right: "Right"
        }
    }
}
