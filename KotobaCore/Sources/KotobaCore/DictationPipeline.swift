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
    let termReportContinuation: AsyncStream<TermReport>.Continuation
    /// What is live: each dictation from key-down until it ends, the recording and its Undo window, Polish, Transcribe
    /// Again and a retry send. It announces `activity`.
    var live: LiveDictations<Recording>
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
    /// The last Polish that saved its text, and the polished text it replaced: Undo puts that one back.
    var lastPolish: (id: DictationID, earlier: String?)?
    /// The last text kotoba pasted and where the owner was then; nil after a Return submitted it. Polish deletes it by
    /// Backspace only while nothing changed (`PolishPlacement`).
    var lastPaste: LastPaste?
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
    /// The run the route asked for with its wait (`scheduleRetry(after:)`); a newer wait replaces it.
    var retryTimer: Task<Void, Never>?
    /// An event that reads or changes the recording or its Undo window runs (`inTurn`); the next ones wait for it.
    private(set) var isTurnTaken = false
    private var turnWaiters = Waiters()
    /// History saves of recordings whose Undo window ended, which run after the turn; quit waits for them.
    var cancelSaves = 0
    var cancelSaveWaiters = Waiters()
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
        let (activity, activityContinuation) = AsyncStream.makeStream(
            of: PipelineActivity.self, bufferingPolicy: .bufferingNewest(1))
        self.activity = activity
        live = LiveDictations(announce: activityContinuation)
    }

    /// `instant` is when the key event happened (the tap's time); nil means now. Tap vs hold and
    /// the latency marks use it, so a slow step before this call does not change them.
    public func handle(_ event: HotkeyEvent, at instant: ContinuousClock.Instant? = nil) async {
        guard !isQuitting else { return }
        let now = instant ?? ports.clock.now
        await inTurn {
            // Quit can begin while the event waits for its turn.
            guard !isQuitting else { return }
            await take(event, at: now)
        }
    }

    private func take(_ event: HotkeyEvent, at now: Instant) async {
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

    /// Runs `body` once no other event reads or changes the recording or its Undo window. A capture start and an
    /// Undo's resume wait for the audio source with no recording live in the ledger; a press, an Undo, the Undo
    /// window's end or quit in that time would begin a second capture over the first or miss the one resuming.
    /// Key events come one at a time already, so a key event waits only for an Undo click, the window's end or quit.
    /// With a `deadline` (quit) it waits no longer than that on the pipeline clock and returns false then, with `body`
    /// not run.
    @discardableResult
    func inTurn(by deadline: Instant? = nil, _ body: () async -> Void) async -> Bool {
        var bound: Task<Void, Never>?
        while isTurnTaken {
            if let deadline {
                guard ports.clock.now < deadline else {
                    bound?.cancel()
                    return false
                }
                bound = bound ?? work.schedule(at: deadline) { await self.wakeTurnWaiters() }
            }
            await withCheckedContinuation { turnWaiters.add($0) }
        }
        bound?.cancel()
        isTurnTaken = true
        await body()
        isTurnTaken = false
        turnWaiters.resumeAll()
        return true
    }

    /// A bound passed: each waiter checks its own deadline and waits on when its turn has not come.
    private func wakeTurnWaiters() {
        turnWaiters.resumeAll()
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
        let now = ports.clock.now
        await inTurn { await resume(at: now) }
    }

    /// The pointer on the Undo pill holds the window's time (true); leaving runs it on (false), as the pill's bar does.
    public func holdUndoWindow(_ isHeld: Bool) {
        guard let id = paused?.item.id else { return }
        paused?.hold(isHeld, at: ports.clock.now) { work.schedule(at: $0) { await self.closeUndoWindow(of: id) } }
    }

    /// The History pane's Delete. A dictation in flight is kept: its own save would bring the row back. False when a
    /// dictation stays because its audio file cannot be removed, or the store failed: the window says so.
    public func delete(_ ids: Set<DictationID>) async -> Bool {
        let deletable = ids.filter { !live.isSending($0) }
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
}

// MARK: - Helpers

extension DictationPipeline {
    /// The pipeline is in `phase` now: a notice shown goes.
    func emit(_ phase: DictationPhase) {
        publish(DictationState(phase))
    }

    /// Shows `notice` over the phase. A notice shows only while no recording or Undo window does, so the phase under
    /// it is `inFlightPhase`.
    func show(_ notice: DictationNotice) {
        publish(DictationState(inFlightPhase, notice: notice))
    }

    private func publish(_ newState: DictationState) {
        guard newState != state else { return }
        state = newState
        stateContinuation.yield(newState)
    }

    /// The dictation ended: a recording in progress keeps the indicator on recording; other dictations in flight keep
    /// it on their step, under `notice` when there is one. `isPasted` with no notice: the pill's check shows first
    /// (`DictationState.isPasted`), only when nothing else is on its way, so it never breaks a sweep that goes on.
    func finishDictation(_ id: DictationID, showing notice: DictationNotice?, isPasted: Bool = false) {
        dropSegments(of: id)
        live.end(id)
        // A live recording or an open Undo window keeps the indicator; the notice would hide it.
        guard !live.hasRecording else { return }
        if let notice {
            show(notice)
            return
        }
        if isPasted, inFlightPhase == .idle {
            publish(DictationState(.idle, isPasted: true))
        }
        emit(inFlightPhase)
    }

    /// The phase when no recording or Undo window shows: the step the dictations in flight wait on, else Polish, else
    /// idle.
    var inFlightPhase: DictationPhase {
        switch live.sendStep {
        case nil: live.isRunning(.polish) ? .polishing : .idle
        case .transcribing: .transcribing
        case .cleaning: .cleaning
        }
    }

    /// The live recording and its Undo window, kept in `live`; set them only to change them in place.
    var recording: Recording? {
        get { live.recording }
        set { live.recording = newValue }
    }

    var paused: UndoWindow<Recording>? {
        get { live.paused }
        set { live.paused = newValue }
    }

    /// Quit began: nothing new is sent, recorded or pasted (`shutdown`).
    var isQuitting: Bool { live.isQuitting }

    /// No recording, no Undo window, no dictation in flight and no Polish: "Paste Again" can paste.
    public var isQuiet: Bool { live.isQuiet }

    /// Returns once nothing is live, or quit began.
    func waitUntilQuiet() async {
        await withCheckedContinuation { live.wait(until: .quiet, $0) }
    }

    /// Waits for all work that can finish now; tests call it after each step.
    func settle() async {
        await work.settle()
    }

    /// Test seam: tasks parked until `condition` holds.
    func waiterCount(_ condition: LiveDictations<Recording>.Condition) -> Int {
        live.waiterCount(condition)
    }

    /// Test seam: events that wait for their turn (`inTurn`).
    var turnWaiterCount: Int { turnWaiters.count }

    /// Test seam: quits that wait for the save after an Undo window.
    var cancelSaveWaiterCount: Int { cancelSaveWaiters.count }

    /// Test seam: quits that wait for billed work.
    var billWaiterCount: Int { work.billWaiterCount }

    /// Test seam: Polish or its Undo runs.
    var isPolishing: Bool { live.isRunning(.polish) }

    /// Test seam: the activity as last announced.
    var lastActivity: PipelineActivity { live.activity }
}
