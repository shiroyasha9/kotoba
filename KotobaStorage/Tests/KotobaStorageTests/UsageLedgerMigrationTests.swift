import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The one-time fill of the ledger from a history kept before it (v0.1.0 and later).
struct UsageLedgerMigrationTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }
    var audio: URL { folder.url }

    static let notes = DictationApp(bundleID: "com.apple.Notes", name: "Notes")
    static let mai = "microsoft/mai-transcribe-2"

    func everything(_ store: HistoryStore) async throws -> UsageSummary {
        try await store.usage(from: .distantPast, to: .distantFuture)
    }

    /// A database from before usage: answers get the recording's length and no cost; the pane says so. A row with
    /// cleaned text also had a cleanup request, whose model was not kept.
    @Test func anOlderDatabaseGetsAnswersWithoutACost() async throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute(
            """
            CREATE TABLE dictations (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, audio_path TEXT NOT NULL,
                audio_duration_ms INTEGER NOT NULL, transcript TEXT, model TEXT, status TEXT NOT NULL,
                cleaned_text TEXT, app_bundle_id TEXT, app_name TEXT
            );
            INSERT INTO dictations VALUES ('6F8F57C5-7D3B-4B0E-9A3B-1C2D3E4F5A6B', 1800000000, '/tmp/a.flac', 4200,
                'um ship it', 'microsoft/mai-transcribe-2', 'pasted', 'Ship it.', 'com.apple.Notes', 'Notes');
            """)

        _ = try HistoryStore(url: url, audio: audio)
        // A second open finds the fill done and adds nothing.
        let summary = try await everything(try HistoryStore(url: url, audio: audio))

        #expect(summary.dictations == 1)
        #expect(summary.words == 2)
        #expect(summary.audio == .milliseconds(4_200))
        #expect(summary.cost == 0)
        #expect(summary.unpricedAnswers == 2)
        #expect(summary.apps == [.init(app: Self.notes, words: 2)])
        #expect(
            summary.models == [
                .init(.speech, model: Self.mai, cost: 0, unpricedAnswers: 1),
                .init(.cleanup, model: UsageEntry.unknownModel, cost: 0, unpricedAnswers: 1),
            ])
    }

    /// A database from before usage with `count` kept dictations of 30 words.
    func saveOldDictations(_ count: Int) throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute(
            """
            CREATE TABLE dictations (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, audio_path TEXT NOT NULL,
                audio_duration_ms INTEGER NOT NULL, transcript TEXT, model TEXT, status TEXT NOT NULL
            );
            """)
        let text = String(repeating: "move the standup to thursday ", count: 6)
        try old.transaction { () throws(SQLiteError) in
            for index in 0..<count {
                try old.run(
                    "INSERT INTO dictations VALUES (?1, ?2, '/tmp/a.flac', 8000, ?3, 'x-ai/grok-stt-1.0', 'pasted');",
                    [.text(UUID().uuidString), .real(Double(index)), .text(text)])
            }
        }
    }

    /// The one-time move at the first launch after this change, on 10,000 kept dictations: each gets its answer
    /// (`TimingTests` times the open).
    @Test func migrating10000OldDictationsFillsTheLedger() async throws {
        try saveOldDictations(10_000)

        let summary = try await everything(try HistoryStore(url: url, audio: audio))

        #expect(summary.dictations == 10_000)
        #expect(summary.words == 300_000)
        #expect(summary.unpricedAnswers == 10_000)
    }
}
