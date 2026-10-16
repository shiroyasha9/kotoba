/// A recording that Esc cancelled, waiting for Undo, and the chord press (if any) during the
/// window. Only a clean tap resumes: a hold, a press that became a shortcut, or a press of the push-to-talk chord
/// (which has no tap) does not.
struct UndoWindow<Item> {
    typealias Schedule = (ContinuousClock.Instant) -> Task<Void, Never>

    let item: Item
    /// Ends the window when it fires; cancelled on resume and while the pointer holds the Undo pill.
    private(set) var timer: Task<Void, Never>
    /// The window's time, held while the pointer is on the Undo pill. A timer that wakes while held does nothing.
    private(set) var countdown: Countdown
    /// The chord press in progress, if any.
    private var press: Press?

    private struct Press {
        let startedAt: ContinuousClock.Instant
        var gesture: ChordGesture
        var isInterrupted = false
    }

    /// `schedule` starts the timer that ends the window at the given deadline.
    init(item: Item, duration: Duration, at now: ContinuousClock.Instant, schedule: Schedule) {
        self.item = item
        countdown = Countdown(duration: duration, startingAt: now)
        timer = schedule(now + duration)
    }

    /// Holds the window's time (true), or runs it on from the time that was left (false) with a new timer.
    mutating func hold(_ isHeld: Bool, at now: ContinuousClock.Instant, schedule: Schedule) {
        guard countdown.isHeld != isHeld else { return }
        if isHeld {
            timer.cancel()
            countdown.hold(at: now)
        } else {
            countdown.resume(at: now)
            timer = schedule(countdown.deadline ?? now)
        }
    }

    var isPressing: Bool { press != nil }

    mutating func pressBegan(at instant: ContinuousClock.Instant, gesture: ChordGesture) {
        press = Press(startedAt: instant, gesture: gesture)
    }

    /// A chord with more keys took over the press (`HotkeyEvent.gestureChanged`).
    mutating func pressChanged(to gesture: ChordGesture) {
        press?.gesture = gesture
    }

    mutating func pressInterrupted() {
        press?.isInterrupted = true
    }

    /// True when the press that ends here was a tap under `threshold` with no other key.
    mutating func pressEnded(at instant: ContinuousClock.Instant, threshold: Duration) -> Bool {
        defer { press = nil }
        guard let press else { return false }
        return !press.isInterrupted && press.gesture != .hold && instant - press.startedAt < threshold
    }
}
