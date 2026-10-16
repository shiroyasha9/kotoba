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
        let output: DictationOutput
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

    /// The transcribe and clean steps, shared with the retry queue.
    let steps: TranscriptionSteps
    let paster: any Paster
    let store: any Store
    let clock: any PipelineClock
    let clipboard: ClipboardGuard
    let frontApp: @Sendable () -> FrontApp?

    /// `beforePaste` returns when it is safe to post Cmd-V (the chord is released). `beforeCleanup` runs as the
    /// transcript goes to the cleaner, so the indicator can say so. `isSubmitRequested` tells, once pasted, whether the
    /// owner stopped with Return or pressed it just after.
    func deliver(
        _ job: Job, beforePaste: @Sendable () async -> Void, beforeCleanup: @Sendable () async -> Void = {},
        isSubmitRequested: @Sendable () async -> Bool = { false }
    ) async -> Outcome {
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
        let result: Result<TranscriptionSteps.Transcribed, any Error>
        do {
            result = .success(try await steps.transcribe(&record, settings: job.settings))
        } catch {
            result = .failure(error)
        }
        mark(.response, at: clock.now)
        if case .success(let transcribed) = result, let network = transcribed.network {
            Self.recordNetwork(network, of: job, in: &latency)
        }
        await savedPending

        var restore: ClipboardGuard.Write?
        var cleanupMiss: TranscriptionSteps.CleanupMiss?
        var submitted: Submitted?
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
        let showing = Self.notice(for: record, cleanupMiss: cleanupMiss, submitted: submitted)
        return Outcome(record: record, restore: restore, showing: showing, isSubmitted: submitted == .sent)
    }

    /// A copied transcript needs the owner's Cmd-V, so "Copied" wins over the cleanup note. A Return the owner asked
    /// for and did not get wins over the cleanup note too.
    private static func notice(
        for record: DictationRecord, cleanupMiss: TranscriptionSteps.CleanupMiss?, submitted: Submitted?
    ) -> DictationState? {
        if submitted == .frontAppChanged { return .returnSkipped(record.id) }
        guard record.status == .pasted, let cleanupMiss else { return nil }
        return switch cleanupMiss {
        case .failed: .cleanupFailed(record.id)
        case .tooSlow: .cleanupTooSlow(record.id)
        }
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
