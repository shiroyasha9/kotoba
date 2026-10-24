import AppKit
import KotobaCore
import Observation

/// The History page's rows (story 30): pages read from the store newest first, the search, the selection and the
/// actions on it. Built when the main window opens and released when it closes, so nothing runs while it is closed.
@MainActor
@Observable
final class HistoryModel {
    /// Rows per read from the store; the window never holds the whole history.
    static let pageSize = 200

    /// What the window does with the history. The snapshot run passes none and sets the rows itself.
    struct Source {
        /// The rows after `after` whose text or app contains the search, newest first.
        var page:
            @MainActor (_ search: String, _ after: DictationRecord?, _ limit: Int) async throws -> [DictationRecord]
        /// One row when it exists and matches the search.
        var record: @MainActor (DictationID, _ search: String) async throws -> DictationRecord?
        /// The pipeline announces what it deleted (`HistoryChange.deleted`); the window removes rows only then. False
        /// when a dictation stays: its audio file cannot be removed, or the store failed.
        var delete: @MainActor (Set<DictationID>) async -> Bool
        var retry: @MainActor (Set<DictationID>) async -> Void
        /// False when the app the owner was in did not come back, so nothing was pasted; the text is on the clipboard.
        var paste: @MainActor (String, DictationID) async -> Bool
        var copy: @MainActor (String) async -> Void
        /// Sends a row with text again, with a route's model or the current one (nil); false when it keeps its text.
        var transcribeAgain: @MainActor (DictationID, _ model: String?) async -> Bool
        /// "Transcribe Again With": the other speech models that can send now.
        var otherSpeechModels: @MainActor () -> [MenuChoice]
        /// Opens the Fix window with the row's text.
        var fix: @MainActor (DictationRecord) -> Void
    }

    /// The rows of one calendar day, for a list section.
    struct Day: Identifiable {
        /// The day's start.
        let id: Date
        let title: String
        var rows: [DictationRecord]
    }

    /// The loaded rows; `HistoryList` decides where each change puts a row.
    private(set) var list = HistoryList() {
        didSet {
            days = Self.days(of: list.rows, now: now())
            selected = list.rows.filter { selection.contains($0.id) }
            // A row that goes (a search that leaves it out, a delete) takes its audio with it: nothing else could
            // stop it.
            if let playing = playback.playing, !list.rows.contains(where: { $0.id == playing }) {
                playback.stop()
            }
        }
    }
    private(set) var days: [Day] = []
    var search = ""
    var selection: Set<DictationID> = [] {
        didSet { selected = list.rows.filter { selection.contains($0.id) } }
    }
    /// The selected rows, newest first.
    private(set) var selected: [DictationRecord] = []
    /// Rows a retry can send: no text yet, and the audio file still on disk. Read once per row when it comes in, not
    /// at each draw.
    private(set) var retryable: Set<DictationID> = []
    /// False until the first read returns, so the empty state does not flash before the rows.
    private(set) var isLoaded = false
    /// The last read of the first page failed: the page shows the failure row with Try Again.
    private(set) var isLoadFailed = false
    /// What the page reads: the search, and each Try Again after a failed read. The view reads when it changes.
    var readKey: ReadKey { ReadKey(search: search, attempt: attempt) }
    private var attempt = 0
    /// While a dictation records or is sent, Paste Again would race its paste; the rows being sent say so and cannot be
    /// deleted. Audio that plays stops, so the speakers do not reach the mic.
    var activity = PipelineActivity(isQuiet: true, inFlight: []) {
        didSet {
            if !activity.isQuiet { playback.stop() }
        }
    }
    /// A row's saved audio, played from the page (`HistoryAudio.swift`).
    let playback: AudioPlayback
    /// Paste Again could not bring back the app the owner was in: the window says so.
    var isPasteFailureShown = false
    /// The rows the Delete confirmation asks about; nil when it is not shown.
    var pendingDelete: [DictationID]?
    /// A Delete kept some dictations: the window says so.
    var isDeleteFailureShown = false
    /// Rows with text being transcribed again, as the pipeline reports them; they read "Transcribing" until the answer.
    var transcribing: Set<DictationID> { activity.transcribingAgain }
    /// A Transcribe Again kept the old text of some rows: the window says so.
    var isTranscribeFailureShown = false
    /// The row whose View Changes sheet is open.
    var changesShown: DictationRecord?
    /// The Audio section (story 31); nil in snapshots of the list alone.
    @ObservationIgnored let audio: AudioRetentionModel?

