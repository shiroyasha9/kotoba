import Foundation

/// The dictation pipeline core. Hotkey events go in; every effect goes out through a port.
///
/// Call `handle(_:at:)` from one serial consumer, so events keep their order.
public actor DictationPipeline {
    typealias Instant = ContinuousClock.Instant

    private struct Recording {
        let id: DictationID
        let file: URL
        let startedAt: Instant
        /// True until the chord-up that decides tap or hold.
        var isUndecided: Bool
        /// The cleanup modifier was seen before the announcement; it cannot change after it.
        var isCleanupSeen = false
        /// The indicator and start cue are on. They wait until the press is a tap (released in
        /// time) or a hold (threshold passed), so a shortcut press shows and plays nothing.
        var isAnnounced = false
        let captureEvents: Task<Void, Never>
        /// The clipboard, taken at the announcement (so a shortcut press reads nothing) while capture runs.
        var clipboard: ClipboardGuard.Pending?
        let warning: Task<Void, Never>
        let announcement: Task<Void, Never>
    }

    public private(set) var state: DictationState = .idle
    /// Every state change, for the indicator and sound cues.
    public nonisolated let states: AsyncStream<DictationState>

    private let ports: Ports
    private var settings: Settings
    private let clipboard: ClipboardGuard
    /// The retry queue, and the Recovered list the menu shows.
    public nonisolated let retries: RetryQueue
    private let delivery: TranscriptDelivery
    private let stateContinuation: AsyncStream<DictationState>.Continuation
    private var recording: Recording?
    /// Set while Esc's Undo window is open.
    private var paused: UndoWindow<Recording>?
    private var isChordDown = false
    /// Pastes waiting for the chord to be released.
    private var releaseWaiters = Waiters()
    private var latencies = LatencyRecorder()
    /// Dictations being transcribed in this process; a retry skips them.
    private var inFlight: Set<DictationID> = []
    private let work: PendingWork
    /// The last stop's capture end; a new capture starts only after it, so the two never overlap.
    private var captureEnd: Task<RecordedAudio, Never>?
    /// Retries waiting until no dictation is live.
    private var quietWaiters = Waiters()

    public init(ports: Ports, settings: Settings) {
        self.ports = ports
        self.settings = settings
        work = PendingWork(clock: ports.clock)
        clipboard = ClipboardGuard(pasteboard: ports.pasteboard)
        delivery = TranscriptDelivery(
            provider: ports.provider, cleaner: ports.cleaner, paster: ports.paster, store: ports.store,
            clock: ports.clock, clipboard: clipboard)
        retries = RetryQueue(
            steps: TranscriptionSteps(provider: ports.provider, cleaner: ports.cleaner), store: ports.store,
            clock: ports.clock, clipboard: clipboard)
        (states, stateContinuation) = AsyncStream.makeStream(of: DictationState.self)
    }

    /// `instant` is when the key event happened (the tap's time); nil means now. Tap vs hold and
    /// the latency marks use it, so a slow step before this call does not change them.
    public func handle(_ event: HotkeyEvent, at instant: ContinuousClock.Instant? = nil) async {
        let now = instant ?? ports.clock.now
        switch event {
        case .chordDown: await chordDown(at: now)
        case .cleanupModifier: cleanupModifier()
        case .chordUp: await chordUp(at: now)
        case .escape:
            if let recording {
                await pause(recording, at: now)
            }
        case .chordInterrupted: await chordInterrupted()
        }
    }

    /// Resumes the recording that Esc cancelled, while the Undo window is open.
    public func undo() async {
        await resume(at: ports.clock.now)
    }

    /// Transcribes kept dictations into the Recovered list (`retries.recovered()`), each send after
    /// no dictation is live. With no `selection` (launch, the menu), dictations that wait for a
    /// setting are included only when the current route has everything it needs.
    public func retryPending(_ chosen: RetrySelection? = nil) async {
        let isSetUp = await ports.missingSetup() == nil
        let selection = chosen ?? (isSetUp ? .all : .exceptNeedsSetup)
        let results = await retries.run(
            selection, settings: { await self.settings }, skipping: { await self.inFlight.contains($0) },
            waitUntilQuiet: { await self.waitUntilQuiet() })
        for record in results where isQuiet {
            emit(.outcome(of: record))
        }
    }

    /// A key or an endpoint was saved: once the route has everything it needs, the dictations that
    /// waited for a setting are sent again, once each.
    public func setupChanged() async {
        guard await ports.missingSetup() == nil else { return }
        await retryPending(.onlyNeedsSetup)
    }

    /// The owner edited the dictionary: the next request, paste and retry use it.
    public func updateDictionary(_ dictionary: PersonalDictionary) async {
        settings.dictionary = dictionary
    }

    /// Quit: a live recording is saved `.pending` (transcribed at the next launch, into Recovered),
    /// and a recording in its Undo window is saved `.cancelled`. Nothing is lost.
    public func shutdown() async {
        if let current = paused {
            paused = nil
            current.timer.cancel()
            await cancel(current.item)
        }
        if let current = recording {
            endRecording(current)
            await keep(current, audio: await endCapture(of: current), as: .pending)
        }
    }

    // MARK: Hotkey events

    private func chordDown(at now: Instant) async {
        isChordDown = true
        if paused != nil {
            paused?.pressBegan(at: now)
        } else if let recording {
            stop(recording, at: now)
        } else {
            await start(at: now)
        }
    }

    private func chordUp(at now: Instant) async {
        isChordDown = false
        releaseWaiters.resumeAll()
        if paused?.isPressing == true {
            if paused?.pressEnded(at: now, threshold: settings.tapThreshold) == true {
                await resume(at: now)
            }
            return
        }
        guard let current = recording, current.isUndecided else { return }
        if now - current.startedAt < settings.tapThreshold {
            recording?.isUndecided = false
            announce(current.id, at: now)
        } else {
            stop(current, at: now)
        }
    }

    /// Counts only before the announcement, so the press that starts a dictation decides its mode.
    private func cleanupModifier() {
        guard let current = recording, !current.isAnnounced, !current.isCleanupSeen else { return }
        recording?.isCleanupSeen = true
        if let cleaner = ports.cleaner {
            work.track { await cleaner.warmUp() }
        }
    }

    private func chordInterrupted() async {
        if paused?.isPressing == true {
            paused?.pressInterrupted()
            return
        }
        // Only the press that started this recording, before its cue, is a shortcut; a later key is typing.
        if let recording, recording.isUndecided, !recording.isAnnounced {
            await discard(recording)
        }
    }
}

