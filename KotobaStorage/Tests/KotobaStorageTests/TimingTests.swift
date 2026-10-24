import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// `make timing`: the wall-clock time of the reads on a large history whose cost `make test` counts in SQLite's
/// steps (`StatementCosts.swift`), against the limits those tests had. Off unless `KOTOBA_TIMING` is set, so
/// `make test` skips it: on a machine busy with other builds a time limit fails while the code is fine. Each store is
/// opened again after its fill, as at launch.
@Suite(.serialized, .enabled(if: Timing.isOn))
struct TimingTests {
    /// Measured 2026-10-16 (debug build): about 0.8 ms a page, 3.3 ms for a search that matches nothing, 0.06 ms for
    /// one row, 2.8 ms for the menu, 17.5 ms for the launch's id check of 10,001 files.
    @Test func historyReads() async throws {
        let history = HistoryStoreTests()
        let ids = try await history.saveSpoken(
            0..<10_000, to: try HistoryStore(url: history.url, audio: history.audio))
        let store = try HistoryStore(url: history.url, audio: history.audio)
        for (name, read) in try await history.historyReads(store, known: ids) {
            try await Timing.expect("History pane, \(name)", below: .milliseconds(100), read)
        }
    }

    /// Measured 2026-10-16: see `docs/research/memory-spike.md`, "Insights pane".
    @Test func insights() async throws {
        let activity = InsightsTests()
        let now = try activity.date(10, 14, 18)
        try await activity.saveDictations(0..<10_000, to: try activity.makeStore(), before: now)
        let store = try activity.makeStore()
        try await Timing.expect("Activity insights", below: .milliseconds(150)) {
            _ = try await store.insights(at: now, in: InsightsTests.india)
        }
    }

    /// Measured 2026-10-16 (debug build): about 18 ms for both ranges.
    @Test func usageSummary() async throws {
        let usage = UsageLedgerTests()
        try await usage.saveAnswered(0..<10_000, to: try HistoryStore(url: usage.url, audio: usage.audio))
        let store = try HistoryStore(url: usage.url, audio: usage.audio)
        try await Timing.expect("usage summary, two ranges", below: .milliseconds(150)) {
            _ = try await usage.summaries(store, saved: 10_000)
        }
    }

    /// Measured 2026-10-16 (debug build): the first run deletes 10,000 files in about 1.0 s, in batches of 500; the
    /// run after the next dictation finds none in about 0.6 ms; the size is one aggregate in about 3 ms.
    @Test func audioRetention() async throws {
        let retention = AudioRetentionStoreTests()
        try await retention.saveExpired(to: try HistoryStore(url: retention.url, audio: retention.audio))
        let store = try HistoryStore(url: retention.url, audio: retention.audio)
        try await Timing.expect("kept audio size", below: .milliseconds(500)) { _ = try await store.keptAudioSize() }
        try await Timing.expect("retention, first run", below: .seconds(10)) {
            _ = try await retention.deleteAudio(store, before: retention.now)
        }
        try await Timing.expect("retention, next run", below: .milliseconds(100)) {
            _ = try await retention.deleteAudio(store, before: retention.now)
        }
    }

    /// Measured 2026-10-16 (debug build): about 165 ms, once, at launch.
    @Test func ledgerFillAtOpen() async throws {
        let migration = UsageLedgerMigrationTests()
        try migration.saveOldDictations(10_000)
        try await Timing.expect("open that fills the ledger from 10,000 dictations", below: .seconds(2)) {
            _ = try HistoryStore(url: migration.url, audio: migration.audio)
        }
    }
}

/// The same in KotobaCore's `TimingTests.swift` (a test target cannot import another's): change both.
enum Timing {
    static let isOn = ProcessInfo.processInfo.environment["KOTOBA_TIMING"] != nil

    /// Times `body`, prints the time, and records an issue when it is not below `limit`.
    static func expect(_ name: String, below limit: Duration, _ body: () async throws -> Void) async rethrows {
        let time = try await ContinuousClock().measure { try await body() }
        let line = "timing: \(name): \(milliseconds(time)) (limit \(milliseconds(limit)))\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        #expect(time < limit, "\(name)")
    }

    private static func milliseconds(_ time: Duration) -> String {
        time.formatted(.units(allowed: [.milliseconds], width: .abbreviated, fractionalPart: .show(length: 2)))
    }
}