    @ObservationIgnored private let source: Source?
    /// Each read takes the next number; a result that comes back after a newer read started is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoadingMore = false
    /// The search the loaded rows match; nil until a read succeeds, and after a read fails.
    @ObservationIgnored private var loadedSearch: String?
    @ObservationIgnored let apps = InstalledApps()
    /// The day titles' "Today" and "Yesterday" count from it.
    @ObservationIgnored private let now: @MainActor () -> Date

    init(source: Source?, audio: AudioRetentionModel?) {
        self.source = source
        self.audio = audio
        playback = AudioPlayback()
        now = { .now }
    }

    /// For snapshots: fixed rows and no store, at `Snapshots.sampleNow`; `transcribing` rows show as being transcribed
    /// again, and `playing`'s audio as playing.
    init(
        rows: [DictationRecord], search: String = "", transcribing: Set<DictationID> = [], playing: DictationID? = nil,
        audio: AudioRetentionModel? = .sample()
    ) {
        source = nil
        self.audio = audio
        playback = AudioPlayback(playing: playing)
        now = { Snapshots.sampleNow }
        self.search = search
        activity = PipelineActivity(isQuiet: true, inFlight: [], transcribingAgain: transcribing)
        list.replace(with: rows, limit: rows.count + 1)
        days = Self.days(of: list.rows, now: now())
        retryable = Self.kept(rows)
        isLoaded = true
    }

    /// For snapshots: a first read that failed.
    static var loadFailed: HistoryModel {
        let model = HistoryModel(rows: [])
        model.isLoadFailed = true
        return model
    }

    struct ReadKey: Hashable {
        var search: String
        var attempt: Int
    }

    var rows: [DictationRecord] { list.rows }
    var isComplete: Bool { list.isComplete }

    // MARK: Reading

    /// The page appeared, or the search changed. The model follows each history write while the window is open
    /// (`apply`), so a page shown again with the same search keeps its rows and pages and reads nothing.
    func show() async {
        guard !isLoaded || search != loadedSearch else { return }
        await reload()
    }

    /// Try Again after a failed read: the page reads the first page again.
    func tryAgain() {
        attempt += 1
    }

    /// Reads the first page again for a new search.
    func reload() async {
        guard let source else { return }
        generation += 1
        let current = generation
        let limit = Self.pageSize
        do {
            let page = try await source.page(search, nil, limit)
            guard current == generation else { return }
            list.replace(with: page, limit: limit)
            retryable = Self.kept(list.rows)
            loadedSearch = search
            isLoadFailed = false
        } catch {
            guard current == generation else { return }
            Log.app.error("Cannot read the history: \(error)")
            loadedSearch = nil
            isLoadFailed = true
        }
        // The failure state hides the rows, so the actions must not act on a selection the owner cannot see.
        selection.formIntersection(isLoadFailed ? [] : rows.map(\.id))
        isLoaded = true
    }

    /// The next page, when the list shows its last row.
    func loadMore() async {
        guard let source, !isComplete, !isLoadingMore, let last = rows.last else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let current = generation
        do {
            let page = try await source.page(search, last, Self.pageSize)
            guard current == generation else { return }
            list.append(page, limit: Self.pageSize)
            retryable.formUnion(Self.kept(page))
        } catch {
            Log.app.error("Cannot read more history: \(error)")
        }
    }

    /// One history write while the window is open: reads only the row it names, drops the deleted rows, or marks the
    /// rows whose audio retention deleted.
    func apply(_ change: HistoryChange) async {
        switch change {
        case .saved(let id, _): await refresh(id)
        case .deleted(let ids):
            if let playing = playback.playing, ids.contains(playing) { playback.stop() }
            list.remove(ids)
            retryable.subtract(ids)
            selection.subtract(ids)
        case .audioDeleted(let ids):
            list.markAudioDeleted(ids)
            retryable.subtract(ids)
        case .usageAdded:
            // The ledger only: no row changed.
            break
        }
    }

    private func refresh(_ id: DictationID) async {
        guard let source else { return }
        let current = generation
        let record: DictationRecord?
        do {
            record = try await source.record(id, search)
        } catch {
            Log.app.error("Cannot read dictation \(id.rawValue): \(error)")
            return
        }
        // A read that started later saw this write too.
        guard current == generation else { return }
        list.update(id, to: record)
        retryable.remove(id)
        retryable.formUnion(Self.kept(record.map { [$0] } ?? []))
    }

