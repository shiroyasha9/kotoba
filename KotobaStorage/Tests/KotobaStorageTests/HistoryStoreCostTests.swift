import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The History pane on a large history: what its reads cost SQLite.
extension HistoryStoreTests {
    /// Dictations of about 30 words, one a second at each index: the History pane's large history.
    func saveSpoken(_ indices: Range<Int>, to store: HistoryStore) async throws -> [DictationID] {
        let words = "please move the standup to thursday and ask the team to review the pull request before lunch"
            .split(separator: " ")
        var ids: [DictationID] = []
        for index in indices {
            let text = (0..<30).map { words[($0 * 7 + index) % words.count] }.joined(separator: " ")
            let saved = spoken(text + " row\(index)", at: TimeInterval(index))
            try await store.save(saved)
            ids.append(saved.id)
        }
        return ids
    }

    /// The History pane's reads: a page, a deep page, a search that matches every row and one that matches
    /// none, one changed row, the menu's reads after each burst of history writes (`AppDelegate.scheduleQueueRefresh`),
    /// and the launch's check for audio with no row (`OrphanAudio`), with every file in `known` named.
    func historyReads(_ store: HistoryStore, known: [DictationID]) async throws
        -> KeyValuePairs<HistoryRead, () async throws -> Void>
    {
        let first = try await store.page(limit: 200)
        #expect(first.count == 200)
        return [
            .page: { _ = try await store.page(limit: 200) },
            .deepPage: { _ = try await store.page(after: first.last, limit: 200) },
            .search: { _ = try await store.page(matching: "Thursday", limit: 200) },
            .searchThatMatchesNothing: { _ = try await store.page(matching: "kubernetes", limit: 200) },
            .oneRow: { _ = try await store.record(first[100].id, matching: "thursday") },
            .recovered: { _ = try await store.recovered(since: .distantPast) },
            .pendingCount: { _ = try await store.pendingCount() },
            .lastDelivered: { _ = try await store.lastDelivered() },
            .knownIDs: { _ = try await store.knownIDs(among: known + [DictationID()]) },
        ]
    }

    func historyReadCosts(_ store: HistoryStore, known: [DictationID]) async throws -> [HistoryRead: [StatementCost]] {
        var costs: [HistoryRead: [StatementCost]] = [:]
        for (read, body) in try await historyReads(store, known: known) {
            costs[read] = try await KotobaStorageTests.costs(on: store, of: body)
        }
        return costs
    }

    /// What the History pane's reads cost on a large history, in SQLite's own steps (`TimingTests` times them), with
    /// the store opened again after the fill as at launch, so the planner has its statistics (`PRAGMA optimize`). A
    /// read that finds its rows through an index costs the same on 10,000 rows as on 5,000. A search that matches
    /// nothing reads every row once, with no sort: the history has no FTS index (`HistoryStore.page`). The menu's
    /// read of recovered dictations reads every row too (no index on `recovered_at`); it stays one pass.
    @Test func theHistoryReadsUseTheirIndexOn10000Rows() async throws {
        let ids = try await saveSpoken(0..<5_000, to: try HistoryStore(url: url, audio: audio))
        let store = try HistoryStore(url: url, audio: audio)
        let half = try await historyReadCosts(store, known: ids)
        _ = try await saveSpoken(5_000..<10_000, to: store)
        let full = try await historyReadCosts(store, known: ids)

        for (read, cost) in full {
            if read.readsEveryRow {
                #expect(cost.growsNoFasterThanTheRows(from: half[read] ?? []), "\(read)")
            } else {
                #expect(cost == half[read], "\(read)")
            }
        }
        #expect(full[.searchThatMatchesNothing]?.map(\.sorts) == [0])
    }
}

enum HistoryRead: String, CustomStringConvertible {
    case page
    case deepPage = "deep page"
    case search
    case searchThatMatchesNothing = "search that matches nothing"
    case oneRow = "one row"
    case recovered
    case pendingCount = "pending count"
    case lastDelivered = "last delivered"
    case knownIDs = "known ids"

    /// The reads that no index serves: each reads every row once.
    var readsEveryRow: Bool {
        self == .searchThatMatchesNothing || self == .recovered
    }

    var description: String { rawValue }
}
