import Foundation

/// The stage after capture: upload, dictionary replacements, the paste (`ClipboardPaste`), latency marks and the
/// stored record. The pipeline hands over one finished recording and gets the final record back; it keeps the hotkey,
/// recording and Undo state machine. A Sendable struct, so this work runs off the pipeline actor and a key event never
/// waits for it.
struct TranscriptDelivery: Sendable {
    /// One finished recording, with what the stage needs from the pipeline.
    struct Job: Sendable {
        let id: DictationID
        let audio: RecordedAudio
        let createdAt: Date
        let keyDown: ContinuousClock.Instant
        let latency: LatencyLog
        /// The clipboard taken at chord-down, and when it was ready.
        let clipboard: ClipboardPaste.PendingSnapshot
        let settings: DictationPipeline.Settings
        let output: DictationOutput
        /// The front app at the stop; the text pastes and a submit Return goes only to it, and the record keeps it.
        var frontAppAtStop: FrontApp?
        /// The press that stopped the dictation, while it was down at the stop: the paste waits for its release.
        var stoppingPress: Int?
        /// The segments sent while it recorded (`CaptureEvent.segment`); empty when it was not cut.
        var segments = SegmentUpload()
    }

    struct Outcome: Sendable {
        let record: DictationRecord
        /// Nil when nothing was pasted.
        let pasted: ClipboardPaste.Pasted?
        /// What the indicator shows instead of the record's usual outcome (for example `.cleanupFailed`).
        var showing: DictationNotice?

        /// Return followed the paste, so the field was submitted and holds no pasted text to read back.
        var isSubmitted: Bool {
            if case .sent = pasted?.submit { true } else { false }
        }
    }

    /// The transcribe and clean steps, shared with the retry queue.
    let steps: TranscriptionSteps
    let store: any Store
    let clock: any PipelineClock
    let paste: ClipboardPaste

