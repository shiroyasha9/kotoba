import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Audio retention's columns and index, added to the schemas that shipped (AGENTS.md "Migrations"). Each shape is the
/// schema SQL of that tag, as written there.
struct HistoryMigrationTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }
    var audio: URL { folder.url.appending(path: "audio", directoryHint: .isDirectory) }
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// `HistoryStore.schema` at v0.1.0.
    static let v010 = """
        PRAGMA journal_mode = WAL;
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
            reject_reason TEXT
        );
        CREATE INDEX IF NOT EXISTS dictations_status ON dictations (status);
        CREATE TABLE IF NOT EXISTS latency_marks (
            dictation_id TEXT NOT NULL REFERENCES dictations (id) ON DELETE CASCADE,
            mark TEXT NOT NULL,
            offset_ms REAL NOT NULL,
            PRIMARY KEY (dictation_id, mark)
        );
        """

    /// `HistoryStore.schema` with `ledgerSchema` at 9d69db8, whose ledger fill had run (`user_version` 1).
    static let usageBuild = """
        PRAGMA journal_mode = WAL;
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
            app_name TEXT
        );
        CREATE INDEX IF NOT EXISTS dictations_status ON dictations (status);
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
        PRAGMA user_version = 1;
        """

    /// A pasted dictation from 10 days ago and a failed one, as the old build wrote them: absolute paths under another
    /// home folder, files in the audio folder.
    func oldHistory(_ shape: String) throws -> (pasted: URL, failed: URL) {
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let pasted = audio.appending(path: "\(UUID().uuidString).flac")
        let failed = audio.appending(path: "\(UUID().uuidString).flac")
        try Data(count: 8_000).write(to: pasted)
        try Data(count: 8_000).write(to: failed)
        let old = "/Volumes/Old Mac/Library/Application Support/kotoba/audio/"
        let created = Self.now.timeIntervalSince1970 - 10 * 24 * 60 * 60
        let database = try SQLiteDatabase(url: url)
        try database.execute(shape)
        try database.run(
            """
            INSERT INTO dictations (id, created_at, audio_path, audio_duration_ms, transcript, status)
            VALUES (?1, ?3, ?4, 5000, 'ship it', 'pasted'), (?2, ?3, ?5, 5000, NULL, 'failed');
            """,
            [
                .text(UUID().uuidString), .text(UUID().uuidString), .real(created),
                .text(old + pasted.lastPathComponent), .text(old + failed.lastPathComponent),
            ])
        return (pasted, failed)
    }

    @Test(arguments: [("v0.1.0", v010), ("9d69db8", usageBuild)])
    func aShippedHistoryKeepsItsAudioUntilRetentionRuns(build: String, shape: String) async throws {
        let files = try oldHistory(shape)

        let store = try HistoryStore(url: url, audio: audio)

        #expect(store.hadDictationsAtOpen, "\(build)")
        let rows = try await store.page(limit: 10)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { !$0.isAudioDeleted })
        #expect(Set(rows.map(\.audio.file)) == [files.pasted, files.failed])
        let size = try #require(try await store.keptAudioSize())
        #expect(size.deletable > 0 && size.waiting > 0)

        let cutoff = Self.now - 7 * 24 * 60 * 60
        let batch = try await store.deleteAudio(transcribedBefore: cutoff, after: nil)
        #expect(batch.deleted.count == 1)
        #expect(!FileManager.default.fileExists(atPath: files.pasted.path))
        #expect(FileManager.default.fileExists(atPath: files.failed.path))
        #expect(try await store.pendingRetries().map(\.audio.file) == [files.failed])
    }

    /// Per-app modes add `cleanup_mode`: a cleanup dictation from before them was cleaned with the Code prompt, and a
    /// retry cleans it the same way.
    @Test(arguments: [("v0.1.0", v010), ("9d69db8", usageBuild)])
    func aShippedCleanupDictationReadsAsACodeCleanup(build: String, shape: String) async throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute(shape)
        try database.run(
            """
            INSERT INTO dictations (id, created_at, audio_path, audio_duration_ms, transcript, status, mode)
            VALUES (?1, ?2, '/tmp/a.flac', 1000, NULL, 'failed', 'cleanup');
            """,
            [.text(UUID().uuidString), .real(Self.now.timeIntervalSince1970)])

        let store = try HistoryStore(url: url, audio: audio)

        #expect(try await store.pendingRetries().map(\.output) == [.cleanup(.code)], "\(build)")
    }
}
