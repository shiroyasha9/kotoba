/// When the indicator warns that the mic gives no sound while recording (docs/research/beyond-wispr.md, idea 4).
///
/// A working mic is never silent: room noise keeps its level over `floor` even before the first word. A muted mic, a
/// dead device or a Bluetooth mic that has not started gives 0. So the warning shows once every level for `delay`
/// stayed under `floor`, or when no level came for `delay`; it clears at the first level at or over it. The policy reads
/// the meter's levels as they arrive, on the pipeline clock; the pipeline keeps one timer at `deadline`.
struct NoSoundPolicy: Sendable, Equatable {
    typealias Instant = ContinuousClock.Instant

    /// On the meter's scale (RMS x 8), about -72 dBFS. The quietest working mic the owner recorded never stayed
    /// under it for more than 0.2 s; a muted one stays at 0.
    static let floor: Float = 0.002

    let delay: Duration
    /// Since when every level was under `floor`.
    private var quietSince: Instant
    private(set) var isWarning = false

    init(delay: Duration, startingAt start: Instant) {
        self.delay = delay
        quietSince = start
    }

    /// Takes one meter level and returns whether the warning shows now.
    mutating func level(_ level: Float, at now: Instant) -> Bool {
        if level >= Self.floor {
            quietSince = now
            isWarning = false
        } else if now - quietSince >= delay {
            isWarning = true
        }
        return isWarning
    }

    /// When the pipeline checks again with `deadlinePassed`: `delay` after the last sound. A mic that sends no levels
    /// at all, or stops sending, gets no other check. Nil while the warning shows: only a level can clear it.
    var deadline: Instant? {
        isWarning ? nil : quietSince + delay
    }

    /// The pipeline's deadline (`deadline`) came.
    mutating func deadlinePassed(at now: Instant) -> Bool {
        if now - quietSince >= delay {
            isWarning = true
        }
        return isWarning
    }

    /// The mic disconnected or stopped sending: the warning shows at once, until a level with sound arrives.
    mutating func inputLost() -> Bool {
        isWarning = true
        return isWarning
    }

    /// The mic turns back on (Undo after Esc): the time it was off is not silence.
    mutating func restart(at now: Instant) {
        quietSince = now
        isWarning = false
    }
}
