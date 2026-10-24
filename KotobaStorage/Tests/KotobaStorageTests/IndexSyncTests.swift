import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Each open makes the history's indexes match `HistoryStore.indexes` (`syncIndexes`): after a downgrade to 0.4.6 and
/// a second upgrade, after a change to an index's condition under the same name, and with nothing to do.
extension IndexMigrationTests {
    /// Every named index in the history, with its SQL as `sqlite_master` keeps it.
    func builtIndexes() throws -> [String: String] {
        try HistoryStore.builtIndexes(in: SQLiteDatabase(url: url)).mapValues(\.sql)
    }

    var listedIndexes: [String: String] {
        Dictionary(uniqueKeysWithValues: HistoryStore.indexes.map { ($0.name, $0.sql) })
    }

    func schemaVersion() throws -> Int64? {
        try SQLiteDatabase(url: url).query("PRAGMA schema_version;").first?.first?.integer
    }

    /// 0.4.6 opens a migrated history (it builds `dictations_status` again) and writes rows as it does, then this build
    /// opens it again: the indexes are the listed ones, and the reads find the rows of both builds.
    @Test func a046BuildBetweenTwoUpgradesLeavesTheListedIndexes() async throws {
        let ids = try oldHistory(pasted: 0..<2, then: [.failed, .recovered])
        _ = try HistoryStore(url: url, audio: audio)

        let downgraded = try SQLiteDatabase(url: url)
        try downgraded.execute(Self.v046)
        let (pasted, failed, recovered) = (UUID(), UUID(), UUID())
        try downgraded.run(
            """
            INSERT INTO dictations (id, created_at, audio_path, audio_duration_ms, transcript, status, recovered_at,
                audio_bytes)
            VALUES (?1, 10, '/tmp/a.flac', 1000, 'later', 'pasted', NULL, 4),
                (?2, 11, '/tmp/b.flac', 1000, NULL, 'failed', NULL, 4),
                (?3, 12, '/tmp/c.flac', 1000, 'kept', 'recovered', 12, 4);
            """, [.text(pasted.uuidString), .text(failed.uuidString), .text(recovered.uuidString)])
        #expect(try builtIndexes()["dictations_status"] != nil)

        let store = try HistoryStore(url: url, audio: audio)

        #expect(try builtIndexes() == listedIndexes)
        #expect(try await store.pendingRetries().map(\.id.rawValue) == [ids[2], failed])
        #expect(try await store.pendingCount() == 2)
        #expect(Set(try await store.recovered(since: .distantPast).map(\.id.rawValue)) == [ids[3], recovered])
        #expect(try await store.lastDelivered()?.id.rawValue == pasted)
        #expect(try await store.page(limit: 10).count == 7)
        #expect(try await store.keptAudioSize() != nil)
    }

    /// SQLite keeps a changed index under its old name, so an index built from other SQL (here, an older condition) or
    /// one the list does not have is replaced at the next open.
    @Test func anIndexFromOtherSQLIsBuiltAgainAndAnUnlistedOneDropped() async throws {
        _ = try HistoryStore(url: url, audio: audio)
        let database = try SQLiteDatabase(url: url)
        try database.execute(
            """
            DROP INDEX dictations_retry;
            CREATE INDEX dictations_retry ON dictations (created_at) WHERE status = 'failed';
            CREATE INDEX dictations_stray ON dictations (model);
            """)

        let store = try HistoryStore(url: url, audio: audio)

        #expect(try builtIndexes() == listedIndexes)
        let pending = DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            audio: RecordedAudio(file: audio.appending(path: "pending.flac"), duration: .seconds(5)), transcript: nil,
            status: .pending, latency: LatencyLog())
        try await store.save(pending)
        #expect(try await store.pendingRetries().map(\.id) == [pending.id])
    }

    /// The indexes 0.4.6 built with the listed SQL (it wrote `IF NOT EXISTS`, which SQLite does not keep) stay: the
    /// first open drops only `dictations_status` and builds only the indexes 0.4.6 did not have.
    @Test func a046HistoryKeepsTheIndexesItShares() throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute(Self.v046)

        let changes = HistoryStore.indexChanges(built: try HistoryStore.builtIndexes(in: database))

        #expect(changes.drop == ["dictations_status"])
        #expect(
            changes.create.map(\.name) == [
                "dictations_unsized", "dictations_kept_size", "dictations_retry", "dictations_recovered",
            ])
    }

    /// A unique index the list does not have (a later build's) stays after a downgrade's open.
    @Test func anUnlistedUniqueIndexStays() throws {
        _ = try HistoryStore(url: url, audio: audio)
        try SQLiteDatabase(url: url).execute("CREATE UNIQUE INDEX dictations_later ON dictations (audio_path);")

        _ = try HistoryStore(url: url, audio: audio)

        #expect(try builtIndexes()["dictations_later"] != nil)
    }

    /// The SQL each open compares is the SQL SQLite keeps, so an open that finds the indexes as listed changes no
    /// schema.
    @Test(arguments: [false, true])
    func anOpenWithTheListedIndexesChangesNothing(fromV046: Bool) throws {
        if fromV046 { try oldHistory(pasted: 0..<2) }
        _ = try HistoryStore(url: url, audio: audio)
        let version = try schemaVersion()

        _ = try HistoryStore(url: url, audio: audio)

        #expect(try builtIndexes() == listedIndexes)
        #expect(try schemaVersion() == version)
    }
}
