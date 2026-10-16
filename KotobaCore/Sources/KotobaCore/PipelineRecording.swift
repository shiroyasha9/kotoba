import Foundation

// MARK: - Recording

extension DictationPipeline {
    func start(_ gesture: ChordGesture, at now: Instant) async {
        let id = DictationID()
        let file = settings.audioDirectory.appending(path: id.audioFileName)
        // The connection warms while the engine starts.
        work.track { [provider = ports.provider] in await provider.warmUp() }
        let modes = settings.modes
        let cleansAtKeyDown = modes.cleansEveryDictation.contains(modes.mode(for: ports.frontApp()?.app))
        let isCleanerWarm = cleansAtKeyDown && warmCleaner()
        if let captureEnd {
            _ = await captureEnd.value
        }
        let events: AsyncStream<CaptureEvent>
        do {
            events = try await ports.audio.beginCapture(into: file)
        } catch {
            Log.pipeline.error("Capture did not start: \(error)")
            emit(.captureFailed)
            return
        }
        latencies.begin(id, keyDown: now)
        let captureEvents = Task {
            for await event in events {
                switch event {
                case .firstBuffer(let instant):
                    self.latencies.mark(.firstAudioBuffer, of: id, at: instant)
                case .level(let level):
                    self.soundChanged(of: id) { $0.level(level, at: self.ports.clock.now) }
                case .inputLost:
                    self.soundChanged(of: id) { $0.inputLost() }
                }
            }
        }
        recording = Recording(
            id: id,
            file: file,
            startedAt: now,
            isUndecided: isChordDown,
            gesture: gesture,
            cleansAtKeyDown: cleansAtKeyDown,
            isCleanerWarm: isCleanerWarm,
            captureEvents: captureEvents,
            warning: work.schedule(at: now + settings.longRecordingWarning) { await self.warnLong(id) },
            announcement: work.schedule(at: now + settings.tapThreshold) { [threshold = settings.tapThreshold] in
                await self.announce(id, at: now + threshold)
            },
            sound: NoSoundPolicy(delay: settings.noSoundWarning, startingAt: now)
        )
        armSoundDeadline(of: id)
    }

    /// Keeps one timer at the policy's deadline, so a mic that sends no levels, or stops sending, warns too. While
    /// sound arrives it wakes at most once per `Settings.noSoundWarning` and sets itself again.
    private func armSoundDeadline(of id: DictationID) {
        guard recording?.id == id, recording?.soundDeadline == nil, let deadline = recording?.sound.deadline else {
            return
        }
        recording?.soundDeadline = work.schedule(at: deadline) { await self.soundDeadlineCame(of: id) }
    }

    private func soundDeadlineCame(of id: DictationID) {
        guard recording?.id == id else { return }
        recording?.soundDeadline = nil
        soundChanged(of: id) { [now = ports.clock.now] in $0.deadlinePassed(at: now) }
    }

    /// A meter level or a lost mic of the live recording: the no-sound warning shows or clears.
    private func soundChanged(of id: DictationID, _ update: (inout NoSoundPolicy) -> Bool) {
        handledSoundEvents += 1
        guard recording?.id == id, var sound = recording?.sound else { return }
        let isSilent = update(&sound)
        recording?.sound = sound
        armSoundDeadline(of: id)
        guard recording?.isAnnounced == true, case .recording(let isLong, _, let isCleaned) = state else { return }
        emit(.recording(isLong: isLong, isSilent: isSilent, isCleaned: isCleaned))
    }

    /// The recording is still live after `Settings.longRecordingWarning`; it never stops on its own.
    private func warnLong(_ id: DictationID) {
        if recording?.id == id {
            emit(
                .recording(
                    isLong: true, isSilent: recording?.sound.isWarning ?? false,
                    isCleaned: recording?.isCleaned ?? false))
        }
    }

