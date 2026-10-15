import AppKit
import KotobaCore
import Observation

/// The History window's rows (story 30): pages read from the store newest first, the search, the selection and the
/// actions on it. Built when the window opens and released when it closes, so nothing runs while it is closed.
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
        /// The pipeline announces what it deleted (`HistoryChange.deleted`); the window removes rows only then.
        var delete: @MainActor (Set<DictationID>) async -> Void
        var retry: @MainActor (Set<DictationID>) async -> Void
        var paste: @MainActor (String, DictationID) async -> Void
        var copy: @MainActor (String) async -> Void
    }

    /// The rows of one calendar day, for a list section.
    struct Day: Identifiable {
        /// The day's start.
        let id: Date
        let title: String
        var rows: [DictationRecord]
    }

    private(set) var rows: [DictationRecord] = [] {
        didSet { rowsChanged() }
    }
    private(set) var days: [Day] = []
    var search = ""
    var selection: Set<DictationID> = [] {
        didSet { selected = rows.filter { selection.contains($0.id) } }
    }
    /// The selected rows, newest first.
    private(set) var selected: [DictationRecord] = []
    /// Rows a retry can send: no text yet, and the audio file still on disk. Read once per row when its page loads,
    /// not at each draw.
    private(set) var retryable: Set<DictationID> = []
    /// False until the first read returns, so the empty state does not flash before the rows.
    private(set) var isLoaded = false
    /// The store has no rows after the last one shown.
    private(set) var isComplete = false
    private(set) var loadError: String?
    /// A dictation is recording or being sent: Paste Again would race its paste, so it waits until the end.
    var isDictating = false
    /// The rows the Delete confirmation asks about; nil when it is not shown.
    var pendingDelete: [DictationID]?

    @ObservationIgnored private let source: Source?
    /// Each read takes the next number; a result that comes back after a newer read started is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoadingMore = false
    /// Rows deleted while the window is open: a read that started before the delete must not show them again.
    @ObservationIgnored private var deleted: Set<DictationID> = []
    @ObservationIgnored private var icons: [String: NSImage?] = [:]

    init(source: Source?) {
        self.source = source
    }

    /// For snapshots: fixed rows and no store.
    init(rows: [DictationRecord], search: String = "") {
        source = nil
        self.search = search
        self.rows = rows
        rowsChanged()
        isLoaded = true
        isComplete = true
    }

    // MARK: Reading

    /// Reads the first page again for a new search, or, with `keepingCount`, as many rows as are shown (a dictation
    /// finished or changed while the window is open).
    func reload(keepingCount: Bool = false) async {
        guard let source else { return }
        generation += 1
        let current = generation
        let limit = keepingCount ? max(Self.pageSize, rows.count) : Self.pageSize
        do {
            let page = try await source.page(search, nil, limit)
            guard current == generation else { return }
            rows = page.filter { !deleted.contains($0.id) }
            isComplete = page.count < limit
            loadError = nil
        } catch {
            guard current == generation else { return }
            Log.app.error("Cannot read the history: \(error)")
            loadError = "kotoba can’t read your history. Quit and reopen kotoba."
        }
        selection.formIntersection(rows.map(\.id))
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
            rows += page.filter { !deleted.contains($0.id) }
            isComplete = page.count < Self.pageSize
        } catch {
            Log.app.error("Cannot read more history: \(error)")
        }
    }

    /// One history write while the window is open: reads only the row it names, or drops the deleted rows. A prune
    /// does not name its rows, so the shown rows are read again.
    func apply(_ change: HistoryChange) async {
        switch change {
        case .saved(let id): await refresh(id)
        case .deleted(let ids):
            deleted.formUnion(ids)
            rows.removeAll { ids.contains($0.id) }
            selection.subtract(ids)
        case .pruned: await reload(keepingCount: true)
        }
    }

    /// Puts the row in its place, newest first, or takes it out when it no longer matches the search. A row older than
    /// the last one shown waits for its page.
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
        guard current == generation, !deleted.contains(id) else { return }
        var updated = rows
        updated.removeAll { $0.id == id }
        if let record, isComplete || updated.last.map({ Self.isNewer(record, than: $0) }) ?? true {
            updated.insert(record, at: updated.firstIndex { Self.isNewer(record, than: $0) } ?? updated.endIndex)
        }
        rows = updated
    }

    /// The store's order: `created_at`, then the id's text, both descending.
    private static func isNewer(_ record: DictationRecord, than other: DictationRecord) -> Bool {
        record.createdAt != other.createdAt
            ? record.createdAt > other.createdAt : record.id.rawValue.uuidString > other.id.rawValue.uuidString
    }

    // MARK: Selection and actions

    /// The text of each row, oldest first, a blank line between: the order they were spoken. `raw` takes the
    /// transcript before cleanup, which is the delivered text of a dictation without cleanup.
    static func text(of records: [DictationRecord], raw: Bool = false) -> String? {
        let texts = records.reversed().compactMap { raw ? $0.transcript : $0.deliveredText }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    static func hasText(_ records: [DictationRecord]) -> Bool {
        records.contains { $0.deliveredText != nil }
    }

    func copy(_ records: [DictationRecord], raw: Bool = false) {
        guard let source, let text = Self.text(of: records, raw: raw) else { return }
        Task { await source.copy(text) }
    }

    /// One row only: two texts pasted in one go would read as one dictation.
    func canPasteAgain(_ records: [DictationRecord]) -> Bool {
        !isDictating && records.count == 1 && records.first?.deliveredText != nil
    }

    func pasteAgain(_ records: [DictationRecord]) {
        guard let source, canPasteAgain(records), let record = records.first, let text = record.deliveredText
        else { return }
        Task { await source.paste(text, record.id) }
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

    /// A row the pipeline may still write (a dictation in flight saves it again) is not deleted while one runs.
    func canDelete(_ records: [DictationRecord]) -> Bool {
        !records.isEmpty && !(isDictating && records.contains { $0.status == .pending })
    }

    func askToDelete(_ records: [DictationRecord]) {
        guard canDelete(records) else { return }
        pendingDelete = records.map(\.id)
    }

    func delete(_ ids: [DictationID]) {
        guard let source else { return }
        Task { await source.delete(Set(ids)) }
    }

    // MARK: Display

    /// The app's icon from its bundle, read once per app while the window is open; nil when it is not installed.
    func icon(for app: DictationApp?) -> NSImage? {
        guard let app else { return nil }
        if let icon = icons[app.bundleID] { return icon }
        let icon = InstalledApp.icon(of: app.bundleID)
        icons[app.bundleID] = icon
        return icon
    }

    private func rowsChanged() {
        days = Self.days(of: rows)
        selected = rows.filter { selection.contains($0.id) }
        retryable = Set(
            rows.lazy.filter { $0.isRetryable && FileManager.default.fileExists(atPath: $0.audio.file.path) }.map(\.id))
    }

    private static func days(of rows: [DictationRecord]) -> [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        for row in rows {
            let start = calendar.startOfDay(for: row.createdAt)
            if days.last?.id == start {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(Day(id: start, title: title(of: start, calendar: calendar), rows: [row]))
            }
        }
        return days
    }

    /// "Today", "Yesterday", "Monday, 12 October", with the year when it is not this year.
    private static func title(of day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        return calendar.isDate(day, equalTo: .now, toGranularity: .year)
            ? day.formatted(style) : day.formatted(style.year())
    }
}
