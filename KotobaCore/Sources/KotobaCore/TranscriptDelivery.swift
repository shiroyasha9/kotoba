import Foundation

/// The stage after capture: upload, dictionary replacements, paste through the clipboard guard,
/// latency marks and the stored record. The pipeline hands over one finished recording and gets
/// the final record back; it keeps the hotkey, recording and Undo state machine.
struct TranscriptDelivery: Sendable {
    /// One finished recording, with what the stage needs from the pipeline.
    struct Job: Sendable {
        let id: DictationID
        let audio: RecordedAudio
        let createdAt: Date
        let keyDown: ContinuousClock.Instant
        let latency: LatencyLog
        /// The clipboard taken at chord-down, and when it was ready.
        let clipboard: ClipboardGuard.Pending
        let settings: DictationPipeline.Settings
        let mode: DictationMode
        /// The front app at the stop; a submit Return goes only to it, and the record keeps it.
        var frontAppAtStop: FrontApp?
    }

    struct Outcome: Sendable {
        let record: DictationRecord
        /// A transient write to restore after `Settings.restoreDelay`; nil when nothing was pasted.
        let restore: ClipboardGuard.Write?
        /// What the indicator shows instead of the record's usual outcome (for example `.cleanupFailed`).
        var showing: DictationState?
        /// Return followed the paste, so the field was submitted and holds no pasted text to read back.
        var isSubmitted = false
    }

    let provider: any TranscriptionProvider
    /// Used for `.cleanup` jobs; nil pastes the raw transcript.
    let cleaner: (any TextCleaner)?
    let paster: any Paster
    let store: any Store
    let clock: any PipelineClock
    let clipboard: ClipboardGuard
    let frontApp: @Sendable () -> FrontApp?

    /// The transcribe and clean steps, shared with the retry queue.
    private var steps: TranscriptionSteps { TranscriptionSteps(provider: provider, cleaner: cleaner, clock: clock) }

    /// `beforePaste` returns when it is safe to post Cmd-V (the chord is released).
    /// `isSubmitRequested` tells, once pasted, whether the owner stopped with Return or pressed it just after.
    func deliver(
        _ job: Job, beforePaste: @Sendable () async -> Void, isSubmitRequested: @Sendable () async -> Bool = { false }
    ) async -> Outcome {
        var latency = job.latency
        func mark(_ mark: LatencyMark, at instant: ContinuousClock.Instant) {
            Self.mark(mark, at: instant, of: job, in: &latency)
        }

        var record = DictationRecord(
            id: job.id, createdAt: job.createdAt, audio: job.audio, transcript: nil, status: .pending, latency: latency)
        record.mode = job.mode
        record.app = job.frontAppAtStop?.app
        // Saved while the upload runs, so a crash keeps the audio queued.
        let pendingRecord = record
        async let savedPending: Void = store.saveOrLog(pendingRecord)
        mark(.uploadStart, at: clock.now)
        let result: Result<TranscriptionSteps.Transcribed, any Error>
        do {
            result = .success(try await steps.transcribe(&record, settings: job.settings))
        } catch {
            result = .failure(error)
        }
        mark(.response, at: clock.now)
        await savedPending

        var restore: ClipboardGuard.Write?
        var isCleanupFailed = false
        var submitted: Submitted?
        switch result {
        case .failure(let error):
            Log.pipeline.error("Transcription \(job.id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            record.markFailed(by: error)
        case .success(let transcribed):
            if job.mode == .cleanup {
                mark(.cleanStart, at: clock.now)
                await steps.clean(transcribed.raw, into: &record, settings: job.settings)
                mark(.cleanResponse, at: clock.now)
                isCleanupFailed = record.cleanedText == nil
            }
            (record.status, restore) = await paste(
                record.cleanedText ?? transcribed.text, job: job, latency: &latency, beforePaste: beforePaste)
            if record.status == .pasted {
                let isAsked = transcribed.submits ? true : await isSubmitRequested()
                if isAsked { submitted = await submit(job: job, latency: &latency) }
            }
            Log.latency.info("\(job.id.rawValue) \(latency.summary, privacy: .public)")
        }
        record.latency = latency
        // The answers' ledger entries go with this save. A crash between the answer and here (at most the cleanup and
        // the paste, 1-2 s) loses them; the pending row is sent again at the next launch.
        await store.saveOrLog(record)
        let showing = Self.notice(for: record, isCleanupFailed: isCleanupFailed, submitted: submitted)
        return Outcome(record: record, restore: restore, showing: showing, isSubmitted: submitted == .sent)
    }

    /// A copied transcript needs the owner's Cmd-V, so "Copied" wins over the cleanup note. A Return the owner asked
    /// for and did not get wins over the cleanup note too.
    private static func notice(
        for record: DictationRecord, isCleanupFailed: Bool, submitted: Submitted?
    ) -> DictationState? {
        if submitted == .frontAppChanged { return .returnSkipped(record.id) }
        return isCleanupFailed && record.status == .pasted ? .cleanupFailed(record.id) : nil
    }

    /// Return right after the Cmd-V, into the same event stream; the chord is already released. True when sent.
    private enum Submitted {
        case sent
        /// A Return in another app could run the pasted text as a command there.
        case frontAppChanged
        case failed
    }

    private func submit(job: Job, latency: inout LatencyLog) async -> Submitted {
        guard frontApp()?.processID == job.frontAppAtStop?.processID else {
            Log.pipeline.info("Return not sent: the front app changed after the stop")
            return .frontAppChanged
        }
        do {
            try await paster.sendReturn()
            Self.mark(.returnSent, at: clock.now, of: job, in: &latency)
            return .sent
        } catch {
            Log.pipeline.error("Return not sent after the paste: \(error)")
            return .failed
        }
    }

    /// Pastes `text` once the chord is released; when paste is not allowed, leaves it on the clipboard.
    private func paste(
        _ text: String,
        job: Job,
        latency: inout LatencyLog,
        beforePaste: @Sendable () async -> Void
    ) async -> (DictationRecord.Status, ClipboardGuard.Write?) {
        let (snapshot, readyAt) = await job.clipboard.value
        Self.mark(.snapshotReady, at: readyAt, of: job, in: &latency)
        await beforePaste()
        let write = await clipboard.writeTransient(text, over: snapshot)
        do {
            try await paster.sendPaste()
            Self.mark(.pasteSent, at: clock.now, of: job, in: &latency)
            return (.pasted, write)
        } catch {
            Log.pipeline.error("Paste not allowed, transcript left on the clipboard: \(error)")
            await clipboard.copy(text)
            return (.copied, nil)
        }
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
