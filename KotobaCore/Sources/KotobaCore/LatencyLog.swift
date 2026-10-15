/// The hot-path moments the latency gate measures (stop tap to Cmd-V sent: p50 <= 1.0 s, p90 <= 1.5 s).
public enum LatencyMark: String, Sendable, CaseIterable {
    case keyDown
    case firstAudioBuffer
    case keyUp
    case uploadStart
    case response
    case pasteSent
}

/// One dictation's latency marks. The pipeline records each mark here and emits a signpost
/// on `Log.latency`, so Instruments and the latency report see the same moments.
public struct LatencyLog: Sendable, Equatable {
    public private(set) var marks: [LatencyMark: ContinuousClock.Instant] = [:]

    public init() {}

    public mutating func record(_ mark: LatencyMark, at instant: ContinuousClock.Instant) {
        marks[mark] = instant
    }
}
