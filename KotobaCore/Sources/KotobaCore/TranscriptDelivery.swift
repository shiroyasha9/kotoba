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
        /// No app read the paste (`ClipboardGuard.Unread`).
        let pasteWentUnread: @Sendable (_ text: String, _ isLeftOnClipboard: Bool) async -> Void
    }

    struct Outcome: Sendable {
        let record: DictationRecord
        /// The transient write that waits for the app's read (`ClipboardGuard`); nil when nothing was pasted or the
        /// earlier clipboard was too large to keep.
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

    /// `beforePaste` returns when it is safe to post Cmd-V (the chord is released): false when the text must not paste
    /// now (the owner is away), so it waits on the clipboard. `beforeCleanup` runs as the
    /// transcript goes to the cleaner, so the indicator can say so. `isSubmitRequested` tells, once pasted, whether the
    /// owner stopped with Return or pressed it just after.
    func deliver(
        _ job: Job, beforePaste: @Sendable () async -> Bool, beforeCleanup: @Sendable () async -> Void = {},
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
        let result = await Result { try await steps.transcribe(&record, settings: job.settings) }
        mark(.response, at: clock.now)
        if case .success(let transcribed) = result, let network = transcribed.network {
            Self.recordNetwork(network, of: job, in: &latency)
        }
        await savedPending

        var restore: ClipboardGuard.Write?
        var cleanupMiss: TranscriptionSteps.CleanupMiss?
        var submitted: Submitted?
        var failure: DictationState?
        switch result {
        case .failure(let error):
            Log.pipeline.error("Transcription \(job.id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            record.markFailed(by: error)
            // A timeout says so: "offline" would send the owner to check a network that works.
            if error as? ProviderError == .timedOut { failure = .timedOut(record.id) }
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
            Self.log(latency, of: job, model: record.model)
        }
        record.latency = latency
        // The answers' ledger entries go with this save. A crash between the answer and here (at most the cleanup and
        // the paste, 1-2 s) loses them; the pending row is sent again at the next launch.
        await store.saveOrLog(record)
        let showing =
            failure ?? Self.notice(for: record, of: job, restore, cleanupMiss: cleanupMiss, submitted: submitted)
        return Outcome(record: record, restore: restore, showing: showing, isSubmitted: submitted == .sent)
    }

    /// A copied transcript needs the owner's Cmd-V, so "Copied" wins over the cleanup note. A Return the owner asked
    /// for and did not get wins over the cleanup note too, and the cleanup note over a cut recording's. Lost audio
    /// matters more than a lost clipboard (a paste with no `restore` did not keep the earlier clipboard).
    private static func notice(
        for record: DictationRecord, of job: Job, _ restore: ClipboardGuard.Write?,
        cleanupMiss: TranscriptionSteps.CleanupMiss?, submitted: Submitted?
    ) -> DictationState? {
        if submitted == .frontAppChanged { return .returnSkipped(record.id) }
        guard record.status == .pasted else { return nil }
        switch cleanupMiss {
        case .failed: return .cleanupFailed(record.id)
        case .tooSlow: return .cleanupTooSlow(record.id)
        case nil: break
        }
        if let loss = job.audio.loss { return .audioCut(record.id, loss) }
        return restore == nil ? .clipboardNotKept(record.id) : nil
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
        beforePaste: @Sendable () async -> Bool
    ) async -> (DictationRecord.Status, ClipboardGuard.Write?) {
        let (snapshot, readyAt) = await job.clipboard.value
        Self.mark(.snapshotReady, at: readyAt, of: job, in: &latency)
        let mayPaste = await beforePaste()
        // The owner went to another app after the stop (a late answer): the text never goes there, it waits on the
        // clipboard (lead, 2026-10-17). With no app known at the stop, or now, nothing says it changed.
        let isFrontAppChanged =
            job.frontAppAtStop.map { atStop in
                frontApp().map { $0.processID != atStop.processID } ?? false
            } ?? false
        guard mayPaste, !isFrontAppChanged else {
            Log.pipeline.info("Not pasted (owner away, or another app in front); the text is on the clipboard")
            await clipboard.copy(text)
            return (.copied, nil)
        }
        let write = await clipboard.writeTransient(text, over: snapshot) { await job.pasteWentUnread(text, $0) }
        if let write { await clipboard.willPaste(write, readBy: clock.now + job.settings.readWait) }
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
