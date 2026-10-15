import Foundation

/// Microphone capture. The mic is open only between `beginCapture` and the end or cancel call,
/// and audio is written to disk from the first buffer (docs/spec.md, "Audio").
public protocol AudioSource: Sendable {
    /// Starts capture into `file` and returns at once, without waiting for audio.
    /// The stream reports capture events and finishes when capture ends.
    func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent>
    /// Stops after one more buffer, so the last word is kept, and closes the file.
    func endCapture() async throws -> RecordedAudio
    /// Stops at once and keeps what was written.
    func cancelCapture() async -> RecordedAudio?
}

public enum CaptureEvent: Sendable, Equatable {
    /// The first buffer reached the file. `at` is when its first sample was captured, not when
    /// the buffer was delivered (delivery lags by one buffer, about 100 ms); it feeds
    /// `LatencyMark.firstAudioBuffer`.
    case firstBuffer(at: ContinuousClock.Instant)
}

public struct RecordedAudio: Sendable, Equatable {
    public var file: URL
    public var duration: Duration

    public init(file: URL, duration: Duration) {
        self.file = file
        self.duration = duration
    }
}
