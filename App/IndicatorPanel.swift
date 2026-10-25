import AppKit
import KotobaCore

/// The floating recording indicator: the glass pill (`PillView`), on the screen that holds the focused window. It sits
/// at one of three anchors (`IndicatorAnchor`), and the owner drags it between them. With "Show indicator: Always" an
/// idle bar stays at idle; hovering it shows the hands-free chord, and a click on it starts a dictation (not while a
/// development build gives way to the release app). It never takes focus: a click or drag on it does not activate
/// kotoba or move focus from the app the owner types in, so the paste goes to that app.
@MainActor
final class IndicatorPanel {
    private static let visibilityKey = AppDefaults.Key.indicatorVisibility.rawValue

    /// Called when the owner clicks the pill's fix or Undo button.
    var onAction: ((PillAction) -> Void)?
    /// A click on the recording pill or its Stop, or on the idle bar with "Always" (`IndicatorPlacement.click`):
    /// AppDelegate sends it as a chord tap.
    var onTap: (() -> Void)?
    /// The hands-free pill's Cancel: AppDelegate sends it as Esc.
    var onCancel: (() -> Void)?
    /// The pointer held (true) or released (false) the Undo pill. The pipeline owns the Undo window, so AppDelegate
    /// passes this on.
    var onUndoHoldChanged: ((Bool) -> Void)?

    /// Where the pill sits, observed: General's picker reads it, so a drop shows there at once.
    let position = IndicatorPosition()

    /// Saved in UserDefaults; setting it moves a visible pill there. A drop and General's picker both set it.
    var anchor: IndicatorAnchor {
        get { position.anchor }
        set {
            position.anchor = newValue
            place(animated: true)
        }
    }

    /// Saved in UserDefaults; setting it shows or hides the idle bar at once.
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

    /// Built on first show and kept. Building it at launch costs about 4.8 MB and 158 ms, and a release after hide
    /// frees almost nothing (docs/research/memory-spike.md).
    private var built: (panel: NSPanel, pill: PillView)?
    var panel: NSPanel { build().panel }
    var pill: PillView { build().pill }
    /// The screen the pill shows on; chosen each time it appears.
    var screen: NSScreen?
    /// The owner's drag of the pill, while it lasts.
    var drag: Drag?
    private var screenObserver: (any NSObjectProtocol)?
    private var spaceObserver: (any NSObjectProtocol)?
    /// The pill's timer. `task` waits for the deadline of a timer that hides the pill.
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
    /// What the pill shows; nil while it is hidden.
    private var content: PillContent?
    /// The notice up (`show(_:)` with a `PillNotice`); an idle state does not replace it.
    private var notice: PillNotice?
    /// The pill was clicked to start a dictation, so the recording pill stays on this screen.
    private var isTapPending = false
    /// Where the recording's time counts from, set when it passes the 10-minute mark (`StatusContext`); the
    /// recording and its Undo window keep it.
    private var timedFrom: ContinuousClock.Instant?

    /// Shows the look `IndicatorLook` gives `state`, with its words and button, or the idle bar, or hides the pill.
    func show(_ state: DictationState, context: StatusContext) {
        let wasNotice = shown?.state.notice
        shown = (state, context)
        // Only the phase under the notice changed (Polish ended under it): the pill and its timer stay as they are.
        if let wasNotice, wasNotice == state.notice {
            return
        }
        countTime(of: state, context: context)
        let next = Self.content(for: state, context: context, visibility: visibility, timedFrom: timedFrom)
        // A held pill (the check, the App's notice) stays over a weaker one until its time ends.
        if PillRank(next) < rank, rank.isHeld {
            return
        }
        notice = nil
        let wasRecording = isRecording
        isRecording = state.phase.isRecording
        // A new dictation follows the focused window, unless a click on the pill started it.
        let followsFocus = isRecording && !wasRecording && !isTapPending
        if state != .idle {
            isTapPending = false
        }
        present(next, followsFocus: followsFocus)
    }

    /// The rank of the pill up now.
    private var rank: PillRank {
        notice == nil ? PillRank(content) : .notice
    }

    /// The time shows from the 10-minute mark: the pipeline says when it passes, and the count starts there.
    private func countTime(of state: DictationState, context: StatusContext) {
        switch state.phase {
        case .recording(isLong: true, _, _, _):
            if timedFrom == nil {
                timedFrom = .now - .seconds(context.longRecordingMinutes * 60)
            }
        case .recording, .undoable:
            break
        case .idle, .transcribing, .cleaning, .polishing:
            timedFrom = nil
        }
    }

    /// Shows `notice` until its timer ends, a click on its button, or the next dictation state.
    func show(_ notice: PillNotice) {
        self.notice = notice
        present(PillContent(notice), followsFocus: false)
    }

