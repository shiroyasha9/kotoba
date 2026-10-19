import Foundation

@testable import KotobaCore

/// The mic: records into the files the pipeline names, and reports what the tests set.
actor FakeAudioSource: AudioSource {
    private(set) var files: [URL] = []
    private(set) var isCapturing = false
    /// The mic is off for the Undo window; the file is still open.
    private(set) var isPaused = false
    private(set) var resumes = 0
    /// Files deleted by `discardCapture` or `discard(_:)`.
    private(set) var discarded: [URL] = []
    /// Files `discardCapture` or `discard(_:)` could not delete: they stay on disk.
    private(set) var undeletable: [URL] = []
    private var isRemovalFailing = false
    private var isCaptureLost = false
    /// The length `endCapture` reports; zero is a stop before the first buffer.
    private var recordedLength: Duration = .seconds(1)
    /// `endCapture` reports that some audio could not be written (`RecordedAudio.loss`).
    private var writeLoss: AudioLoss?
    /// `endCapture` reports an Opus upload copy next to the file (`RecordedAudio.upload`).
    private var writesUploadCopies = false
    /// When set, `beginCapture` waits for this gate.
    var beginGate: Gate?
    var beginError: (any Error)?

    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func holdBegin(at gate: Gate) {
        beginGate = gate
    }

    /// From now on `discardCapture` cannot delete the file, as when the audio folder refuses the removal.
    func failRemoval() {
        isRemovalFailing = true
    }

    /// From now on `endCapture` finds no capture running, as when the adapter lost it: nothing was written.
    func loseCapture() {
        isCaptureLost = true
    }

    /// From now on `endCapture` reports `length` of audio.
    func record(_ length: Duration) {
        recordedLength = length
    }

    /// From now on the file takes no more audio, for `loss`: `endCapture` reports `length` written, and the loss.
    func failWrites(after length: Duration, with loss: AudioLoss = .diskFull) {
        recordedLength = length
        writeLoss = loss
    }

    /// From now on `endCapture` reports an Opus upload copy, as the app's recorder writes one.
    func writeUploadCopies() {
        writesUploadCopies = true
    }

    func failBegin(with error: any Error) {
        beginError = error
    }

    func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent> {
        await beginGate?.pass()
        if let beginError { throw beginError }
        files.append(file)
        isCapturing = true
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation = continuation
        return stream
    }

    /// The first buffer arrived, its first sample captured at `instant`.
    func deliverFirstBuffer(at instant: ContinuousClock.Instant) {
        continuation?.yield(.firstBuffer(at: instant))
    }

    /// The meter measured `level` over its last window.
    func deliverLevel(_ level: Float) {
        continuation?.yield(.level(level))
    }

    /// The mic disconnected or stopped sending.
    func loseInput() {
        continuation?.yield(.inputLost)
    }

    func endCapture() async -> RecordedAudio? {
        isCapturing = false
        continuation?.finish()
        guard !isCaptureLost else { return nil }
        let file = files.last ?? URL(filePath: "/dev/null")
        return RecordedAudio(
            file: file, duration: recordedLength, loss: writeLoss,
            upload: writesUploadCopies ? file.deletingPathExtension().appendingPathExtension("ogg") : nil)
    }

    func cancelCapture() async -> RecordedAudio? {
        isCapturing = false
        continuation?.finish()
        return files.last.map { RecordedAudio(file: $0, duration: recordedLength) }
    }

    func pauseCapture() async {
        isCapturing = false
        isPaused = true
    }

    func resumeCapture() async throws {
        isCapturing = true
        isPaused = false
        resumes += 1
    }

    func discardCapture() async -> Bool {
        isCapturing = false
        continuation?.finish()
        guard let file = files.popLast() else { return true }
        return remove(file)
    }

    func discard(_ audio: RecordedAudio) async -> Bool {
        remove(audio.file)
    }

    private func remove(_ file: URL) -> Bool {
        if isRemovalFailing {
            undeletable.append(file)
            return false
        }
        discarded.append(file)
        return true
    }
}
