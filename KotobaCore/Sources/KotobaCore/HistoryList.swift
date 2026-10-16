import Foundation

/// The History window's loaded rows, newest first in the store's order (`createdAt`, then the id's text, both
/// descending), and how each history change moves them. The window loads pages of it; a change reads one row.
public struct HistoryList: Sendable, Equatable {
    public private(set) var rows: [DictationRecord] = []
    /// The store has no rows after the last one.
    public private(set) var isComplete = false
    /// Deleted while the window is open: a read that started before the delete must not bring them back.
    private var deleted: Set<DictationID> = []

    public init() {}

    /// A first page: a new search, or the shown rows read again. A page shorter than `limit` is the end.
    public mutating func replace(with page: [DictationRecord], limit: Int) {
        rows = page.filter { !deleted.contains($0.id) }
        isComplete = page.count < limit
    }

    /// The page after the last row.
    public mutating func append(_ page: [DictationRecord], limit: Int) {
        rows += page.filter { !deleted.contains($0.id) }
        isComplete = page.count < limit
    }

    /// The row a history change names, as the store reads it now; nil when it is gone or no longer matches the search.
    /// A shown row changes in place (its time never changes). A new row goes to its place, unless it is older than the
    /// last row shown while more pages follow: its page brings it.
    public mutating func update(_ id: DictationID, to record: DictationRecord?) {
        guard !deleted.contains(id) else { return }
        if let index = rows.firstIndex(where: { $0.id == id }) {
            if let record {
                rows[index] = record
            } else {
                rows.remove(at: index)
            }
            return
        }
        guard let record, isComplete || rows.last.map({ Self.isNewer(record, than: $0) }) ?? true else { return }
        rows.insert(record, at: rows.firstIndex { Self.isNewer(record, than: $0) } ?? rows.endIndex)
    }

    /// Audio retention deleted the audio of these rows: shown ones change in place, with no read from the store.
    public mutating func markAudioDeleted(_ ids: Set<DictationID>) {
        for index in rows.indices where ids.contains(rows[index].id) {
            rows[index].isAudioDeleted = true
        }
    }

    public mutating func remove(_ ids: Set<DictationID>) {
        deleted.formUnion(ids)
        rows.removeAll { ids.contains($0.id) }
    }

    private static func isNewer(_ record: DictationRecord, than other: DictationRecord) -> Bool {
        record.createdAt != other.createdAt
            ? record.createdAt > other.createdAt : record.id.rawValue.uuidString > other.id.rawValue.uuidString
    }
}