// MARK: - Recording

extension DictationPipeline {
    private func start(at now: Instant) async {
        let id = DictationID()
        let file = settings.audioDirectory.appending(path: "\(id.rawValue.uuidString).flac")
        // The connection warms while the engine starts.
        work.track { [provider = ports.provider] in await provider.warmUp() }
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
                }
            }
        }
        recording = Recording(
            id: id,
            file: file,
            startedAt: now,
            isUndecided: isChordDown,
            captureEvents: captureEvents,
            warning: work.schedule(at: now + settings.longRecordingWarning) { await self.warnLong(id) },
            announcement: work.schedule(at: now + settings.tapThreshold) { [threshold = settings.tapThreshold] in
                await self.announce(id, at: now + threshold)
            }
        )
    }

    /// The recording is still live after `Settings.longRecordingWarning`; it never stops on its own.
    private func warnLong(_ id: DictationID) {
        if recording?.id == id {
            emit(.recording(isLong: true))
        }
    }

    /// Shows the recording: the indicator appears and the start cue plays.
    private func announce(_ id: DictationID, at instant: Instant) {
        guard let current = recording, current.id == id, !current.isAnnounced else { return }
        recording?.isAnnounced = true
        recording?.clipboard = takeClipboard()
        current.announcement.cancel()
        latencies.mark(.cue, of: id, at: instant)
        emit(.recording(isLong: false))
    }

    private func takeClipboard() -> ClipboardGuard.Pending {
        Task { [clipboard, clock = ports.clock] in (snapshot: await clipboard.snapshot(), readyAt: clock.now) }
    }

    /// Clears the live recording and its timers.
    private func endRecording(_ current: Recording) {
        recording = nil
        current.warning.cancel()
        current.announcement.cancel()
    }

    private func stop(_ current: Recording, at now: Instant) {
        endRecording(current)
        latencies.mark(.stop, of: current.id, at: now)
        inFlight.insert(current.id)
        emit(.transcribing)
        let ended = Task { await self.endCapture(of: current) }
        captureEnd = ended
        let clipboard = current.clipboard ?? takeClipboard()
        work.track { await self.finish(current, audio: await ended.value, clipboard: clipboard) }
    }

    /// Stops after the buffer that holds the stop moment; on an error, sends what was written.
    private func endCapture(of current: Recording) async -> RecordedAudio {
        let audio: RecordedAudio
        do {
            audio = try await ports.audio.endCapture()
        } catch {
            Log.pipeline.error("Capture did not end cleanly, sending what was written: \(error)")
            audio = RecordedAudio(file: current.file, duration: .zero)
        }
        await current.captureEvents.value
        return audio
    }

    private func cancel(_ current: Recording) async {
        endRecording(current)
        let audio = await ports.audio.cancelCapture()
        await current.captureEvents.value
        await keep(current, audio: audio, as: .cancelled)
        emit(inFlight.isEmpty ? .idle : .transcribing)
        resumeQuietWaiters()
    }

    /// Saves a recording that is not transcribed now, with its audio and latency marks.
    private func keep(_ current: Recording, audio: RecordedAudio?, as status: DictationRecord.Status) async {
        let latency = latencies.take(current.id).log
        guard let audio else { return }
        let record = DictationRecord(
            id: current.id, createdAt: ports.clock.date, audio: audio, transcript: nil, status: status, latency: latency
        )
        await ports.store.saveOrLog(record)
    }

    /// Esc: the mic goes off, the file stays open, and Undo can resume until the window closes.
    private func pause(_ current: Recording, at now: Instant) async {
        recording = nil
        current.announcement.cancel()
        latencies.mark(.cancel, of: current.id, at: now)
        let window = work.schedule(at: now + settings.undoWindow) { [id = current.id] in
            await self.closeUndoWindow(of: id)
        }
        paused = UndoWindow(item: current, timer: window)
        emit(.undoable)
        await ports.audio.pauseCapture()
    }

    private func resume(at now: Instant) async {
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
        recording = resumed
        latencies.mark(.resume, of: resumed.id, at: now)
        emit(.recording(isLong: now - resumed.startedAt >= settings.longRecordingWarning))
    }

    /// No Undo in time: the cancel is final and the audio stays in history.
    private func closeUndoWindow(of id: DictationID) async {
        guard let current = paused, current.item.id == id else { return }
        paused = nil
        await cancel(current.item)
    }

    /// Drops a recording that turned out to be part of another app's shortcut: no row, no file, no cue.
    private func discard(_ current: Recording) async {
        endRecording(current)
        await ports.audio.discardCapture()
        await current.captureEvents.value
        _ = latencies.take(current.id)
        emit(inFlight.isEmpty ? .idle : .transcribing)
        resumeQuietWaiters()
    }
}

