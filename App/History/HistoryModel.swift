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
        /// False when the app the owner was in did not come back, so nothing was pasted; the text is on the clipboard.
        var paste: @MainActor (String, DictationID) async -> Bool
        var copy: @MainActor (String) async -> Void
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
            days = Self.days(of: list.rows)
            selected = list.rows.filter { selection.contains($0.id) }
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
    private(set) var loadError: String?
    /// While a dictation records or is sent, Paste Again would race its paste; the rows being sent say so and cannot be
    /// deleted.
    var activity = PipelineActivity(isQuiet: true, inFlight: [])
    /// Each Edit > Find… adds one; the view focuses its search field.
    var findRequests = 0
    /// Paste Again could not bring back the app the owner was in: the window says so.
    var isPasteFailureShown = false
    /// The rows the Delete confirmation asks about; nil when it is not shown.
    var pendingDelete: [DictationID]?

    @ObservationIgnored private let source: Source?
    /// Each read takes the next number; a result that comes back after a newer read started is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoadingMore = false
    @ObservationIgnored private var icons: [String: NSImage?] = [:]

    init(source: Source?) {
        self.source = source
    }

    /// For snapshots: fixed rows and no store.
    init(rows: [DictationRecord], search: String = "") {
        source = nil
        self.search = search
        list.replace(with: rows, limit: rows.count + 1)
        days = Self.days(of: list.rows)
        retryable = Self.kept(rows)
        isLoaded = true
    }

    var rows: [DictationRecord] { list.rows }
    var isComplete: Bool { list.isComplete }

    // MARK: Reading

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
        case .saved(let id): await refresh(id)
        case .deleted(let ids):
            list.remove(ids)
            retryable.subtract(ids)
            selection.subtract(ids)
        case .audioDeleted(let ids):
            list.markAudioDeleted(ids)
            retryable.subtract(ids)
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
    private static func kept(_ records: [DictationRecord]) -> Set<DictationID> {
        Set(
            records.lazy.filter { $0.isRetryable && FileManager.default.fileExists(atPath: $0.audio.file.path) }.map(
                \.id))
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
        activity.isQuiet && records.count == 1 && records.first?.deliveredText != nil
    }

    func pasteAgain(_ records: [DictationRecord]) {
        guard let source, canPasteAgain(records), let record = records.first, let text = record.deliveredText
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

    /// A dictation in flight is not deleted: its own save would bring the row back (the pipeline keeps it too).
    func canDelete(_ records: [DictationRecord]) -> Bool {
        !records.isEmpty && !records.contains { activity.inFlight.contains($0.id) }
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