    /// The ids of `records` a retry can send: retryable, with the audio file still on disk.
    static func kept(_ records: [DictationRecord]) -> Set<DictationID> {
        Set(
            records.lazy.filter { $0.isRetryable && FileManager.default.fileExists(atPath: $0.audio.file.path) }.map(
                \.id))
    }

    // MARK: Selection and actions

    /// The latest text of each row (rewritten when Rewrite ran), oldest first, a blank line between: the order they
    /// were spoken. `raw` takes the transcript before cleanup, which is the delivered text of a dictation without
    /// cleanup.
    static func text(of records: [DictationRecord], raw: Bool = false) -> String? {
        let texts = records.reversed().compactMap { raw ? $0.transcript : $0.latestText }.filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    static func hasText(_ records: [DictationRecord]) -> Bool {
        records.contains(where: \.hasText)
    }

    func copy(_ records: [DictationRecord], raw: Bool = false) {
        guard let source, let text = Self.text(of: records, raw: raw) else { return }
        Task { await source.copy(text) }
    }

    /// One row with text: the Fix window learns from one dictation's edit.
    func canFix(_ records: [DictationRecord]) -> Bool {
        records.count == 1 && records.first?.hasText == true
    }

    func fix(_ records: [DictationRecord]) {
        guard let source, canFix(records), let record = records.first else { return }
        source.fix(record)
    }

    /// One row with a cleaned or rewritten text: View Changes compares it with the text before.
    func canViewChanges(_ records: [DictationRecord]) -> Bool {
        records.count == 1 && records.first.map { !ChangesView.Comparison.all(of: $0).isEmpty } == true
    }

    func viewChanges(_ records: [DictationRecord]) {
        guard canViewChanges(records) else { return }
        changesShown = records.first
    }

    /// One row only: two texts pasted in one go would read as one dictation.
    func canPasteAgain(_ records: [DictationRecord]) -> Bool {
        activity.isQuiet && records.count == 1 && records.first?.hasText == true
    }

    func pasteAgain(_ records: [DictationRecord]) {
        guard let source, canPasteAgain(records), let record = records.first, let text = record.latestText
        else { return }
        Task {
            if await !source.paste(text, record.id) {
                isPasteFailureShown = true
            }
        }
    }

    func canRetry(_ records: [DictationRecord]) -> Bool {
        records.contains { retryable.contains($0.id) }
    }

    func retry(_ records: [DictationRecord]) {
        guard let source else { return }
        let ids = Set(records.map(\.id)).intersection(retryable)
        guard !ids.isEmpty else { return }
        Task { await source.retry(ids) }
    }

    /// The one selected row with text whose audio is kept and that is not being sent; nil for none or several, so a
    /// click never sends many paid requests.
    func againRecord(_ records: [DictationRecord]) -> DictationRecord? {
        guard let record = audioRecord(records), record.hasText, !transcribing.contains(record.id) else { return nil }
        return record
    }

    /// While no dictation records or is sent: the request would slow a live one.
    func canTranscribeAgain(_ records: [DictationRecord]) -> Bool {
        activity.isQuiet && againRecord(records) != nil
    }

    /// Sends the row again with `model` (a route's) or the current speech model (nil).
    func transcribeAgain(_ records: [DictationRecord], model: String? = nil) {
        guard let source, canTranscribeAgain(records), let id = againRecord(records)?.id else { return }
        // Weak: a closed window drops the model, and the request still ends in the pipeline, which reports the row in
        // its activity meanwhile.
        Task { [weak self] in
            if await !source.transcribeAgain(id, model) { self?.isTranscribeFailureShown = true }
        }
    }

    /// The other speech models that can send now, for "Transcribe Again With".
    var otherSpeechModels: [MenuChoice] {
        source?.otherSpeechModels() ?? []
    }

    /// A dictation in flight or being transcribed again is not deleted: its own save would bring the row back (the
    /// pipeline keeps it too), or find it gone.
    func canDelete(_ records: [DictationRecord]) -> Bool {
        !records.isEmpty && !records.contains { activity.inFlight.contains($0.id) || transcribing.contains($0.id) }
    }

    func askToDelete(_ records: [DictationRecord]) {
        guard canDelete(records) else { return }
        pendingDelete = records.map(\.id)
    }

    func delete(_ ids: [DictationID]) {
        guard let source else { return }
        Task {
            if await !source.delete(Set(ids)) {
                isDeleteFailureShown = true
            }
        }
    }
}