    /// `gate` says when and whether the text may paste (`ClipboardPaste.run(_:gate:)`). `beforeCleanup` runs as the
    /// transcript goes to the cleaner, so the indicator can say so.
    func deliver(_ job: Job, gate: some PasteGate, beforeCleanup: @Sendable () async -> Void = {}) async -> Outcome {
        var latency = job.latency
        func mark(_ mark: LatencyMark, at instant: ContinuousClock.Instant) {
            Self.mark(mark, at: instant, of: job, in: &latency)
        }

        var record = DictationRecord(
            id: job.id, createdAt: job.createdAt, audio: job.audio, transcript: nil, status: .pending, latency: latency)
        record.output = job.output
        record.app = job.frontAppAtStop?.app
        // Saved while the upload runs, so a crash keeps the audio queued.
        let pendingRecord = record
        async let savedPending: Void = store.saveOrLog(pendingRecord)
        mark(.uploadStart, at: clock.now)
        let result = await Result {
            try await steps.transcribe(&record, settings: job.settings, segments: job.segments)
        }
        mark(.response, at: clock.now)
        if case .success(let transcribed) = result, let network = transcribed.network {
            Self.recordNetwork(network, of: job, in: &latency)
        }
        await savedPending

        var pasted: ClipboardPaste.Pasted?
        var cleanupMiss: TranscriptionSteps.CleanupMiss?
        switch result {
        case .failure(let error):
            Log.pipeline.error("Transcription \(job.id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            record.markFailed(by: error)
        case .success(let transcribed):
            if let mode = job.output.cleanupMode {
                await beforeCleanup()
                mark(.cleanStart, at: clock.now)
                cleanupMiss = await steps.clean(
                    transcribed, in: mode, into: &record, settings: job.settings,
                    deadline: job.settings.cleanupDeadline)
                mark(.cleanResponse, at: clock.now)
            }
            (record.status, pasted) = await pasteTranscript(
                record.cleanedText ?? transcribed.text, submits: transcribed.submits, job: job, gate: gate,
                latency: &latency)
            Self.log(latency, of: job, model: record.model)
        }
        record.latency = latency
        // The answers' ledger entries go with this save. A crash between the answer and here (at most the cleanup and
        // the paste, 1-2 s) loses them; the pending row is sent again at the next launch.
        await store.saveOrLog(record)
        let showing = Self.notice(for: record, of: job, pasted, cleanupMiss: cleanupMiss)
        return Outcome(record: record, pasted: pasted, showing: showing)
    }

    /// A copied transcript needs the owner's Cmd-V, so "Copied" wins over the cleanup note. A Return the owner asked
    /// for and did not get wins over the cleanup note too, and the cleanup note over a cut recording's. Lost audio
    /// matters more than a lost clipboard (`Pasted.isClipboardKept`).
    private static func notice(
        for record: DictationRecord, of job: Job, _ pasted: ClipboardPaste.Pasted?,
        cleanupMiss: TranscriptionSteps.CleanupMiss?
    ) -> DictationNotice? {
        if pasted?.submit == .frontAppChanged { return .returnSkipped(record.id) }
        guard record.status == .pasted else { return nil }
        switch cleanupMiss {
        case .failed: return .cleanupFailed(record.id)
        case .tooSlow: return .cleanupTooSlow(record.id)
        case nil: break
        }
        if let loss = job.audio.loss { return .audioCut(record.id, loss) }
        return pasted?.isClipboardKept == false ? .clipboardNotKept(record.id) : nil
    }

    /// Pastes `text` once the gate allows it, with its latency marks; when paste is not allowed, the text waits on the
    /// clipboard, and while kotoba quits it is only saved.
    private func pasteTranscript(
        _ text: String, submits: Bool, job: Job, gate: some PasteGate, latency: inout LatencyLog
    ) async -> (DictationRecord.Status, ClipboardPaste.Pasted?) {
        Self.mark(.snapshotReady, at: await job.clipboard.value.readyAt, of: job, in: &latency)
        let request = ClipboardPaste.Request(
            id: job.id, text: text, kind: .dictation(stoppingPress: job.stoppingPress, submits: submits),
            app: job.frontAppAtStop, snapshot: job.clipboard)
        switch await paste.run(request, gate: gate) {
        case .pasted(let pasted):
            Self.mark(.pasteSent, at: pasted.sentAt, of: job, in: &latency)
            if case .sent(let at) = pasted.submit { Self.mark(.returnSent, at: at, of: job, in: &latency) }
            return (.pasted, pasted)
        case .copied:
            return (.copied, nil)
        case .skipped:
            return (.notPasted, nil)
        }
    }

    /// One notice line per transcribed dictation. Notice, not info: the system keeps notice lines on disk, so
    /// `make latency-log` reads them from `log show`.
    private static func log(_ latency: LatencyLog, of job: Job, model: String?) {
        Log.latency.notice(
            """
            \(job.id.rawValue) model=\(model ?? UsageEntry.unknownModel, privacy: .public) \
            audioMs=\(Int(job.audio.duration / .milliseconds(1)), privacy: .public) \
            \(latency.summary, privacy: .public)
            """)
    }

    /// The system measured these moments and hands them over only with the answer, so they are recorded without a
    /// signpost: one emitted now would sit at the wrong moment in Instruments.
    private static func recordNetwork(_ network: NetworkTiming, of job: Job, in latency: inout LatencyLog) {
        if let connected = network.connected { latency.record(.connected, offset: connected - job.keyDown) }
        latency.record(.uploadSent, offset: network.uploadSent - job.keyDown)
        latency.record(.firstByte, offset: network.firstByte - job.keyDown)
    }

    private static func mark(
        _ mark: LatencyMark,
        at instant: ContinuousClock.Instant,
        of job: Job,
        in latency: inout LatencyLog
    ) {
        latency.mark(mark, at: instant, keyDown: job.keyDown)
    }
}

extension Result where Failure == any Error {
    /// `Result(catching:)` for an async body.
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}
