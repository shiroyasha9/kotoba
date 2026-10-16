import Foundation

// MARK: - Transcription and paste

extension DictationPipeline {
    func finish(_ current: Recording, audio: RecordedAudio, clipboard: ClipboardGuard.Pending) async {
        let (keyDown, latency) = latencies.take(current.id)
        let job = TranscriptDelivery.Job(
            id: current.id, audio: audio, createdAt: ports.clock.date, keyDown: keyDown, latency: latency,
            clipboard: clipboard, settings: settings, output: current.output,
            frontAppAtStop: current.frontAppAtStop)
        let outcome = await delivery.deliver(
            job, beforePaste: { await self.waitForChordRelease() },
            beforeCleanup: { await self.cleanupStarted(current.id) },
            isSubmitRequested: { await self.submitRequests.contains(current.id) })
        if let write = outcome.restore {
            work.schedule(at: ports.clock.now + settings.restoreDelay) { await self.clipboard.restore(after: write) }
        }
        finishDictation(current.id, showing: outcome.showing ?? .outcome(of: outcome.record))
        // Learning reads the field only between dictations, and not after a Return submitted it.
        if let readback = ports.readback, outcome.record.status == .pasted, !outcome.isSubmitted, recording == nil,
            paused == nil, let text = outcome.record.deliveredText
        {
            await readback.pasted(text)
        }
        // After the paste: a dictation with text is the event that lets retention run (story 31). Tracked, so the
        // retries below do not wait for the files.
        if outcome.record.status.isTranscribed { work.track { await self.deleteExpiredAudio() } }
        // A transcript proves the route works, credit included: the dictations that waited are sent (decision 6).
        if outcome.record.transcript != nil { await setupChanged() }
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