    /// Shows the recording: the indicator appears and the start cue plays. The edit session of the last paste ends
    /// here, not at key-down, so a press that turns out to be a shortcut (⌥⌫ with ⌥ for push to talk) leaves it on.
    func announce(_ id: DictationID, at instant: Instant) async {
        guard let current = recording, current.id == id, !current.isAnnounced else { return }
        recording?.isAnnounced = true
        recording?.clipboard = takeClipboard()
        current.announcement.cancel()
        latencies.mark(.cue, of: id, at: instant)
        primeRoute(for: id)
        emit(.recording(isLong: false, isSilent: current.sound.isWarning, isCleaned: current.isCleaned))
        await ports.readback?.dictationStarted()
    }

    /// Sends the route's primer (`TranscriptionProvider.prime`) unless one is on its way, and keeps the live recording
    /// primed every `Settings.primerInterval`; a route with no primer gets neither. Nothing waits for it. Its cost goes
    /// to the ledger with this dictation, with no audio and no words, so minutes and words per minute stay what the
    /// owner dictated.
    func primeRoute(for id: DictationID) {
        guard ports.provider.hasPrimer, !isPrimerInFlight else { return }
        isPrimerInFlight = true
        primedAt = ports.clock.now
        armPrimer(for: id)
        let language = settings.language
        work.track { [provider = ports.provider, store = ports.store, clock = ports.clock] in
            let primer = await provider.prime(language: language)
            await self.primerFinished()
            guard let primer else { return }
            do {
                try await store.addUsage([
                    UsageEntry(
                        time: clock.date, dictation: id, kind: .speech, model: primer.model, deliveredWords: 0,
                        cost: primer.usage.cost)
                ])
            } catch {
                Log.pipeline.error("Primer \(id.rawValue): cannot bill it: \(error)")
            }
        }
    }

    /// The next primer of the live recording `id`, `Settings.primerInterval` after the last one was sent (at once when
    /// that is past, as after a long Undo window). The stop and Esc cancel it.
    func armPrimer(for id: DictationID) {
        guard recording?.id == id, recording?.primerTimer == nil, let primedAt else { return }
        recording?.primerTimer = work.schedule(at: primedAt + settings.primerInterval) {
            await self.primerTimerFired(id)
        }
    }

    /// A primer that was still on its way at its recording's timer skipped that one; the next is armed here, unless
    /// the route changed to one with no primer meanwhile.
    private func primerFinished() {
        isPrimerInFlight = false
        if let id = recording?.id, ports.provider.hasPrimer { armPrimer(for: id) }
    }

    private func primerTimerFired(_ id: DictationID) {
        guard recording?.id == id else { return }
        recording?.primerTimer = nil
        primeRoute(for: id)
    }

    private func takeClipboard() -> ClipboardGuard.Pending {
        Task { [clipboard, clock = ports.clock] in (snapshot: await clipboard.snapshot(), readyAt: clock.now) }
    }

    /// Opens the cleaner's connection as tracked work; false when there is no cleaner.
    func warmCleaner() -> Bool {
        guard let cleaner = ports.cleaner else { return false }
        work.track { await cleaner.warmUp() }
        return true
    }

    /// Clears the live recording and its timers.
    func endRecording(_ current: Recording) {
        recording = nil
        current.warning.cancel()
        current.announcement.cancel()
        current.soundDeadline?.cancel()
        current.primerTimer?.cancel()
    }

    func stop(_ current: Recording, at now: Instant) {
        var current = current
        current.frontAppAtStop = ports.frontApp()
        current.output = settings.modes.output(for: current.frontAppAtStop?.app, isCleanupChord: current.isCleanupSeen)
        // Warmed while the audio is sent, so the cleanup request finds the connection open.
        if current.output != .transcript, !current.isCleanerWarm {
            _ = warmCleaner()
        }
        endRecording(current)
        latencies.mark(.stop, of: current.id, at: now)
        inFlight.insert(current.id)
        lastStopped = current.id
        emit(.transcribing)
        let ended = Task { await self.endCapture(of: current) }
        captureEnd = ended
        let clipboard = current.clipboard ?? takeClipboard()
        work.track { await self.finish(current, audio: await ended.value, clipboard: clipboard) }
    }

