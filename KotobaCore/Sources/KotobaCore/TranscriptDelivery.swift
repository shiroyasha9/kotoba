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
    }

    struct Outcome: Sendable {
        let record: DictationRecord
        /// A transient write to restore after `Settings.restoreDelay`; nil when nothing was pasted.
        let restore: ClipboardGuard.Write?
        /// What the indicator shows instead of the record's usual outcome (for example `.cleanupFailed`).
        var showing: DictationState?
    }

    let provider: any TranscriptionProvider
    /// Used for `.cleanup` jobs; nil pastes the raw transcript.
    let cleaner: (any TextCleaner)?
    let paster: any Paster
    let store: any Store
    let clock: any PipelineClock
    let clipboard: ClipboardGuard

    /// The transcribe and clean steps, shared with the retry queue.
    private var steps: TranscriptionSteps { TranscriptionSteps(provider: provider, cleaner: cleaner) }

    /// `beforePaste` returns when it is safe to post Cmd-V (the chord is released).
    func deliver(_ job: Job, beforePaste: @Sendable () async -> Void) async -> Outcome {
        var latency = job.latency
        func mark(_ mark: LatencyMark, at instant: ContinuousClock.Instant) {
            Self.mark(mark, at: instant, of: job, in: &latency)
        }

        var record = DictationRecord(
            id: job.id, createdAt: job.createdAt, audio: job.audio, transcript: nil, status: .pending, latency: latency)
        record.mode = job.mode
        // Saved while the upload runs, so a crash keeps the audio queued.
        let pendingRecord = record
        async let savedPending: Void = store.saveOrLog(pendingRecord)
        mark(.uploadStart, at: clock.now)
        let result: Result<TranscriptionSteps.Transcribed, any Error>
        do {
            result = .success(try await steps.transcribe(job.audio, settings: job.settings))
        } catch {
            result = .failure(error)
        }
        mark(.response, at: clock.now)
        await savedPending

        var restore: ClipboardGuard.Write?
        var isCleanupFailed = false
        switch result {
        case .failure(let error):
            Log.pipeline.error("Transcription \(job.id.rawValue) failed: \(error)")
            record.markFailed(by: error)
        case .success(let transcribed):
            record.transcript = transcribed.text
            record.model = transcribed.model
            if job.mode == .cleanup {
                mark(.cleanStart, at: clock.now)
                record.cleanedText = await steps.clean(transcribed.raw, settings: job.settings, id: job.id)
                mark(.cleanResponse, at: clock.now)
                isCleanupFailed = record.cleanedText == nil
            }
            (record.status, restore) = await paste(
                record.cleanedText ?? transcribed.text, job: job, latency: &latency, beforePaste: beforePaste)
            Log.latency.info("\(job.id.rawValue) \(latency.summary, privacy: .public)")
        }
        record.latency = latency
        await store.saveOrLog(record)
        // A copied transcript needs the owner's Cmd-V, so "Copied" wins over the cleanup note.
        let showing: DictationState? = isCleanupFailed && record.status == .pasted ? .cleanupFailed(job.id) : nil
        return Outcome(record: record, restore: restore, showing: showing)
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
