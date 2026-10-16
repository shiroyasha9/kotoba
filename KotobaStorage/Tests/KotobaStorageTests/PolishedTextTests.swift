import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Polish keeps its text next to the dictation's own (`polished_text`), and its answer in the ledger with no words.
extension HistoryStoreTests {
    static let spoken = "okay so fix the the login bug"
    static let polished = "Fix the login bug."

    /// A pasted dictation with its speech answer: 6 words.
    func pastedDictation() -> DictationRecord {
        var dictation = record(.pasted)
        dictation.transcript = Self.spoken
        dictation.usage = [
            UsageEntry(
                time: dictation.createdAt, dictation: dictation.id, kind: .speech, model: "mai", audio: .seconds(12),
                deliveredWords: 6, spokenWords: 6, cost: .reported(Decimal(3) / 10_000))
        ]
        return dictation
    }

    @Test func aPolishedTextComesBackWithTheTextsBeforeItAndSearchFindsIt() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let dictation = pastedDictation()
        try await store.save(dictation)

        #expect(try await store.setPolishedText(Self.polished, of: dictation.id, usage: []))

        let read = try #require(try await store.record(dictation.id))
        #expect(read.transcript == Self.spoken)
        #expect(read.polishedText == Self.polished)
        #expect(try await store.lastDelivered()?.latestText == Self.polished)
        #expect(try await store.page(matching: "login bug.", limit: 10).map(\.id) == [dictation.id])
        #expect(try await store.transcribedRecord(dictation.id)?.latency == dictation.latency)
    }

    @Test func onlyADictationWithTextTakesAPolishedTextButTheAnswerIsBilled() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let failed = record(.failed)
        try await store.save(failed)
        let answer = UsageEntry(
            time: failed.createdAt, dictation: failed.id, kind: .polish, model: "m", deliveredWords: 0,
            cost: .reported(1))

        #expect(try await store.setPolishedText("x", of: failed.id, usage: [answer]) == false)
        #expect(try await store.setPolishedText("x", of: DictationID(), usage: []) == false)
        #expect(try await store.record(failed.id)?.polishedText == nil)
        let usage = try await store.usage(from: failed.createdAt - 60, to: failed.createdAt + 60)
        #expect(usage.cost == 1)
    }

    @Test func aPolishAnswerIsBilledButIsNotADictation() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let dictation = pastedDictation()
        try await store.save(dictation)
        let answer = UsageEntry(
            time: dictation.createdAt, dictation: dictation.id, kind: .polish, model: "deepseek/deepseek-v4.1-flash",
            deliveredWords: 0, cost: .reported(Decimal(4) / 10_000))
        _ = try await store.setPolishedText(Self.polished, of: dictation.id, usage: [answer])

        let day = dictation.createdAt
        let usage = try await store.usage(from: day - 60, to: day + 60)
        #expect(usage.dictations == 1)
        #expect(usage.words == 6)
        #expect(usage.audio == .seconds(12))
        #expect(usage.cost == Decimal(7) / 10_000)
        #expect(usage.models.map(\.kind).sorted { $0.rawValue < $1.rawValue } == [.polish, .speech])
        let insights = try await store.insights(at: day, in: Calendar(identifier: .gregorian))
        #expect(insights.dictations == 1)
        #expect(insights.words == 6)
    }
}

/// `polished_text` is added on open to the schema v0.3.1 shipped (AGENTS.md "Migrations").
extension HistoryMigrationTests {
    @Test func aV031HistoryGetsThePolishedTextColumn() async throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute(Self.retentionBuild)
        // v0.3.1 added `cleanup_mode` to the retention build's shape.
        try database.execute("ALTER TABLE dictations ADD COLUMN cleanup_mode TEXT;")
        let id = UUID()
        try database.run(
            """
            INSERT INTO dictations (id, created_at, audio_path, audio_duration_ms, transcript, status)
            VALUES (?1, ?2, '/tmp/a.flac', 1000, 'ship it', 'pasted');
            """,
            [.text(id.uuidString), .real(Self.now.timeIntervalSince1970)])

        let store = try HistoryStore(url: url, audio: audio)
        #expect(try await store.transcribedRecord(DictationID(rawValue: id))?.polishedText == nil)

        #expect(try await store.setPolishedText("Ship it.", of: DictationID(rawValue: id), usage: []))
        #expect(try await store.lastDelivered()?.latestText == "Ship it.")
    }
}
