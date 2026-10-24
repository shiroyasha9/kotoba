import Testing

@testable import KotobaStorage

typealias StatementCost = SQLiteDatabase.StatementCost

/// What each statement that `body` runs on `store` costs SQLite, in order. A test of a read on a large history checks
/// these counts, which load on the machine does not change, never its time (`TimingTests` has the times).
func costs(on store: HistoryStore, of body: () async throws -> Void) async rethrows -> [StatementCost] {
    await store.startCounting()
    do {
        try await body()
    } catch {
        _ = await store.stopCounting()
        throw error
    }
    return await store.stopCounting()
}

extension [StatementCost] {
    /// The same statements as `smaller`, the read on half the rows, with at most twice its steps in all: the work
    /// grows with the rows and no faster (no statement for each row, no pass for each row). One statement may grow more
    /// where its share of the rows does (the streak's read of the days before the chart).
    func growsNoFasterThanTheRows(from smaller: Self) -> Bool {
        map(\.sql) == smaller.map(\.sql) && steps <= 2 * smaller.steps
    }

    var steps: Int {
        reduce(0) { $0 + $1.steps }
    }
}