    /// Shows `notice` only over a weaker pill (hidden, the idle bar or the check), so it never covers a dictation or
    /// another notice.
    func showWhenQuiet(_ notice: PillNotice) {
        if rank < .notice {
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
    /// pill redraws now; a dictation's or a notice's pill keeps its words and timer, and the next pill reads it.
    func contextChanged(_ context: StatusContext) {
        shown = (shown?.state ?? .idle, context)
        if rank == .quiet {
            showQuiet()
        }
    }

    func showLevel(_ level: Float) {
        built?.pill.level = CGFloat(level)
    }

    /// Shows `content` (nil hides the pill) and starts its timer.
    private func present(_ content: PillContent?, followsFocus: Bool) {
        cancelTimer()
        guard let content else {
            orderOut()
            return
        }
        self.content = content
        let wasVisible = panel.isVisible
        // The idle bar is not about a window, so it skips the window list and takes the pointer's screen.
        if !wasVisible || (followsFocus && drag == nil) {
            let next = content.look == .idle ? NSScreen.withPointer : NSScreen.focused
            if !wasVisible || next != screen {
                screen = next
                place(animated: wasVisible)
            }
        }
        pill.isClickable = content.click != nil
        pill.toolTip = content.toolTip
        pill.look = look(for: content)
        if !wasVisible {
            panel.orderFrontRegardless()
            Self.rejoinAllSpaces(panel)
        }
        if let timer = content.timer {
            start(timer)
        }
    }

    /// The content's look; the idle bar shows the hands-free chord while the pointer is on it and a click starts a
    /// dictation.
    private func look(for content: PillContent) -> PillLook {
        guard content.look == .idle, content.click != nil, isHovering else { return content.look }
        return .hover(keys: HotkeyChords.shared.handsFree.keycaps)
    }

    /// The pill is done with its message: the idle bar with "Always", else nothing.
    private func showQuiet() {
        notice = nil
        present(
            shown.flatMap { Self.content(for: .idle, context: $0.context, visibility: visibility) }, followsFocus: false
        )
    }

    private func perform(_ action: PillView.Action) {
        switch action {
        case .click:
            guard content?.click != nil else { return }
            if !isRecording {
                isTapPending = true
            }
            onTap?()
        case .stop:
            onTap?()
        case .cancel:
            onCancel?()
        case .button:
            guard let pillAction = content?.look.action else { return }
            onAction?(pillAction)
            // The pipeline ends the Undo window itself; any other message is done. A recording's fix (Choose Mic…)
            // leaves the recording on the pill.
            if pillAction != .undo, case .message = content?.look {
                showQuiet()
            }
        }
    }

    /// Whether `window` is the pill's panel: its click is a chord tap (`onTap`), not a mouse-down that drops a press.
    func holds(_ window: NSWindow?) -> Bool {
        window != nil && window === built?.panel
    }

    /// Hides the pill. Its look goes back to the idle bar offscreen, so no sweep, check or clock runs while hidden.
    private func orderOut() {
        endDrag()
        content = nil
        guard let built else { return }
        built.panel.orderOut(nil)
        built.pill.look = .idle
        screen = nil
    }

    private func build() -> (panel: NSPanel, pill: PillView) {
        if let built {
            return built
        }
        let pill = PillView(frame: .zero)
        let panel = Self.makeFloatingPanel(holding: pill, frame: .zero)
        panel.hidesOnDeactivate = false
        pill.onAction = { [weak self] action in self?.perform(action) }
        pill.onHoverChanged = { [weak self] isInside in self?.hoverChanged(isInside: isInside) }
        pill.onDragBegan = { [weak self] press in self?.beginDrag(from: press) }
        pill.onDragMoved = { [weak self] point in self?.moveDrag(to: point) }
        pill.onDragEnded = { [weak self] point in self?.endDrag(at: point) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.built.map { Self.rejoinAllSpaces($0.panel) } }
        }
        built = (panel, pill)
        return (panel, pill)
    }
}

// MARK: Timer

extension IndicatorPanel {
    private func start(_ timer: PillTimer) {
        self.timer = Timer(
            countdown: Countdown(duration: timer.duration, startingAt: .now, isHeld: isHovering), kind: timer.kind)
        if isHovering, timer.kind == .followsUndoWindow {
            onUndoHoldChanged?(true)
        }
        timerChanged()
    }

    /// Waits for the deadline of a running timer that hides the pill.
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
    }

    private func cancelTimer() {
        timer?.task?.cancel()
        timer = nil
    }

    /// Hover holds the timer; leaving runs it on from the time that was left. On the idle bar it shows the chord.
    private func hoverChanged(isInside: Bool) {
        isHovering = isInside
        if let content {
            pill.look = look(for: content)
        }
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
    /// Moves the pill's room to its anchor on `screen`; the capsule changes shape inside the room. The same room at
    /// another place (a drop at the anchor it had, another screen) slides there, and the pill in it does not change. A
    /// room of another size (a new anchor) is taken at once, before the pill takes the anchor in it, so the capsule's
    /// place is worked out in the room it ends in: a room that grew in an animation left the glass where the old room
    /// put it, cut off at the window's edge (owner QA 4, U3).
    private func place(animated: Bool) {
        guard let built, drag == nil, let screen = screen ?? NSScreen.focused else { return }
        let anchor = anchor
        let room = IndicatorPlacement.room(
            at: anchor, thickness: Double(PillGeometry.height), in: ScreenRect(screen.visibleFrame))
        let frame = Self.windowFrame(around: NSRect(room))
        guard animated, built.panel.isVisible, built.pill.anchor == anchor, built.panel.frame.size == frame.size
        else {
            built.panel.setFrame(frame, display: true)
            built.pill.anchor = anchor
            // At its place in the new room now, not after a spring from where it was in the old one.
            built.pill.placeGlass()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            built.panel.animator().setFrame(frame, display: true)
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
