import Foundation

/// What is live in the pipeline: each dictation from its key-down until it ends (sent and finished, cancelled, dropped,
/// or kept at quit), the live recording and its Undo window, and the jobs beside them (Polish, Transcribe Again, a
/// retry send). One record per live dictation holds its step, its Return request and its latency marks.
///
/// The storage is private, so a change goes through a transition below, and each transition announces the activity
/// when it changed. A dictation leaves every list at once (`end`), and one place answers what is live and what quit
/// waits for (`areSendsEnded`). The pipeline actor holds the one instance.
struct LiveDictations<Recording: Identifiable> where Recording.ID == DictationID {
    typealias Instant = ContinuousClock.Instant

    /// The step of a dictation that is being sent. Not `DictationState`: the pipeline decides what the pill shows.
    enum SendStep: Equatable {
        case transcribing
        case cleaning
    }

    private struct Entry {
        let keyDown: Instant
        var latency = LatencyLog()
        /// Nil until the stop.
        var send: SendStep?
        var isSubmitAsked = false
        /// The cue played, or the recording stopped or paused: the press is a dictation, not part of a shortcut.
        var isShown = false
    }

    private var entries: [DictationID: Entry] = [:]
    private var liveRecording: Recording?
    private var undoWindow: UndoWindow<Recording>?
    /// The last dictation stopped, for a Return that the tap swallowed just after the stop.
    private var lastStopped: DictationID?
    private var jobs: Set<Job> = []
    private var quietWaiters = Waiters()
    private var sendWaiters = Waiters()
    private let announce: AsyncStream<PipelineActivity>.Continuation
    /// The activity as last announced.
    private(set) var activity = PipelineActivity(isQuiet: true, inFlight: [])

    /// `announce` gets the activity each time it changes.
    init(announce: AsyncStream<PipelineActivity>.Continuation) {
        self.announce = announce
    }

    // MARK: - The recording and its Undo window

    /// The live recording. Set it only to change that recording in place: it starts, stops, pauses and ends through the
    /// transitions below.
    var recording: Recording? {
        get { liveRecording }
        set {
            guard newValue?.id == liveRecording?.id else {
                assertionFailure("A recording starts and ends only through a transition")
                return
            }
            liveRecording = newValue
        }
    }

    /// The recording that Esc paused, in its Undo window. Set it only to change that window in place.
    var paused: UndoWindow<Recording>? {
        get { undoWindow }
        set {
            guard newValue?.item.id == undoWindow?.item.id else {
                assertionFailure("An Undo window opens and closes only through a transition")
                return
            }
            undoWindow = newValue
        }
    }

    /// A recording starts: its dictation is live from `keyDown`, the first latency mark.
    mutating func start(_ recording: Recording, keyDown: Instant) {
        entries[recording.id] = Entry(keyDown: keyDown)
        mark(.keyDown, of: recording.id, at: keyDown)
        take(recording)
    }

    /// The cue at `instant`: the press is a dictation, and the activity counts it.
    mutating func announce(_ id: DictationID, at instant: Instant) {
        entries[id]?.isShown = true
        mark(.cue, of: id, at: instant)
        changed()
    }

    /// Records `mark` as an offset from key-down and emits its signpost. No-op once the dictation ended.
    mutating func mark(_ mark: LatencyMark, of id: DictationID, at instant: Instant) {
        guard let keyDown = entries[id]?.keyDown else { return }
        entries[id]?.latency.mark(mark, at: instant, keyDown: keyDown)
    }

    /// The stop at `instant`: the recording is over, and its dictation is sent.
    mutating func stop(_ id: DictationID, at instant: Instant) {
        if liveRecording?.id == id { liveRecording = nil }
        entries[id]?.send = .transcribing
        entries[id]?.isShown = true
        lastStopped = id
        mark(.stop, of: id, at: instant)
        changed()
    }

    /// Esc at `instant`: the recording waits in its Undo window.
    mutating func pause(_ window: UndoWindow<Recording>, at instant: Instant) {
        if liveRecording?.id == window.item.id { liveRecording = nil }
        undoWindow = window
        entries[window.item.id]?.isShown = true
        mark(.cancel, of: window.item.id, at: instant)
        changed()
    }

    /// Undo: the window closes for its recording to go on. The dictation stays live while its capture resumes, until
    /// `resume` or `end`.
    mutating func unpause() -> UndoWindow<Recording>? {
        defer { undoWindow = nil }
        return undoWindow
    }

    /// The capture resumed at `instant`: the recording is live again.
    mutating func resume(_ recording: Recording, at instant: Instant) {
        guard entries[recording.id] != nil else { return }
        mark(.resume, of: recording.id, at: instant)
        take(recording)
    }

    /// Puts `recording` in the one place of the live recording. A press during a start or a resume (both wait for the
    /// audio source) can bring a second one; the one it replaces can no longer stop, so its dictation ends here.
    private mutating func take(_ recording: Recording) {
        if let replaced = liveRecording, replaced.id != recording.id {
            Log.pipeline.error("A recording started while another was live; the earlier one ends with no row")
            entries.removeValue(forKey: replaced.id)
        }
        liveRecording = recording
        changed()
    }

    // MARK: - Dictations being sent

    /// The transcript of `id` went to the cleaner.
    mutating func cleanupStarted(_ id: DictationID) {
        guard entries[id]?.send != nil else { return }
        entries[id]?.send = .cleaning
    }

    /// Return: it follows the paste of the live recording, or else of the dictation stopped last while that one is
    /// still being sent.
    mutating func askSubmit() {
        guard let id = liveRecording?.id ?? lastStopped.flatMap({ isSending($0) ? $0 : nil }) else { return }
        entries[id]?.isSubmitAsked = true
    }

