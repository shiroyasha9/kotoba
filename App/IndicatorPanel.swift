import AppKit
import KotobaCore

/// The floating recording indicator: a Liquid Glass pill with the state and the mic level, on the
/// screen that holds the focused window. It sits at one of three anchors (`IndicatorAnchor`), and
/// the owner drags it between them. With "Show indicator: Always" a small round pill stays at idle, and
/// a click on it starts and stops a dictation (not while a development build gives way to the release app). It never takes focus: a click or drag on it does not
/// activate kotoba or move focus from the app the owner types in, so the paste goes to that app.
@MainActor
final class IndicatorPanel {
    private static let anchorKey = AppDefaults.Key.indicatorAnchor.rawValue
    private static let visibilityKey = AppDefaults.Key.indicatorVisibility.rawValue

    /// Called when the owner clicks the pill's button.
    var onAction: ((PillAction) -> Void)?
    /// A click on the recording pill, or on the idle pill with "Always" (`IndicatorPlacement.isClickATap`): AppDelegate
    /// sends it as a chord tap.
    var onTap: (() -> Void)?
    /// The pointer held (true) or released (false) the Undo pill. The pipeline owns the Undo window, so
    /// AppDelegate passes this on; the pill's bar holds by itself.
    var onUndoHoldChanged: ((Bool) -> Void)?

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

    /// Saved in UserDefaults; setting it shows or hides the idle pill at once.
    var visibility: IndicatorVisibility {
        get {
            UserDefaults.standard.string(forKey: Self.visibilityKey).flatMap(IndicatorVisibility.init)
                ?? .whileDictating
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.visibilityKey)
            if notice == nil, let shown {
                show(shown.state, context: shown.context)
            }
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
    /// The pill's timer, the same one its bar shows. `task` waits for the deadline of a timer that hides the pill.
    private struct Timer {
        var countdown: Countdown
        let kind: PillTimer.Kind
        var task: Task<Void, Never>?
    }

    private var timer: Timer?
    private var isHovering = false
    private var isRecording = false
    /// The last dictation state, so a visibility change or a finished message can show it again.
    private var shown: (state: DictationState, context: StatusContext)?
    /// The notice up (`show(_:)` with a `PillNotice`); an idle state does not replace it.
    private var notice: PillNotice?
    /// The pill was clicked to start a dictation, so the recording pill stays on this screen.
    private var isTapPending = false

    /// Shows the text and the button `StatusText` gives `state`, or the idle pill, or hides the pill.
    func show(_ state: DictationState, context: StatusContext) {
        shown = (state, context)
        if state == .idle, notice != nil {
            return
        }
        notice = nil
        let wasRecording = isRecording
        isRecording = if case .recording = state { true } else { false }
        // A new dictation follows the focused window, unless a click on the pill started it.
        let followsFocus = isRecording && !wasRecording && !isTapPending
        if state != .idle {
            isTapPending = false
        }
        present(Self.content(for: state, context: context, visibility: visibility), followsFocus: followsFocus)
    }

    /// Shows `notice` until its timer ends, a click on its button, or the next dictation state.
    func show(_ notice: PillNotice) {
        self.notice = notice
        present(.init(notice), followsFocus: false)
    }

    /// Shows `notice` only while the pill is quiet (hidden, or the idle pill), so it never covers a dictation or
    /// another notice.
    func showWhenQuiet(_ notice: PillNotice) {
        if isQuiet {
            show(notice)
        }
    }

    /// Ends `notice` if it is the one up.
    func end(_ notice: PillNotice) {
        if self.notice == notice {
            showQuiet()
        }
    }

    /// A new context for the shown state, such as a development build that starts or stops giving way. Only a quiet
    /// pill redraws now; a dictation's or a notice's pill keeps its text and timer, and the next pill reads it.
    func contextChanged(_ context: StatusContext) {
        shown = (shown?.state ?? .idle, context)
        if notice == nil, isQuiet {
            showQuiet()
        }
    }

    /// Hidden, or the idle pill: no dictation and no notice is on screen.
    private var isQuiet: Bool {
        built.map { !$0.panel.isVisible || $0.pill.content.isRound } ?? true
    }

    func showLevel(_ level: Float) {
        built?.pill.level = CGFloat(level)
    }

    /// Shows `content` (nil hides the pill) and starts its timer.
    private func present(_ content: IndicatorPillView.Content?, followsFocus: Bool) {
        cancelTimer()
        guard let content else {
            orderOut()
            return
        }
        pill.content = content
        let wasVisible = panel.isVisible
        // The idle pill is not about a window, so it skips the window list and takes the pointer's screen.
        if !wasVisible || (followsFocus && dropTargets == nil) {
            screen = content.isRound ? NSScreen.withPointer : NSScreen.focused
        }
        place(animated: wasVisible)
        if !wasVisible {
            panel.orderFrontRegardless()
        }
        // A pill that appears under a still pointer gets no mouse-entered event, but its exit must still come.
        isHovering = panel.frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin).contains(NSEvent.mouseLocation)
        pill.trackPointer(isInside: isHovering)
        if let timer = content.timer {
            start(timer)
        }
    }

