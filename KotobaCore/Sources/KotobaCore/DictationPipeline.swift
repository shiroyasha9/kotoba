import Foundation

/// The dictation pipeline core. Hotkey events go in; every effect goes out through a port.
///
/// Call `handle(_:at:)` from one serial consumer, so events keep their order.
public actor DictationPipeline {
    typealias Instant = ContinuousClock.Instant

    public private(set) var state: DictationState = .idle
    /// Every state change, for the indicator and sound cues.
    public nonisolated let states: AsyncStream<DictationState>
    /// What is live after each change: whether "Paste Again" can paste, and which dictations are being sent. Only
    /// the newest value is kept.
    public nonisolated let activity: AsyncStream<PipelineActivity>
    /// Each write to the store, in order: the menu reads its counts and lists again, an open History window its rows.
    public nonisolated let historyChanges: AsyncStream<HistoryChange>

    let ports: Ports
    var settings: Settings
    let clipboard: ClipboardGuard
    /// The retry queue, and the Recovered list the menu shows.
    public nonisolated let retries: RetryQueue
    let delivery: TranscriptDelivery
    private let stateContinuation: AsyncStream<DictationState>.Continuation
    private let activityContinuation: AsyncStream<PipelineActivity>.Continuation
    private var lastActivity = PipelineActivity(isQuiet: true, inFlight: [])
    var recording: Recording?
    /// Set while Esc's Undo window is open.
    var paused: UndoWindow<Recording>?
    var isChordDown = false
    /// Pastes waiting for the chord to be released.
    var releaseWaiters = Waiters()
    var latencies = LatencyRecorder()
    /// Dictations being transcribed in this process; a retry skips them.
    var inFlight: Set<DictationID> = []
    /// The dictations in flight whose transcript is with the cleaner.
    var cleaning: Set<DictationID> = []
    /// Dictations stopped with Return, or given a Return just after the stop: Return follows their paste.
    var submitRequests: Set<DictationID> = []
    /// The last dictation stopped, for a Return the tap swallowed just after the stop.
    var lastStopped: DictationID?
    let work: PendingWork
    /// The last stop's capture end; a new capture starts only after it, so the two never overlap.
    var captureEnd: Task<RecordedAudio, Never>?
    var audioDeletion = AudioDeletion()
    /// Retries waiting until no dictation is live.
    private var quietWaiters = Waiters()
    /// Test seam: sound events taken so far (levels, a lost mic, the no-sound deadline). The capture stream gives
    /// tests no other sign that the pipeline took an event, so they wait for this count before they check the state.
    var handledSoundEvents = 0

    public init(ports: Ports, settings: Settings) {
        // Not coalesced: each change names its rows. A dictation makes two or three.
        let (historyChanges, changes) = AsyncStream.makeStream(of: HistoryChange.self)
        self.historyChanges = historyChanges
        var ports = ports
        ports.store = AnnouncingStore(base: ports.store, changes: changes)
        self.ports = ports
        self.settings = settings
        work = PendingWork(clock: ports.clock)
        clipboard = ClipboardGuard(pasteboard: ports.pasteboard)
        let steps = TranscriptionSteps(
            provider: ports.provider, cleaner: ports.cleaner, clock: ports.clock, store: ports.store, work: work)
        delivery = TranscriptDelivery(
            steps: steps, paster: ports.paster, store: ports.store, clock: ports.clock, clipboard: clipboard,
            frontApp: ports.frontApp)
        retries = RetryQueue(steps: steps, store: ports.store, clock: ports.clock, clipboard: clipboard)
        (states, stateContinuation) = AsyncStream.makeStream(of: DictationState.self)
        (activity, activityContinuation) = AsyncStream.makeStream(
            of: PipelineActivity.self, bufferingPolicy: .bufferingNewest(1))
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
        case .submit: requestSubmit(at: now)
        // Tracked, so the next key event does not wait for the history read.
        case .pasteLast: work.track { await self.pasteLast() }
        }
    }

    /// Resumes the recording that Esc cancelled, while the Undo window is open.
    public func undo() async {
        await resume(at: ports.clock.now)
    }

    /// The pointer on the Undo pill holds the window's time (true); leaving runs it on (false), as the pill's bar does.
    public func holdUndoWindow(_ isHeld: Bool) {
        guard let id = paused?.item.id else { return }
        paused?.hold(isHeld, at: ports.clock.now) { work.schedule(at: $0) { await self.closeUndoWindow(of: id) } }
    }

    /// Transcribes kept dictations into the Recovered list, each send after no dictation is live. With no `selection`
    /// (launch, the menu), dictations that wait for a setting are included only when the route has everything.
    public func retryPending(_ chosen: RetrySelection? = nil) async {
        let isSetUp = await ports.missingSetup() == nil
        let selection = chosen ?? (isSetUp ? .all : .exceptNeedsSetup)
        let results = await retries.run(
            selection, settings: { await self.settings }, skipping: { await self.inFlight.contains($0) },
            waitUntilQuiet: { await self.waitUntilQuiet() })
        for record in results where isQuiet {
            emit(.outcome(of: record))
        }
        // A recovered dictation is delivered too: retention's event (story 31).
        if results.contains(where: \.status.isTranscribed) { work.track { await self.deleteExpiredAudio() } }
    }

    /// The History window's Retry: sends the chosen kept dictations again, each after no dictation is live. A cancelled
    /// or rejected one joins the queue first (`DictationRecord.isRetryable`).
    public func retry(_ ids: Set<DictationID>) async {
        for id in ids {
            do {
                try await ports.store.queueForRetry(id)
            } catch {
                Log.pipeline.error("Cannot queue \(id.rawValue) for retry: \(error)")
            }
        }
        await retryPending(.only(ids))
    }

    /// The History window's Delete. A dictation in flight is kept: its own save would bring the row back. False when a
    /// dictation stays because its audio file cannot be removed, or the store failed: the window says so.
    public func delete(_ ids: Set<DictationID>) async -> Bool {
        let deletable = ids.subtracting(inFlight)
        guard !deletable.isEmpty else { return true }
        do {
            let kept = try await ports.store.delete(deletable)
            if !kept.isEmpty { Log.pipeline.error("Kept \(kept.count) dictations whose audio cannot be deleted") }
            return kept.isEmpty
        } catch {
            Log.pipeline.error("Cannot delete dictations: \(error)")
            return false
        }
    }

    /// A key, an endpoint or credit arrived: once the route has everything, the waiting dictations are sent once each.
    public func setupChanged() async {
        guard await ports.missingSetup() == nil else { return }
        await retryPending(.onlyNeedsSetup)
    }

    /// The network monitor's report. When the network returns after an outage, the failed dictations are sent again
    /// (story 22), as tracked work: this returns at once, so the monitor never waits on a retry (review B7).
    public func networkChanged(isOnline: Bool) async {
        guard await retries.recordNetwork(isOnline: isOnline) else { return }
        work.track { await self.retryPending(.exceptNeedsSetup) }
    }

    /// The owner edited the dictionary: the next request, paste and retry use it.
    public func updateDictionary(_ dictionary: PersonalDictionary) async {
        settings.dictionary = dictionary
    }

    /// The owner changed the per-app modes: the next key-down and stop use them.
    public func updateModes(_ modes: ModeRules) async {
        settings.modes = modes
    }

    /// The owner turned the submit phrase on or off: the next transcript uses it.
    public func updateSubmitPhrase(isOn: Bool) async {
        settings.isSubmitPhraseOn = isOn
    }

    /// "Paste Last Dictation", from the menu or its chord: pastes the newest delivered dictation again (`pasteAgain`).
    public func pasteLast() async {
        guard isQuiet else { return }
        do {
            guard let last = try await ports.store.lastDelivered(), let text = last.deliveredText else { return }
            await pasteAgain(text, of: last.id)
        } catch {
            Log.pipeline.error("Cannot read the last dictation: \(error)")
        }
    }

    /// Pastes `text` of dictation `id` through the clipboard guard, as a dictation does, with no Return (Paste Last,
    /// History's "Paste Again"). Only between dictations, with none in flight (its paste would replace this text on
    /// the clipboard before the app reads it); when paste is not allowed, the text stays on the clipboard.
    public func pasteAgain(_ text: String, of id: DictationID) async {
        guard isQuiet else { return }
        let write = await clipboard.writeTransient(text, over: await clipboard.snapshot())
        do {
            try await ports.paster.sendPaste()
            work.schedule(at: ports.clock.now + settings.restoreDelay) { await self.clipboard.restore(after: write) }
        } catch {
            Log.pipeline.error("Paste not allowed, the last dictation is left on the clipboard: \(error)")
            await clipboard.copy(text)
            emit(.copied(id))
        }
    }

    /// "Copy Last Dictation": leaves `text` on the clipboard, with no restore.
    public func copyAgain(_ text: String) async {
        await clipboard.copy(text)
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
        if !current.isCleanerWarm {
            recording?.isCleanerWarm = warmCleaner()
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

// MARK: - Helpers

extension DictationPipeline {
    func emit(_ newState: DictationState) {
        announceActivity()
        guard newState != state else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    /// A recording in progress keeps the indicator on recording; other dictations in flight keep it on their step.
    func finishDictation(_ id: DictationID, showing outcome: DictationState) {
        inFlight.remove(id)
        cleaning.remove(id)
        submitRequests.remove(id)
        // With another dictation in flight the state may not change, but this one is no longer sent.
        announceActivity()
        defer { resumeQuietWaiters() }
        // A live recording or an open Undo window keeps the indicator; the outcome would hide it.
        guard recording == nil, paused == nil else { return }
        emit(outcome == .idle ? inFlightState : outcome)
    }

    /// What the indicator shows when no recording or Undo window does: idle, or the step the dictations in flight
    /// wait on. Cleaning only when all of them are with the cleaner; a dictation still being transcribed comes first.
    var inFlightState: DictationState {
        if inFlight.isEmpty { return .idle }
        return inFlight.isSubset(of: cleaning) ? .cleaning : .transcribing
    }

    /// Sends the activity when it changed; every change of a recording, Undo window or dictation in flight comes with
    /// a state change or `finishDictation`.
    private func announceActivity() {
        let now = PipelineActivity(isQuiet: isQuiet, inFlight: inFlight)
        guard now != lastActivity else { return }
        lastActivity = now
        activityContinuation.yield(now)
    }

    /// No recording, no Undo window and no transcription in flight: "Paste Again" can paste.
    public var isQuiet: Bool {
        recording == nil && paused == nil && inFlight.isEmpty
    }

    private func waitUntilQuiet() async {
        guard !isQuiet else { return }
        await withCheckedContinuation { quietWaiters.add($0) }
    }

    func resumeQuietWaiters() {
        if isQuiet {
            quietWaiters.resumeAll()
        }
    }

    /// Waits for all work that can finish now; tests call it after each step.
    func settle() async {
        await work.settle()
    }
}