    func isSubmitAsked(_ id: DictationID) -> Bool {
        entries[id]?.isSubmitAsked == true
    }

    /// The key-down instant and the marks so far, handed to the send.
    func latency(of id: DictationID) -> (keyDown: Instant, log: LatencyLog)? {
        entries[id].map { ($0.keyDown, $0.latency) }
    }

    /// The dictation is no longer live, from any step: its recording or Undo window goes too. Returns its latency
    /// marks; nil when it was not live.
    @discardableResult mutating func end(_ id: DictationID) -> LatencyLog? {
        if liveRecording?.id == id { liveRecording = nil }
        if undoWindow?.item.id == id { undoWindow = nil }
        if lastStopped == id { lastStopped = nil }
        guard let ended = entries.removeValue(forKey: id) else { return nil }
        changed()
        return ended.latency
    }

    // MARK: - Jobs and quit

    /// Work beside the dictations.
    enum Job: Hashable {
        /// Polish or its Undo.
        case polish
        /// History's Transcribe Again of a dictation with text.
        case transcribeAgain(DictationID)
        /// The retry queue's send of one kept dictation.
        case retrySend
    }

    /// Starts `job` when its rules allow it; false when they do not, and always once quit began. Polish waits for
    /// nothing live and no Transcribe Again (Polish writes the text it read before its request); Transcribe Again for
    /// its dictation not being sent or sent again, and no Polish; a retry send for nothing live.
    mutating func begin(_ job: Job) -> Bool {
        guard !isQuitting, !jobs.contains(job) else { return false }
        switch job {
        case .polish:
            guard isQuiet, !jobs.contains(where: { $0.transcribedAgain != nil }) else { return false }
        case .transcribeAgain(let id):
            guard !isSending(id), !jobs.contains(.polish) else { return false }
        case .retrySend:
            guard isQuiet else { return false }
        }
        jobs.insert(job)
        changed()
        return true
    }

    mutating func end(_ job: Job) {
        guard jobs.remove(job) != nil else { return }
        changed()
    }

    func isRunning(_ job: Job) -> Bool {
        jobs.contains(job)
    }

    /// Quit began: no job begins from here, and whatever waits for quiet goes on to see it.
    private(set) var isQuitting = false

    mutating func beginQuit() {
        isQuitting = true
        quietWaiters.resumeAll()
    }

    // MARK: - Waiters

    enum Condition {
        /// `isQuiet`, or quit began.
        case quiet
        /// `areSendsEnded`.
        case sendsEnded
    }

    /// Resumes `continuation` once `condition` holds: at once when it holds now.
    mutating func wait(until condition: Condition, _ continuation: CheckedContinuation<Void, Never>) {
        let holds =
            switch condition {
            case .quiet: isQuiet || isQuitting
            case .sendsEnded: areSendsEnded
            }
        guard !holds else { return continuation.resume() }
        self[waiters: condition].add(continuation)
    }

    /// Resumes the waiters of `condition` though it does not hold: quit's wait passed its bound.
    mutating func release(_ condition: Condition) {
        self[waiters: condition].resumeAll()
    }

    /// Test seam: how many tasks wait for `condition`.
    func waiterCount(_ condition: Condition) -> Int {
        self[waiters: condition].count
    }

    private subscript(waiters condition: Condition) -> Waiters {
        get {
            switch condition {
            case .quiet: quietWaiters
            case .sendsEnded: sendWaiters
            }
        }
        set {
            switch condition {
            case .quiet: quietWaiters = newValue
            case .sendsEnded: sendWaiters = newValue
            }
        }
    }

    /// No dictation is being sent and no retry send is on its way: quit's wait ends. A recording is no send; quit keeps
    /// it for the next launch.
    var areSendsEnded: Bool {
        !jobs.contains(.retrySend) && !entries.values.contains { $0.send != nil }
    }

    // MARK: - Answers

    /// No dictation and no Polish is live: "Paste Again" can paste and a retry can send. Transcribe Again and a retry
    /// send paste nothing, so they keep it quiet.
    var isQuiet: Bool { entries.isEmpty && !jobs.contains(.polish) }

    /// A dictation records, waits in its Undo window, resumes, or is sent.
    var isDictationLive: Bool { !entries.isEmpty }

    /// A recording or its Undo window is live: the indicator shows it, not another dictation's outcome.
    var hasRecording: Bool { liveRecording != nil || undoWindow != nil }

    func isSending(_ id: DictationID) -> Bool {
        entries[id]?.send != nil
    }

    /// The step the dictations being sent wait on: cleaning only when every one is with the cleaner. Nil when none is.
    var sendStep: SendStep? {
        var step: SendStep?
        for entry in entries.values {
            switch entry.send {
            case .transcribing: return .transcribing
            case .cleaning: step = .cleaning
            case nil: break
            }
        }
        return step
    }

    /// Wakes the waiters whose condition now holds, and announces the activity when it changed. The activity counts a
    /// recording from its cue, so a press that turns out to be a shortcut changes nothing the windows show (History
    /// stops its playback when the activity is busy).
    private mutating func changed() {
        if isQuiet { quietWaiters.resumeAll() }
        if areSendsEnded { sendWaiters.resumeAll() }
        let now = PipelineActivity(
            isQuiet: !entries.values.contains(where: \.isShown) && !jobs.contains(.polish),
            inFlight: Set(entries.compactMap { $0.value.send == nil ? nil : $0.key }),
            transcribingAgain: Set(jobs.compactMap(\.transcribedAgain)))
        guard now != activity else { return }
        activity = now
        announce.yield(now)
    }
}

extension LiveDictations.Job {
    /// The dictation of a Transcribe Again.
    var transcribedAgain: DictationID? {
        if case .transcribeAgain(let id) = self { id } else { nil }
    }
}
