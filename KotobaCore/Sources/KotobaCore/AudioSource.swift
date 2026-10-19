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
    /// A segment of the upload copy closed at a pause (`UploadSegments`); the recording goes on.
    case segment(UploadSegment)
}

/// One closed segment of a live recording's upload copy, cut at a pause (`UploadSegments`), sent while the recording
/// goes on so the stop waits only for the last one (`SegmentUpload`).
public struct UploadSegment: Sendable, Equatable {
    /// From 0, in recording order.
    public var index: Int
    /// Ogg Opus, like the upload copy; its request deletes it.
    public var file: URL
    /// Where it starts in the recording.
    public var start: Duration
    public var duration: Duration

    public init(index: Int, file: URL, start: Duration, duration: Duration) {
        self.index = index
        self.file = file
        self.start = start
        self.duration = duration
    }
}

public struct RecordedAudio: Sendable, Equatable {
    public var file: URL
    /// The length written; zero when no frame was (a stop before the first buffer, an orphan with no readable audio).
    public var duration: Duration
    /// Some captured audio could not be written, and why: the file holds only `duration`, and the pipeline says so.
    /// Known only at the stop; the history does not keep it.
    public var loss: AudioLoss?
    /// The same audio as Ogg Opus at 24 kbps, about a fifth of the FLAC's bytes, written during the recording for the
    /// first request only (`TranscriptionRequest.upload`), which deletes it when it ends; a discard deletes it too. Nil
    /// when the recorder wrote none (its encoder failed). After a cut it holds only the audio after the last cut
    /// (`uploadStart`). The history does not keep it.
    public var upload: URL?
    /// Where `upload` starts in the recording: after the last cut (`CaptureEvent.segment`), zero when none was made.
    public var uploadStart: Duration

    public init(
        file: URL, duration: Duration, loss: AudioLoss? = nil, upload: URL? = nil, uploadStart: Duration = .zero
    ) {
        self.file = file
        self.duration = duration
        self.loss = loss
        self.upload = upload
        self.uploadStart = uploadStart
    }

    /// Something to send: a recording with no frames is never sent, and never offered for a retry.
    public var hasAudio: Bool { duration > .zero }
}

/// Why a recording file stopped taking audio.
public enum AudioLoss: Sendable, Equatable {
    /// The write failed with ENOSPC: the volume is full.
    case diskFull
    /// Another write or conversion error.
    case other
}
