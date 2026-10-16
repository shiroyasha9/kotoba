import Foundation

/// Microphone capture. The mic is open only between `beginCapture` and the end or cancel call,
/// and audio is written to disk from the first buffer (docs/spec.md, "Audio").
public protocol AudioSource: Sendable {
    /// Starts capture into `file` and returns at once, without waiting for audio.
    /// The stream reports capture events and finishes when capture ends.
    func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent>
    /// Stops after one more buffer, so the last word is kept, closes the file and reports the length written. Nil when
    /// no capture runs: nothing was written then.
    func endCapture() async -> RecordedAudio?
    /// Stops at once and keeps what was written.
    func cancelCapture() async -> RecordedAudio?
    /// Stops at once and deletes the file. False when the file stays on disk (its removal failed): the pipeline then
    /// remembers the discard, so the file is never sent (`Store.markDiscarded`).
    @discardableResult
    func discardCapture() async -> Bool
    /// Deletes the file of a capture that already ended (`endCapture`): a recording too short to send
    /// (`Settings.minimumRecording`). False when the file stays on disk, as for `discardCapture`.
    @discardableResult
    func discard(_ audio: RecordedAudio) async -> Bool
    /// Turns the mic off and keeps the file open, for the Undo window after Esc.
    func pauseCapture() async
    /// Turns the mic back on and appends to the same file.
    func resumeCapture() async throws
}

public enum CaptureEvent: Sendable, Equatable {
    /// The first audio arrived. `at` is when its first sample was captured, not when it was
    /// delivered; it feeds `LatencyMark.firstAudioBuffer`.
    case firstBuffer(at: ContinuousClock.Instant)
    /// The mic level 0...1 over the last meter window (about ten a second), the value the indicator's
    /// meter shows. The no-sound warning reads it (`NoSoundPolicy`).
    case level(Float)
    /// The mic disconnected or stopped sending audio; no more levels come from it.
    case inputLost
}

public struct RecordedAudio: Sendable, Equatable {
    public var file: URL
    /// The length written; zero when no frame was (a stop before the first buffer, an orphan with no readable audio).
    public var duration: Duration

    public init(file: URL, duration: Duration) {
        self.file = file
        self.duration = duration
    }

    /// Something to send: a recording with no frames is never sent, and never offered for a retry.
    public var hasAudio: Bool { duration > .zero }
}