    /// The pill is done with its message: the idle pill with "Always", else nothing.
    private func showQuiet() {
        notice = nil
        present(
            shown.flatMap { Self.content(for: .idle, context: $0.context, visibility: visibility) }, followsFocus: false
        )
    }

    private func perform(_ action: PillAction) {
        onAction?(action)
        // The pipeline ends the Undo window itself; any other action is done with the pill.
        if action != .undo {
            showQuiet()
        }
    }

    /// Whether `window` is the pill's panel: its click is a chord tap (`onTap`), not a mouse-down that drops a press.
    func holds(_ window: NSWindow?) -> Bool {
        window != nil && window === built?.panel
    }

    private func tapped() {
        if !isRecording {
            isTapPending = true
        }
        onTap?()
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
        let pill = IndicatorPillView(frame: .zero)
        let panel = Self.makeFloatingPanel(holding: pill, frame: NSRect(x: 0, y: 0, width: 240, height: 40))
        panel.hidesOnDeactivate = false
        pill.onAction = { [weak self] action in self?.perform(action) }
        pill.onClick = { [weak self] in self?.tapped() }
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
}

// MARK: Timer

extension IndicatorPanel {
    private func start(_ timer: PillTimer) {
        self.timer = Timer(
            countdown: Countdown(duration: timer.duration, startingAt: .now, isHeld: isHovering),
            kind: timer.kind)
        if isHovering, timer.kind == .followsUndoWindow {
            onUndoHoldChanged?(true)
        }
        timerChanged()
    }

    /// Shows the timer on the bar, and waits for the deadline of a running timer that hides the pill.
    private func timerChanged() {
        guard var timer else { return }
        timer.task?.cancel()
        timer.task = nil
        if timer.kind == .hidesPill, let deadline = timer.countdown.deadline {
            timer.task = Task { [weak self] in
                do {
                    try await ContinuousClock().sleep(until: deadline)
                } catch {
                    return
                }
                // A show() between the wake-up and here cancelled this timer; its pill stays.
                guard !Task.isCancelled else { return }
                self?.showQuiet()
            }
        }
        self.timer = timer
        pill.countdown = timer.countdown
    }

    private func cancelTimer() {
        timer?.task?.cancel()
        timer = nil
        built?.pill.countdown = nil
    }

    /// Hover holds the timer and its bar; leaving runs both on from the time that was left.
    private func hoverChanged(isInside: Bool) {
        isHovering = isInside
        guard var timer, timer.countdown.isHeld != isInside else { return }
        if isInside {
            timer.countdown.hold(at: .now)
        } else {
            timer.countdown.resume(at: .now)
        }
        self.timer = timer
        timerChanged()
        if timer.kind == .followsUndoWindow {
            onUndoHoldChanged?(isInside)
        }
    }
}

// MARK: Placement

extension IndicatorPanel {
    /// Moves the pill to its anchor on `screen`, horizontal or vertical to fit the content.
    private func place(animated: Bool) {
        guard built != nil, dropTargets == nil, let screen = screen ?? NSScreen.focused else { return }
        let anchor = anchor
        let content = pill.content
        let visibleFrame = ScreenRect(screen.visibleFrame)
        let pillFrame: ScreenRect
        if content.isRound {
            pill.layout = .round
            pillFrame = IndicatorPlacement.roundFrame(at: anchor, in: visibleFrame)
        } else {
            let isCompact = content.isCompact
            pill.layout = IndicatorPlacement.isVertical(at: anchor, isCompact: isCompact) ? .vertical : .horizontal
            pillFrame = IndicatorPlacement.frame(
                at: anchor, isCompact: isCompact, contentWidth: pill.fittingWidth, in: visibleFrame)
        }
        let frame = Self.windowFrame(around: NSRect(pillFrame))
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
            self.screen = NSScreen.focused
        }
        place(animated: false)
    }
}

// MARK: Drag

extension IndicatorPanel {
    private func beginDrag() {
        guard let screen else { return }
        dropTargetWidth = pill.fittingWidth
        pill.layout = .round
        dropTargets = DropTargets(in: screen.visibleFrame, contentWidth: dropTargetWidth, below: panel)
    }

    private func moveDrag(to point: NSPoint) {
        guard let dropTargets else { return }
        panel.setFrame(
            Self.windowFrame(around: NSRect(IndicatorPlacement.dragFrame(centeredAt: ScreenPoint(point)))),
            display: true)
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
