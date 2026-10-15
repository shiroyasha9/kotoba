import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

struct HistoryStoreTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }

    func record(_ status: DictationRecord.Status, at time: TimeInterval = 1_800_000_000) -> DictationRecord {
        var latency = LatencyLog()
        latency.record(.stop, offset: .seconds(3))
        latency.record(.pasteSent, offset: .milliseconds(3_812))
        return DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: time),
            audio: RecordedAudio(file: folder.url.appending(path: "\(UUID().uuidString).flac"), duration: .seconds(12)),
            transcript: nil, status: status, latency: latency)
    }

    @Test func aSavedRecordComesBackWhole() async throws {
        let store = try HistoryStore(url: url)
        var saved = record(.failed)
        saved.needsSetup = .endpoint
        saved.mode = .cleanup
        saved.model = "x-ai/grok-stt-1.0"
        try await store.save(saved)

        let loaded = try #require(try await HistoryStore(url: url).pendingRetries().first)
        #expect(loaded == saved)
        #expect(try await store.status(of: saved.id) == .failed)
    }

    @Test func aRejectedRecordKeepsItsReason() async throws {
        let store = try HistoryStore(url: url)
        var saved = record(.rejected)
        saved.rejectReason = .emptyTranscript
        try await store.save(saved)

        // No query returns rejected rows yet, so read the column directly.
        let rows = try SQLiteDatabase(url: url).query("SELECT reject_reason FROM dictations;")
        #expect(rows.first?.first == .text("emptyTranscript"))
    }

    @Test func theLastDeliveredIsTheNewestPastedOrCopiedRow() async throws {
        let store = try HistoryStore(url: url)
        #expect(try await store.lastDelivered() == nil)
        var pasted = record(.pasted, at: 1_800_000_000)
        pasted.transcript = "deploy it to versel"
        var copied = record(.copied, at: 1_800_000_100)
        copied.transcript = "raw words"
        copied.cleanedText = "Cleaned words."
        try await store.save(pasted)
        try await store.save(copied)
        try await store.save(record(.failed, at: 1_800_000_200))
        try await store.save(record(.cancelled, at: 1_800_000_300))

        let last = try #require(try await store.lastDelivered())
        #expect(last.id == copied.id)
        #expect(last.cleanedText == "Cleaned words.")
    }

    @Test func onlyPendingAndFailedAreQueued() async throws {
        let store = try HistoryStore(url: url)
        for status in [DictationRecord.Status.pending, .failed, .pasted, .rejected, .cancelled] {
            try await store.save(record(status))
        }

        #expect(Set(try await store.pendingRetries().map(\.status)) == [.pending, .failed])
        #expect(try await store.pendingCount() == 2)
    }

    @Test func recoveredRowsAreListedNewestFirstUntilCopied() async throws {
        let store = try HistoryStore(url: url)
        var older = record(.recovered)
        older.recoveredAt = Date(timeIntervalSince1970: 1_800_000_100)
        var newer = record(.recovered)
        newer.recoveredAt = Date(timeIntervalSince1970: 1_800_000_200)
        try await store.save(older)
        try await store.save(newer)

        #expect(try await store.recovered(since: .distantPast).map(\.id) == [newer.id, older.id])
        try await store.markCopied(newer.id)
        #expect(try await store.recovered(since: .distantPast).map(\.id) == [older.id])
        #expect(try await store.status(of: newer.id) == .copied)
    }

    @Test func pruneKeepsQueuedAndRejectedRows() async throws {
        let store = try HistoryStore(url: url)
        let pasted = record(.pasted, at: 1_000)
        let failed = record(.failed, at: 1_000)
        let rejected = record(.rejected, at: 1_000)
        for saved in [pasted, failed, rejected] {
            try await store.save(saved)
        }

        try await store.prune(olderThan: Date(timeIntervalSince1970: 2_000))

        #expect(try await store.status(of: pasted.id) == nil)
        #expect(try await store.status(of: failed.id) == .failed)
        #expect(try await store.status(of: rejected.id) == .rejected)
    }

    @Test func pruneDeletesTheAudioFileAndLatencyMarksOfAPrunedRow() async throws {
        let store = try HistoryStore(url: url)
        let pasted = record(.pasted, at: 1_000)
        let failed = record(.failed, at: 1_000)
        for saved in [pasted, failed] {
            try Data("flac".utf8).write(to: saved.audio.file)
            try await store.save(saved)
        }

        try await store.prune(olderThan: Date(timeIntervalSince1970: 2_000))

        #expect(!FileManager.default.fileExists(atPath: pasted.audio.file.path))
        #expect(FileManager.default.fileExists(atPath: failed.audio.file.path))
        // Two marks per record: only the failed row's remain, so the cascade ran on this connection.
        let marks = try SQLiteDatabase(url: url).query("SELECT count(*) FROM latency_marks;")
        #expect(marks.first?.first == .integer(2))
    }

    @Test func anOlderDatabaseGetsTheNewColumns() async throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute(
            """
            CREATE TABLE dictations (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, audio_path TEXT NOT NULL,
                audio_duration_ms INTEGER NOT NULL, transcript TEXT, status TEXT NOT NULL,
                needs_key INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO dictations VALUES ('6F8F57C5-7D3B-4B0E-9A3B-1C2D3E4F5A6B', 1800000000, '/tmp/a.flac', 1000,
                NULL, 'failed', 1);
            """)

        let store = try HistoryStore(url: url)

        let migrated = try #require(try await store.pendingRetries().first)
        #expect(migrated.needsSetup == .key)
        #expect(migrated.mode == .transcript)
    }
}
