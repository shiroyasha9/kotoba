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
    /// Each write to the store, in order: the menu reads its counts and lists again, an open History pane its rows.
    public nonisolated let historyChanges: AsyncStream<HistoryChange>
    /// The keyterms of each dictation that got its text, live or retried, after its paste.
    public nonisolated let termReports: AsyncStream<TermReport>

    let ports: Ports
    var settings: Settings
    /// Every paste goes through it (`ClipboardPaste.run(_:gate:)`, the pipeline as the gate).
    let paste: ClipboardPaste
    /// The retry queue, and the Recovered list the menu shows.
    public nonisolated let retries: RetryQueue
    let delivery: TranscriptDelivery
    private let stateContinuation: AsyncStream<DictationState>.Continuation
    private let activityContinuation: AsyncStream<PipelineActivity>.Continuation
    let termReportContinuation: AsyncStream<TermReport>.Continuation
    private(set) var lastActivity = PipelineActivity(isQuiet: true, inFlight: [])
    var recording: Recording?
    /// Set while Esc's Undo window is open.
    var paused: UndoWindow<Recording>?
    var isChordDown = false
    /// Counts chord presses: the number of the press that is down now, or of the last one.
    var press = 0
    /// Why the owner is away (`PipelineAway.swift`); while any is open, nothing pastes.
    var absences: Set<Absence> = []
    /// The release of the last push-to-talk tap, if it was dropped and no chord was pressed since: a push-to-talk press
    /// soon after it is a double tap (`Settings.doubleTapGap`).
    var droppedTapEnd: Instant?
    /// Pastes waiting for the chord to be released.
    var releaseWaiters = Waiters()
    var latencies = LatencyRecorder()
    /// Dictations being transcribed in this process; a retry skips them.
    var inFlight: Set<DictationID> = []
    /// Dictations with text that History's "Transcribe Again" is sending (`PipelineTranscribeAgain.swift`).
    var transcribingAgain: Set<DictationID> = []
    /// The dictations in flight whose transcript is with the cleaner.
    var cleaning: Set<DictationID> = []
    /// On while Polish waits for its answer and pastes (`PipelinePolish.swift`).
    var isPolishing = false
    /// The last Polish that saved its text, and the polished text it replaced: Undo puts that one back.
    var lastPolish: (id: DictationID, earlier: String?)?
    /// The last text kotoba pasted and where the owner was then; nil after a Return submitted it. Polish deletes it by
    /// Backspace only while nothing changed (`PolishPlacement`).
    var lastPaste: LastPaste?
    /// Dictations stopped with Return, or given a Return just after the stop: Return follows their paste.
    var submitRequests: Set<DictationID> = []
    /// The last dictation stopped, for a Return the tap swallowed just after the stop.
    var lastStopped: DictationID?
    /// A route primer is on its way; a second one is never sent beside it.
    var isPrimerInFlight = false
    /// When the last route primer was sent: the route stays warm for about 45 s after it.
    var primedAt: Instant?
    /// The dictation whose cold route gets the large primer once its silent one answered.
    var largePrimerDue: DictationID?
    /// When the route last answered: it wraps the provider port, so every request reports to it.
    let warmth: RouteWarmth
    let work: PendingWork
    /// The last stop's capture end; a new capture starts only after it, so the two never overlap.
    var captureEnd: Task<RecordedAudio?, Never>?
    var audioDeletion = AudioDeletion()
    /// Retries waiting until no dictation is live.
    private(set) var quietWaiters = Waiters()
    /// The run the route asked for with its wait (`scheduleRetry(after:)`); a newer wait replaces it.
    var retryTimer: Task<Void, Never>?
    /// Quit, waiting for the dictations in flight (`shutdown`).
    var quitWaiters = Waiters()
    /// Quit began: nothing new is sent, recorded or pasted (`shutdown`).
    var isQuitting = false
    /// Quit waits for the retry send on its way (`RetryQueue.sendEnded`), as for a live dictation.
    var isRetrySending = false
    /// Test seam: sound events taken so far (levels, a lost mic, the no-sound deadline). The capture stream gives
    /// tests no other sign that the pipeline took an event, so they wait for this count before they check the state.
    var handledSoundEvents = 0

    public init(ports: Ports, settings: Settings) {
        // Not coalesced: each change names its rows. A dictation makes two or three.
        let (historyChanges, changes) = AsyncStream.makeStream(of: HistoryChange.self)
        self.historyChanges = historyChanges
        var ports = ports
        ports.store = AnnouncingStore(base: ports.store, changes: changes)
        let warmth = RouteWarmth(base: ports.provider, clock: ports.clock)
        ports.provider = warmth
        self.warmth = warmth
        self.ports = ports
        self.settings = settings
        work = PendingWork(clock: ports.clock)
        let paste = ClipboardPaste(
            pasteboard: ports.pasteboard, paster: ports.paster, frontApp: ports.frontApp,
            place: ports.polisher == nil ? nil : ports.inputMark, readWait: settings.readWait, work: work,
            clock: ports.clock)
        self.paste = paste
        let steps = TranscriptionSteps(
            provider: ports.provider, cleaner: ports.cleaner, clock: ports.clock, store: ports.store, work: work)
        delivery = TranscriptDelivery(steps: steps, store: ports.store, clock: ports.clock, paste: paste)
        retries = RetryQueue(steps: steps, store: ports.store, clock: ports.clock, paste: paste)
        (states, stateContinuation) = AsyncStream.makeStream(of: DictationState.self)
        (termReports, termReportContinuation) = AsyncStream.makeStream(of: TermReport.self)
        (activity, activityContinuation) = AsyncStream.makeStream(
            of: PipelineActivity.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// `instant` is when the key event happened (the tap's time); nil means now. Tap vs hold and
    /// the latency marks use it, so a slow step before this call does not change them.
    public func handle(_ event: HotkeyEvent, at instant: ContinuousClock.Instant? = nil) async {
        guard !isQuitting else { return }
        let now = instant ?? ports.clock.now
        switch event {
        case .chordDown(let gesture): await chordDown(gesture, at: now)
        case .gestureChanged(let gesture): gestureChanged(gesture)
        case .cleanupModifier: cleanupModifier()
        case .chordUp: await chordUp(at: now)
        case .escape:
            if let recording {
                await pause(recording, at: now)
            }
        case .chordInterrupted: await chordInterrupted()
        case .submit: requestSubmit(at: now)
        // Tracked, so the next key event does not wait for the history read.
        case .pasteLast, .copyLast, .polishLast: work.track { await self.lastDictation(event) }
        }
    }

    /// The Paste Last, Copy Last and Polish Last chords.
    private func lastDictation(_ event: HotkeyEvent) async {
        switch event {
        case .pasteLast: await pasteLast()
        case .copyLast: await copyLast()
        case .polishLast: await polishLast()
        default: break
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

    /// The History pane's Delete. A dictation in flight is kept: its own save would bring the row back. False when a
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

    /// The owner edited the dictionary: the next request, paste and retry use it.
    public func updateDictionary(_ dictionary: PersonalDictionary) async {
        settings.dictionary = dictionary
    }

    /// The use counts or pins changed: the next request ranks its keyterms with them.
    public func updateTermUse(_ use: [String: TermUse]) async {
        settings.termUse = use
    }

    /// The owner changed the per-app modes: the next key-down and stop use them.
    public func updateModes(_ modes: ModeRules) async {
        settings.modes = modes
    }

    /// The owner turned the submit phrase on or off: the next transcript uses it.
    public func updateSubmitPhrase(isOn: Bool) async {
        settings.isSubmitPhraseOn = isOn
    }

    /// The owner turned spoken line breaks on or off: the next transcript uses it.
    public func updateLineBreakPhrase(isOn: Bool) async {
        settings.isLineBreakPhraseOn = isOn
    }

    /// Quit: a live recording is saved `.pending` (transcribed at the next launch, into Recovered),
    /// and a recording in its Undo window is saved `.cancelled`. Nothing is lost. A dictation being sent gets up to
    /// `quitWait` for its answer, so its billed text is saved and the next launch does not send it again; one that
    /// takes longer stays `.pending`; a retry being sent gets the same wait, and a paste that went out gets its restore.
    /// From the start nothing new is sent (a send now could be billed now and again at the next launch), recorded or
    /// pasted: the paste of an answer that comes during the wait would return before its restore.
    public func shutdown() async {
        isQuitting = true
        retryTimer?.cancel()
        retryTimer = nil
        if await retries.stop() {
            isRetrySending = true
            // Tracked, so the quit wait below bounds it: a send on its way can take long.
            work.track {
                await self.retries.sendEnded()
                await self.retrySendEnded()
            }
        }
        // A paste waiting for a chord release saves its text instead.
        releaseWaiters.resumeAll()
        if let current = paused {
            paused = nil
            current.timer.cancel()
            await cancel(current.item)
        }
        if let current = recording {
            endRecording(current)
            await keep(current, audio: await endCapture(of: current), as: .pending)
        }
        let deadline = ports.clock.now + Self.quitWait
        if !isSendDone {
            let bound = work.schedule(at: deadline) { await self.endQuitWait() }
            await withCheckedContinuation { quitWaiters.add($0) }
            bound.cancel()
        }
        // A paste that went out before quit began gets its restore, so the owner's clipboard comes back.
        await paste.waitUntilRestored(by: deadline)
    }

    /// No live dictation and no retry is being sent.
    var isSendDone: Bool { inFlight.isEmpty && !isRetrySending }

    private func retrySendEnded() {
        isRetrySending = false
        if isSendDone { quitWaiters.resumeAll() }
    }

    /// Most dictations get their answer in about a second; quit must not hang on a slow route.
    static let quitWait = Duration.seconds(3)

    private func endQuitWait() {
        quitWaiters.resumeAll()
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
        if isSendDone { quitWaiters.resumeAll() }
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
    func announceActivity() {
        let now = PipelineActivity(isQuiet: isQuiet, inFlight: inFlight, transcribingAgain: transcribingAgain)
        guard now != lastActivity else { return }
        lastActivity = now
        activityContinuation.yield(now)
    }

    /// No recording, no Undo window, no transcription in flight and no Polish: "Paste Again" can paste.
    public var isQuiet: Bool {
        recording == nil && paused == nil && inFlight.isEmpty && !isPolishing
    }

    func waitUntilQuiet() async {
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
