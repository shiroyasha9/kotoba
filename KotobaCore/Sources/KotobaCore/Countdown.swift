/// A timer that can be held: it runs down to a deadline, or holds the time that was left. The pointer on
/// the indicator pill holds the pill's timer and its bar; the Esc Undo window holds the same way.
public struct Countdown: Sendable, Equatable {
    public typealias Instant = ContinuousClock.Instant

    private enum State: Sendable, Equatable {
        case running(deadline: Instant)
        case held(remaining: Duration)
    }

    public let duration: Duration
    private var state: State

    public init(duration: Duration, startingAt start: Instant, isHeld: Bool = false) {
        self.duration = duration
        state = isHeld ? .held(remaining: duration) : .running(deadline: start + duration)
    }

    /// When the time runs out; nil while held.
    public var deadline: Instant? {
        if case .running(let deadline) = state { deadline } else { nil }
    }

    public var isHeld: Bool {
        deadline == nil
    }

    public func remaining(at now: Instant) -> Duration {
        switch state {
        case .running(let deadline): max(now.duration(to: deadline), .zero)
        case .held(let remaining): remaining
        }
    }

    /// The part of `duration` still left, from 1 to 0: the length of the pill's bar.
    public func fraction(at now: Instant) -> Double {
        duration > .zero ? remaining(at: now) / duration : 0
    }

    public func isOver(at now: Instant) -> Bool {
        remaining(at: now) == .zero
    }

    /// Stops the clock with the time that is left; a held countdown stays as it is.
    public mutating func hold(at now: Instant) {
        guard !isHeld else { return }
        state = .held(remaining: remaining(at: now))
    }

    /// Runs on from the held time; a running countdown stays as it is.
    public mutating func resume(at now: Instant) {
        guard case .held(let remaining) = state else { return }
        state = .running(deadline: now + remaining)
    }
}
