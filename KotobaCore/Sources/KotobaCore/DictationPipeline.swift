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
    let clipboard: ClipboardGuard
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
    /// Each dictation's place, read just before its ⌘V (`takePasteTarget`): several can be in flight.
    var pasteTargets: [DictationID: InputMark] = [:]
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
    private var quietWaiters = Waiters()
    /// The run the route asked for with its wait (`scheduleRetry(after:)`); a newer wait replaces it.
    var retryTimer: Task<Void, Never>?
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
        clipboard = ClipboardGuard(
            pasteboard: ports.pasteboard, paster: ports.paster, work: work, clock: ports.clock)
        let steps = TranscriptionSteps(
            provider: ports.provider, cleaner: ports.cleaner, clock: ports.clock, store: ports.store, work: work)
        delivery = TranscriptDelivery(
            steps: steps, paster: ports.paster, store: ports.store, clock: ports.clock, clipboard: clipboard,
            frontApp: ports.frontApp)
        retries = RetryQueue(steps: steps, store: ports.store, clock: ports.clock, clipboard: clipboard)
        (states, stateContinuation) = AsyncStream.makeStream(of: DictationState.self)
        (termReports, termReportContinuation) = AsyncStream.makeStream(of: TermReport.self)
        (activity, activityContinuation) = AsyncStream.makeStream(
            of: PipelineActivity.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// `instant` is when the key event happened (the tap's time); nil means now. Tap vs hold and
    /// the latency marks use it, so a slow step before this call does not change them.
    public func handle(_ event: HotkeyEvent, at instant: ContinuousClock.Instant? = nil) async {
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

    /// "Paste Last Dictation", from the menu or its chord: pastes the newest delivered dictation again (`pasteAgain`).
    public func pasteLast() async {
        guard isQuiet else { return }
        do {
            guard let last = try await ports.store.lastDelivered(), let text = last.latestText else { return }
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
        switch await pasteThroughClipboard(text, of: id) {
        case .pasted: break
        case .clipboardNotKept: emit(.clipboardNotKept(id))
        case .copied: emit(.copied(id))
        }
    }

    /// "Copy Last Dictation", from the menu or its chord: leaves the newest delivered dictation on the clipboard, with
    /// no restore, and the indicator says so. During a dictation it copies too, and the indicator keeps its state.
    public func copyLast() async {
        do {
            guard let last = try await ports.store.lastDelivered(), let text = last.latestText else { return }
            await clipboard.copy(text)
            emitIfQuiet(.copied(last.id))
        } catch {
            Log.pipeline.error("Cannot read the last dictation: \(error)")
        }
    }

    /// History's Copy: leaves `text` on the clipboard, with no restore.
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