// MARK: - Transcription and paste

extension DictationPipeline {
    private func finish(_ current: Recording, audio: RecordedAudio, clipboard: ClipboardGuard.Pending) async {
        let (keyDown, latency) = latencies.take(current.id)
        let job = TranscriptDelivery.Job(
            id: current.id, audio: audio, createdAt: ports.clock.date, keyDown: keyDown, latency: latency,
            clipboard: clipboard, settings: settings, mode: current.isCleanupSeen ? .cleanup : .transcript)
        let outcome = await delivery.deliver(job) { await self.waitForChordRelease() }
        if let write = outcome.restore {
            work.schedule(at: ports.clock.now + settings.restoreDelay) { await self.clipboard.restore(after: write) }
        }
        finishDictation(current.id, showing: outcome.showing ?? .outcome(of: outcome.record))
    }

    /// A Cmd-V posted while the chord is held reaches the app as Ctrl+Opt+Cmd+V.
    private func waitForChordRelease() async {
        guard isChordDown else { return }
        await withCheckedContinuation { releaseWaiters.add($0) }
    }

    // MARK: Helpers

    private func emit(_ newState: DictationState) {
        guard newState != state else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    /// A recording in progress keeps the indicator on recording; other transcriptions keep it on transcribing.
    private func finishDictation(_ id: DictationID, showing outcome: DictationState) {
        inFlight.remove(id)
        defer { resumeQuietWaiters() }
        // A live recording or an open Undo window keeps the indicator; the outcome would hide it.
        guard recording == nil, paused == nil else { return }
        emit(outcome == .idle && !inFlight.isEmpty ? .transcribing : outcome)
    }

    /// No recording, no Undo window and no transcription in flight.
    private var isQuiet: Bool {
        recording == nil && paused == nil && inFlight.isEmpty
    }

    private func waitUntilQuiet() async {
        guard !isQuiet else { return }
        await withCheckedContinuation { quietWaiters.add($0) }
    }

    private func resumeQuietWaiters() {
        if isQuiet {
            quietWaiters.resumeAll()
        }
    }

    /// Waits for all work that can finish now; tests call it after each step.
    func settle() async {
        await work.settle()
    }
}