    /// Stops after the buffer that holds the stop moment, with the length the audio source wrote. Nil when it ran no
    /// capture: nothing was written, so there is no dictation to keep.
    func endCapture(of current: Recording) async -> RecordedAudio? {
        let audio = await ports.audio.endCapture()
        if audio == nil { Log.pipeline.error("The capture was gone at the stop, nothing was recorded") }
        await current.captureEvents.value
        return audio
    }

    func cancel(_ current: Recording) async {
        endRecording(current)
        let audio = await ports.audio.cancelCapture()
        await current.captureEvents.value
        await keep(current, audio: audio, as: .cancelled)
        emit(inFlightState)
        resumeQuietWaiters()
    }

    /// Saves a recording that is not transcribed now, with its audio and latency marks.
    func keep(_ current: Recording, audio: RecordedAudio?, as status: DictationRecord.Status) async {
        let latency = latencies.take(current.id).log
        guard let audio else { return }
        var record = DictationRecord(
            id: current.id, createdAt: ports.clock.date, audio: audio, transcript: nil, status: status, latency: latency
        )
        // Esc keeps the app in front at the Esc; quit comes before any stop, so the app in front now is where the text
        // would have gone. Its mode is what a later retry cleans in.
        record.app = (current.frontAppAtStop ?? ports.frontApp())?.app
        record.output = settings.modes.output(for: record.app, isCleanupChord: current.isCleanupSeen)
        await ports.store.saveOrLog(record)
    }

    /// Esc: the mic goes off, the file stays open, and Undo can resume until the window closes.
    func pause(_ current: Recording, at now: Instant) async {
        var current = current
        // A cancel that becomes final keeps the app and the mode of the Esc, not of the app in front 5 s later.
        current.frontAppAtStop = ports.frontApp()
        recording = nil
        current.announcement.cancel()
        current.soundDeadline?.cancel()
        current.primerTimer?.cancel()
        current.primerTimer = nil
        latencies.mark(.cancel, of: current.id, at: now)
        paused = UndoWindow(item: current, duration: settings.undoWindow, at: now) { [id = current.id] in
            work.schedule(at: $0) { await self.closeUndoWindow(of: id) }
        }
        emit(.undoable)
        await ports.audio.pauseCapture()
    }

    func resume(at now: Instant) async {
        guard let current = paused else { return }
        paused = nil
        current.timer.cancel()
        do {
            try await ports.audio.resumeCapture()
        } catch {
            Log.pipeline.error("Capture did not resume, the cancel is final: \(error)")
            await cancel(current.item)
            return
        }
        var resumed = current.item
        resumed.isUndecided = false
        resumed.isAnnounced = true
        resumed.sound.restart(at: now)
        resumed.soundDeadline = nil
        recording = resumed
        armSoundDeadline(of: resumed.id)
        armPrimer(for: resumed.id)
        latencies.mark(.resume, of: resumed.id, at: now)
        emit(.recording(isLong: now - resumed.startedAt >= settings.longRecordingWarning, isCleaned: resumed.isCleaned))
    }

    /// No Undo in time: the cancel is final and the audio stays in history.
    func closeUndoWindow(of id: DictationID) async {
        guard let current = paused, current.item.id == id, !current.countdown.isHeld else { return }
        paused = nil
        await cancel(current.item)
    }

    /// Drops a recording that turned out to be part of another app's shortcut: no row, no file, no cue. A file that
    /// stays on disk is remembered as discarded, so no launch takes it for an orphan and sends it (`OrphanAudio`).
    func discard(_ current: Recording) async {
        endRecording(current)
        await remember(current.id, unless: await ports.audio.discardCapture())
        await current.captureEvents.value
        _ = latencies.take(current.id)
        emit(inFlightState)
        resumeQuietWaiters()
    }

    /// Remembers a discarded recording whose file stayed on disk (`isDeleted` false).
    func remember(_ id: DictationID, unless isDeleted: Bool) async {
        guard !isDeleted else { return }
        do {
            try await ports.store.markDiscarded(id)
        } catch {
            Log.pipeline.error("Cannot remember discarded audio \(id.rawValue): \(error)")
        }
    }
}
