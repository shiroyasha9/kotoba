/// The hot-path moments the latency gate measures (stop tap to Cmd-V sent: p50 <= 1.0 s, p90 <= 1.5 s).
public enum LatencyMark: String, Sendable, CaseIterable {
    case keyDown
    /// When the first captured sample was recorded, from the buffer's capture time.
    case firstAudioBuffer
    /// The clipboard snapshot taken at chord-down is ready.
    case snapshotReady
    /// The indicator and start cue: at the release of a tap, or when a hold passes the threshold.
    case cue
    /// The stop moment, where the latency gate starts: in tap mode the second tap's chord-down
    /// (not its key-up), in hold mode the chord-up.
    case stop
    case uploadStart
    case response
    case pasteSent
    /// Submit phrase only: Return posted after the paste.
    case returnSent
    /// Cleanup dictations only: the cleaner request and its answer. `make latency` leaves these
    /// dictations out of the 1 s gate.
    case cleanStart
    case cleanResponse
    /// The last Esc that opened the Undo window, and the last Undo that resumed the recording.
    case cancel
    case resume

    /// One point-of-interest signpost, so Instruments shows the same moments as the log.
    func signpost() {
        Log.signposter.emitEvent("latency", "\(rawValue, privacy: .public)")
    }
}

/// One dictation's latency marks, as offsets from key-down. The pipeline also emits each mark
/// as a signpost on `Log.signposter`, so Instruments and the latency report see the same moments.
public struct LatencyLog: Sendable, Equatable {
    public private(set) var offsets: [LatencyMark: Duration] = [:]

    public init(offsets: [LatencyMark: Duration] = [:]) {
        self.offsets = offsets
    }

    public mutating func record(_ mark: LatencyMark, offset: Duration) {
        offsets[mark] = offset
    }

    /// "stopToPasteMs=812 keyDown=0 firstAudioBuffer=41 ...", for the latency log line.
    var summary: String {
        let stopToPaste = duration(from: .stop, to: .pasteSent).map { Int($0 / .milliseconds(1)) } ?? -1
        let marks = LatencyMark.allCases.compactMap { mark in
            offsets[mark].map { "\(mark.rawValue)=\(Int($0 / .milliseconds(1)))" }
        }
        return (["stopToPasteMs=\(stopToPaste)"] + marks).joined(separator: " ")
    }

    /// Records `mark` at `instant` as an offset from `keyDown`, and emits its signpost.
    mutating func mark(_ mark: LatencyMark, at instant: ContinuousClock.Instant, keyDown: ContinuousClock.Instant) {
        record(mark, offset: instant - keyDown)
        mark.signpost()
    }

    /// Time from `start` to `end`, or nil when either mark is missing.
    public func duration(from start: LatencyMark, to end: LatencyMark) -> Duration? {
        guard let startOffset = offsets[start], let endOffset = offsets[end] else { return nil }
        return endOffset - startOffset
    }
}

/// The latency logs of the dictations in progress.
struct LatencyRecorder {
    private var logs: [DictationID: (keyDown: ContinuousClock.Instant, log: LatencyLog)] = [:]

    mutating func begin(_ id: DictationID, keyDown: ContinuousClock.Instant) {
        logs[id] = (keyDown, LatencyLog())
        mark(.keyDown, of: id, at: keyDown)
    }

    /// Records `mark` as an offset from key-down and emits its signpost. No-op once taken.
    mutating func mark(_ mark: LatencyMark, of id: DictationID, at instant: ContinuousClock.Instant) {
        guard let keyDown = logs[id]?.keyDown else { return }
        logs[id]?.log.mark(mark, at: instant, keyDown: keyDown)
    }

    /// The key-down instant and the log, handed to the next stage; later marks here are dropped.
    mutating func take(_ id: DictationID) -> (keyDown: ContinuousClock.Instant, log: LatencyLog) {
        logs.removeValue(forKey: id) ?? (.now, LatencyLog())
    }
}
