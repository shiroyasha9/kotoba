import Foundation

// MARK: - Transcription and paste

extension DictationPipeline {
    /// `audio` is nil when the audio source ran no capture: the stop says nothing was recorded and keeps nothing.
    /// Audio shorter than `Settings.minimumRecording` (an accidental double tap) is discarded with no word, unless the
    /// file stopped taking audio (`RecordedAudio.loss`): then the pill says the audio was not saved. A longer
    /// incomplete file is sent; its paste says the text has only the part saved (`TranscriptDelivery`).
    func finish(_ current: Recording, audio: RecordedAudio?, clipboard: ClipboardPaste.PendingSnapshot) async {
        let (keyDown, latency) = live.latency(of: current.id) ?? (ports.clock.now, LatencyLog())
        guard let audio else {
            finishDictation(current.id, showing: .nothingRecorded)
            return
        }
        // Microphone access went off while kotoba runs: the mic gave only zeros, so nothing is sent or billed. Read
        // only for a recording that never heard a sound.
        guard current.sound.hasHeardSound || ports.isMicrophoneAllowed() else {
            await remember(current.id, unless: await ports.audio.discard(audio))
            finishDictation(current.id, showing: .captureFailed)
            return
        }
        guard audio.duration >= settings.minimumRecording else {
            await remember(current.id, unless: await ports.audio.discard(audio))
            finishDictation(current.id, showing: audio.loss.map(DictationNotice.audioNotSaved))
            return
        }
        let job = TranscriptDelivery.Job(
            id: current.id, audio: audio, createdAt: ports.clock.date, keyDown: keyDown, latency: latency,
            clipboard: clipboard, settings: settings, output: current.output,
            frontAppAtStop: current.frontAppAtStop, stoppingPress: current.stoppingPress,
            segments: live.takeSegments(of: current.id))
        let outcome = await delivery.deliver(
            job, gate: self, beforeCleanup: { await self.cleanupStarted(current.id) })
        finishDictation(
            current.id, showing: outcome.showing ?? .outcome(of: outcome.record),
            isPasted: outcome.record.status == .pasted)
        if let wait = outcome.record.lastError?.retryAfter { scheduleRetry(after: wait) }
        // Return submitted the field: the text is no longer where it was pasted.
        if outcome.isSubmitted {
            lastPaste = nil
        } else if let pasted = outcome.pasted, let text = outcome.record.deliveredText {
            markPasted(text, at: pasted.place)
        }
        // Learning reads the field only between dictations, and not after a Return submitted it.
        if let readback = ports.readback, outcome.record.status == .pasted, !outcome.isSubmitted, !live.hasRecording,
            let text = outcome.record.deliveredText
        {
            await readback.pasted(text)
        }
        reportTerms(of: outcome.record)
        // After the paste: a dictation with text is the event that lets retention run (story 31). Tracked, so the
        // retries below do not wait for the files.
        if outcome.record.status.isTranscribed { work.track { await self.deleteExpiredAudio() } }
        // Tracked, so this dictation's work ends here while the retries wait for a quiet moment.
        if outcome.record.transcript != nil { work.track { await self.routeAnswered() } }
    }

    /// Shows `notice` only while nothing is live, so it never hides a dictation; nil shows idle.
    func showIfQuiet(_ notice: DictationNotice?) {
        guard isQuiet else { return }
        if let notice { show(notice) } else { emit(.idle) }
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
        live.cleanupStarted(id)
        guard !live.hasRecording else { return }
        emit(inFlightPhase)
    }

    /// Return while recording stops it. Just after a stop the tap may still swallow a Return (the indicator has not
    /// left recording yet), so it goes to the dictation that stopped, while that one is not yet pasted.
    func requestSubmit(at now: Instant) {
        live.askSubmit()
        if let recording {
            stop(recording, at: now)
        }
    }

    /// A Cmd-V posted while a chord is held reaches the app as Ctrl+Opt+Cmd+V, so the paste waits for every press to
    /// end. Only the press that stopped this dictation (`stoppingPress`) can have lost its release: it holds the paste
    /// for `Settings.chordReleaseWait` at most. A later press (the next push-to-talk hold) holds it until its release,
    /// however long; a lost one is repaired at the next key event (`HotkeyMissedReleaseTests`).
    private func waitForChordRelease(after stoppingPress: Int?) async {
        // The owner away (`absenceBegan`) ends the wait: the text is copied, not pasted.
        while isChordDown, isPresent, !isQuitting {
            let isStoppingPress = press == stoppingPress
            let bound =
                isStoppingPress
                ? work.schedule(at: ports.clock.now + settings.chordReleaseWait) { await self.endReleaseWait() } : nil
            await withCheckedContinuation { releaseWaiters.add($0) }
            bound?.cancel()
            // Still the stopping press after the wake: the bound passed, its release was lost.
            if isStoppingPress, isChordDown, press == stoppingPress { return }
        }
    }

    private func endReleaseWait() {
        releaseWaiters.resumeAll()
    }
}

// MARK: - The paste gate

extension DictationPipeline: PasteGate {
    /// A dictation's paste waits for the chord's release; Paste Again and Polish wait for nothing. A dictation that
    /// started since overtakes them, and a Polish overtakes Paste Again. Polish checked the store for a newer
    /// dictation after its selection; one delivered since then was live at that check. Nothing pastes while the owner
    /// is away or kotoba quits.
    func facts(for request: ClipboardPaste.Request) async -> ClipboardPaste.Facts {
        let isOvertaken: Bool
        switch request.kind {
        case .dictation(let stoppingPress, _):
            await waitForChordRelease(after: stoppingPress)
            isOvertaken = false
        case .again:
            isOvertaken = !isQuiet
        case .polish:
            isOvertaken = live.isDictationLive
        }
        return ClipboardPaste.Facts(isQuitting: isQuitting, isPresent: isPresent, isOvertaken: isOvertaken)
    }

    func isSubmitAsked(_ request: ClipboardPaste.Request) -> Bool {
        live.isSubmitAsked(request.id)
    }

    /// The paste did not land, so Polish never deletes it by Backspace. A dictation's own paste leaves its row copied,
    /// not pasted; Paste Again and Polish leave the row as it was. When the text is still on the clipboard, the pill
    /// says so if no dictation shows.
    func pasteWentUnread(_ request: ClipboardPaste.Request, isLeftOnClipboard: Bool) async {
        let id = request.id
        Log.pipeline.notice("No app read the paste of \(id.rawValue); left on the clipboard: \(isLeftOnClipboard)")
        if lastPaste?.text == request.text { lastPaste = nil }
        if case .dictation = request.kind {
            do {
                try await ports.store.markCopied(id)
            } catch {
                Log.pipeline.error("Cannot mark \(id.rawValue) copied: \(error)")
            }
        }
        if isLeftOnClipboard { showIfQuiet(.copied(id)) }
    }
}
