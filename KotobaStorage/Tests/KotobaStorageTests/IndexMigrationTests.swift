import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The read indexes after 0.4.6 (`HistoryStore.readIndexes`, `keptSizeIndexes`), added to the shape 0.4.6 shipped (AGENTS.md
/// "Migrations"). The shape is the schema SQL of v0.4.6, as written there, after its ledger fill.
struct IndexMigrationTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }
    var audio: URL { folder.url }

    /// `HistoryStore.schema` with `ledgerSchema`, `discardedSchema` and `keptAudioIndex` at v0.4.6.
    static let v046 = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA busy_timeout = 2000;
        CREATE TABLE IF NOT EXISTS dictations (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            audio_path TEXT NOT NULL,
            audio_duration_ms INTEGER NOT NULL,
            transcript TEXT,
            model TEXT,
            status TEXT NOT NULL,
            recovered_at REAL,
            cleaned_text TEXT,
            needs_setup TEXT,
            mode TEXT NOT NULL DEFAULT 'transcript',
            reject_reason TEXT,
            app_bundle_id TEXT,
            app_name TEXT,
            audio_deleted INTEGER NOT NULL DEFAULT 0,
            audio_bytes INTEGER,
            cleanup_mode TEXT,
            polished_text TEXT,
            attempts INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS dictations_status ON dictations (status);
        -- The History window's order, newest first.
        CREATE INDEX IF NOT EXISTS dictations_created ON dictations (created_at, id);
        CREATE TABLE IF NOT EXISTS latency_marks (
            dictation_id TEXT NOT NULL REFERENCES dictations (id) ON DELETE CASCADE,
            mark TEXT NOT NULL,
            offset_ms REAL NOT NULL,
            PRIMARY KEY (dictation_id, mark)
        );
        CREATE TABLE IF NOT EXISTS usage_ledger (
            id TEXT PRIMARY KEY,
            time REAL NOT NULL,
            dictation_id TEXT,
            kind TEXT NOT NULL,
            model TEXT NOT NULL,
            audio_ms INTEGER NOT NULL,
            words INTEGER NOT NULL,
            spoken_words INTEGER NOT NULL DEFAULT 0,
            cost_nano_usd INTEGER,
            cost_estimated INTEGER,
            app_bundle_id TEXT,
            app_name TEXT
        );
        CREATE INDEX IF NOT EXISTS usage_ledger_time ON usage_ledger (time);
        CREATE TABLE IF NOT EXISTS discarded_audio (id TEXT PRIMARY KEY) WITHOUT ROWID;
        DROP INDEX IF EXISTS dictations_kept_audio;
        CREATE INDEX IF NOT EXISTS dictations_kept_audio_2 ON dictations (coalesce(recovered_at, created_at), id)
            WHERE audio_deleted = 0 AND status IN ('pasted', 'copied', 'notPasted', 'recovered');
        PRAGMA user_version = 1;
        """

    /// A 0.4.6 history: pasted dictations one a second at each index, with the text `HistoryStoreTests.saveSpoken`
    /// gives them, then the given rows of other statuses one second after the newest.
    @discardableResult
    func oldHistory(pasted indices: Range<Int>, then statuses: [DictationRecord.Status] = []) throws -> [UUID] {
        let database = try SQLiteDatabase(url: url)
        try database.execute(Self.v046)
        let words = "please move the standup to thursday and ask the team to review the pull request before lunch"
            .split(separator: " ")
        var ids: [UUID] = []
        let rows = indices.map { index in
            let text = (0..<30).map { words[($0 * 7 + index) % words.count] }.joined(separator: " ")
            return (DictationRecord.Status.pasted, Double(index), text + " row\(index)")
        }
        let later = Double(indices.upperBound)
        try database.transaction { () throws(SQLiteError) in
            for (status, time, text) in rows + statuses.map({ ($0, later, "words") }) {
                let id = UUID()
                ids.append(id)
                try database.run(
                    """
                    INSERT INTO dictations (id, created_at, audio_path, audio_duration_ms, transcript, status,
                        recovered_at)
                    VALUES (?1, ?2, '/tmp/a.flac', 12000, ?3, ?4, ?5);
                    """,
                    [
                        .text(id.uuidString), .real(time), .text(text), .text(status.rawValue),
                        status == .recovered ? .real(later) : .null,
                    ])
            }
        }
        return ids
    }

    func indexes() throws -> [String] {
        try SQLiteDatabase(url: url)
            .query("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'dictations' ORDER BY name;")
            .compactMap(\.first?.string)
    }

    @Test func a046HistoryGetsTheReadIndexesAndKeepsItsRows() async throws {
        let ids = try oldHistory(pasted: 0..<2, then: [.failed, .recovered])

        let store = try HistoryStore(url: url, audio: audio)

        let opened = try indexes()
        #expect(!opened.contains("dictations_status"))
        for index in ["dictations_retry", "dictations_recovered", "dictations_unsized", "dictations_kept_size"] {
            #expect(opened.contains(index), "\(index)")
        }
        #expect(try await store.pendingRetries().map(\.id.rawValue) == [ids[2]])
        #expect(try await store.pendingCount() == 1)
        #expect(try await store.recovered(since: .distantPast).map(\.id.rawValue) == [ids[3]])
        #expect(try await store.lastDelivered()?.id.rawValue == ids[1])
        _ = try HistoryStore(url: url, audio: audio)
        #expect(try indexes() == opened)
    }

    /// The History pane's reads on a migrated 0.4.6 history cost what they cost on a new one
    /// (`HistoryStoreCostTests`): the same on 10,000 rows as on 5,000, but for the search that matches nothing. The
    /// old rows have no audio size: the first size read measures them, and the next one finds none with a probe.
    @Test func a046HistoryReadsThroughTheNewIndexes() async throws {
        let ids = try oldHistory(pasted: 0..<5_000).map(DictationID.init)
        let history = HistoryStoreTests()
        let store = try HistoryStore(url: url, audio: audio)
        let half = try await history.historyReadCosts(store, known: ids)
        _ = try await history.saveSpoken(5_000..<10_000, to: store)
        let full = try await history.historyReadCosts(store, known: ids)

        for (read, cost) in full where !read.readsEveryRow {
            #expect(cost == half[read], "\(read)")
        }
        _ = try await store.keptAudioSize()
        let size = try await costs(on: store) { _ = try await store.keptAudioSize() }
        #expect(size.count == 2)
        #expect(size.first.map { $0.steps < 5_000 } == true)
    }
}
