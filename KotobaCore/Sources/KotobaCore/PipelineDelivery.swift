import Foundation

// MARK: - Transcription and paste

extension DictationPipeline {
    /// `audio` is nil when the audio source ran no capture: the stop says nothing was recorded and keeps nothing.
    /// Audio shorter than `Settings.minimumRecording` (an accidental double tap) is discarded with no word, unless the
    /// file stopped taking audio (`RecordedAudio.loss`): then the pill says the audio was not saved. A longer
    /// incomplete file is sent; its paste says the text has only the part saved (`TranscriptDelivery`).
    func finish(_ current: Recording, audio: RecordedAudio?, clipboard: ClipboardGuard.Pending) async {
        let (keyDown, latency) = latencies.take(current.id)
        guard let audio else {
            finishDictation(current.id, showing: .nothingRecorded)
            return
        }
        guard audio.duration >= settings.minimumRecording else {
            await remember(current.id, unless: await ports.audio.discard(audio))
            finishDictation(current.id, showing: audio.loss.map(DictationState.audioNotSaved) ?? .idle)
            return
        }
        let job = TranscriptDelivery.Job(
            id: current.id, audio: audio, createdAt: ports.clock.date, keyDown: keyDown, latency: latency,
            clipboard: clipboard, settings: settings, output: current.output,
            frontAppAtStop: current.frontAppAtStop)
        let outcome = await delivery.deliver(
            job,
            beforePaste: {
                await self.waitForChordRelease()
                await self.takePasteTarget(for: current.id)
            },
            beforeCleanup: { await self.cleanupStarted(current.id) },
            isSubmitRequested: { await self.submitRequests.contains(current.id) })
        if let write = outcome.restore {
            work.schedule(at: ports.clock.now + settings.restoreDelay) { await self.clipboard.restore(after: write) }
        }
        finishDictation(current.id, showing: outcome.showing ?? .outcome(of: outcome.record))
        // Return submitted the field: the text is no longer where it was pasted.
        let target = pasteTargets.removeValue(forKey: current.id)
        if outcome.isSubmitted {
            lastPaste = nil
        } else if outcome.record.status == .pasted, let text = outcome.record.deliveredText {
            markPasted(text, at: target)
        }
        // Learning reads the field only between dictations, and not after a Return submitted it.
        if let readback = ports.readback, outcome.record.status == .pasted, !outcome.isSubmitted, recording == nil,
            paused == nil, let text = outcome.record.deliveredText
        {
            await readback.pasted(text)
        }
        reportTerms(of: outcome.record)
        // After the paste: a dictation with text is the event that lets retention run (story 31). Tracked, so the
        // retries below do not wait for the files.
        if outcome.record.status.isTranscribed { work.track { await self.deleteExpiredAudio() } }
        // A transcript proves the route works, credit included: the dictations that waited are sent (decision 6).
        if outcome.record.transcript != nil { await setupChanged() }
    }

    /// After the paste: which keyterms the request sent, and which the delivered text has. Over every keyterm, sent or
    /// not, so a term the model wrote without the hint earns its place back.
    func reportTerms(of record: DictationRecord) {
        guard record.status.isTranscribed, let sent = record.sentTerms, let text = record.deliveredText else { return }
        let (keyterms, at) = (settings.dictionary.keyterms, ports.clock.date)
        work.track { [termReportContinuation] in
            let hits = await Self.hits(of: keyterms, in: text)
            termReportContinuation.yield(TermReport(sent: sent, hits: hits, at: at))
        }
    }

    /// Off the pipeline actor, so the next key-down never waits: 300 keyterms take about 0.15 ms on 50 words and 3 ms
    /// on 2,000 (release build).
    @concurrent private static func hits(of keyterms: [String], in text: String) async -> [String] {
        TermHits.find(keyterms, in: text)
    }

    /// The transcript of `id` went to the cleaner: the indicator says so, unless a new recording or an Undo window
    /// shows, or another dictation is still being transcribed.
    func cleanupStarted(_ id: DictationID) {
        cleaning.insert(id)
        guard recording == nil, paused == nil else { return }
        emit(inFlightState)
    }

    /// Return while recording stops it. Just after a stop the tap may still swallow a Return (the indicator has not
    /// left recording yet), so it goes to the dictation that stopped, while that one is not yet pasted.
    func requestSubmit(at now: Instant) {
        if let recording {
            submitRequests.insert(recording.id)
            stop(recording, at: now)
        } else if let id = lastStopped, inFlight.contains(id) {
            submitRequests.insert(id)
        }
    }

    /// A Cmd-V posted while the chord is held reaches the app as Ctrl+Opt+Cmd+V. A release that never comes holds
    /// the paste only for `Settings.chordReleaseWait`.
    private func waitForChordRelease() async {
        guard isChordDown else { return }
        let bound = work.schedule(at: ports.clock.now + settings.chordReleaseWait) { await self.endReleaseWait() }
        await withCheckedContinuation { releaseWaiters.add($0) }
        bound.cancel()
    }

    private func endReleaseWait() {
        releaseWaiters.resumeAll()
    }
}
