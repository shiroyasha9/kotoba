import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The usage ledger: one row per billed answer, kept apart from the deletable history, summed over a date range.
struct UsageLedgerTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }

    static let notes = DictationApp(bundleID: "com.apple.Notes", name: "Notes")
    static let mail = DictationApp(bundleID: "com.apple.mail", name: "Mail")
    static let mai = "microsoft/mai-transcribe-2"

    func usd(_ text: String) throws -> Decimal {
        try #require(Decimal(string: text))
    }

    func entry(
        _ kind: UsageEntry.Kind = .speech, at time: TimeInterval, for dictation: DictationID = DictationID(),
        model: String = mai, audio: Duration = .seconds(10), words: Int = 2, cost: Cost? = nil,
        app: DictationApp? = nil
    ) -> UsageEntry {
        UsageEntry(
            time: Date(timeIntervalSince1970: time), dictation: dictation, kind: kind, model: model,
            audio: kind == .speech ? audio : .zero, deliveredWords: words, spokenWords: kind == .speech ? words : 0,
            cost: cost, app: app)
    }

    /// A pasted dictation created at `time` whose answers are `usage`.
    func dictation(at time: TimeInterval, _ usage: [UsageEntry] = []) -> DictationRecord {
        var record = DictationRecord(
            id: usage.first?.dictation ?? DictationID(), createdAt: Date(timeIntervalSince1970: time),
            audio: RecordedAudio(file: folder.url.appending(path: "\(UUID().uuidString).flac"), duration: .seconds(10)),
            transcript: "one two", model: Self.mai, status: .pasted, latency: LatencyLog())
        record.usage = usage
        return record
    }

    func save(_ store: HistoryStore, _ entries: UsageEntry...) async throws {
        for entry in entries {
            try await store.save(dictation(at: entry.time.timeIntervalSince1970, [entry]))
        }
    }

    func everything(_ store: HistoryStore) async throws -> UsageSummary {
        try await store.usage(from: .distantPast, to: .distantFuture)
    }

    @Test func anEmptyLedgerHasNoUsage() async throws {
        let store = try HistoryStore(url: url)
        try await store.save(dictation(at: 1_000))

        #expect(try await everything(store) == UsageSummary())
    }

    @Test func savingARecordAgainAddsItsAnswersOnce() async throws {
        let store = try HistoryStore(url: url)
        let record = dictation(at: 1_000, [entry(at: 1_000, cost: .reported(try usd("0.001")))])
        try await store.save(record)
        try await store.save(record)
        #expect(try await store.update(record))

        #expect(try await everything(store).cost == (try usd("0.001")))
    }

    /// Story 33: what kotoba cost does not change when the owner deletes dictations or the history is pruned.
    @Test func deletingOrPruningDictationsKeepsTheirSpend() async throws {
        let store = try HistoryStore(url: url)
        let deleted = dictation(at: 1_000, [entry(at: 1_000, cost: .reported(try usd("0.001")))])
        let pruned = dictation(at: 2_000, [entry(at: 2_000, cost: .reported(try usd("0.002")))])
        try await store.save(deleted)
        try await store.save(pruned)

        try await store.delete([deleted.id])
        try await store.prune(olderThan: Date(timeIntervalSince1970: 3_000))

        #expect(try await store.page(limit: 10).isEmpty)
        let summary = try await everything(store)
        #expect(summary.cost == (try usd("0.003")))
        #expect(summary.dictations == 2)
        #expect(summary.words == 4)
    }

    /// A retry's answer was billed even when the owner deleted the dictation while it ran.
    @Test func anUpdateOfADeletedDictationStillAddsItsAnswer() async throws {
        let store = try HistoryStore(url: url)
        var record = dictation(at: 1_000)
        try await store.save(record)
        try await store.delete([record.id])

        record.usage = [entry(at: 2_000, for: record.id, cost: .reported(try usd("0.001")))]
        #expect(try await !store.update(record))

        #expect(try await everything(store).cost == (try usd("0.001")))
    }

    /// An answer counts in the period of the time it came, not of the dictation's key-down.
    @Test func onlyAnswersInTheRangeCount() async throws {
        let store = try HistoryStore(url: url)
        let id = DictationID()
        // Spoken before the range, retried inside it.
        try await store.save(dictation(at: 500, [entry(at: 1_500, for: id, cost: .reported(try usd("0.001")))]))
        try await save(
            store, entry(at: 999, cost: .reported(try usd("0.004"))),
            entry(at: 1_000, cost: .reported(try usd("0.001"))),
            entry(at: 2_000, cost: .reported(try usd("0.004"))))

        let summary = try await store.usage(
            from: Date(timeIntervalSince1970: 1_000), to: Date(timeIntervalSince1970: 2_000))

        #expect(summary.dictations == 2)
        #expect(summary.words == 4)
        #expect(summary.audio == .seconds(20))
        #expect(summary.cost == (try usd("0.002")))
        #expect(!summary.isCostEstimated)
    }

    /// Each try is billed: audio and cost add up; words and the dictation count come from answers with words.
    @Test func everyTryCountsItsAudioAndCostOnce() async throws {
        let store = try HistoryStore(url: url)
        let id = DictationID()
        let empty = entry(at: 1_000, for: id, words: 0, cost: .reported(try usd("0.001")))
        let retried = entry(at: 2_000, for: id, words: 3, cost: .reported(try usd("0.001")))
        try await store.save(dictation(at: 1_000, [empty, retried]))

        let summary = try await everything(store)

        #expect(summary.dictations == 1)
        #expect(summary.words == 3)
        #expect(summary.audio == .seconds(20))
        #expect(summary.cost == (try usd("0.002")))
    }

    /// Words are those of the delivered text: a used cleanup adds the change it made (4 spoken, 3 delivered).
    @Test func cleanupAnswersChangeTheWordsAndAddCostButNoAudio() async throws {
        let store = try HistoryStore(url: url)
        let id = DictationID()
        try await store.save(
            dictation(
                at: 1_000,
                [
                    entry(at: 1_000, for: id, words: 4, cost: .reported(try usd("0.001"))),
                    entry(.cleanup, at: 1_001, for: id, model: "anthropic/claude-haiku-5.5", words: -1, cost: nil),
                ]))

        let summary = try await everything(store)

        #expect(summary.words == 3)
        #expect(summary.dictations == 1)
        #expect(summary.audio == .seconds(10))
        #expect(summary.unpricedAnswers == 1)
        #expect(
            summary.models == [
                .init(.speech, model: Self.mai, cost: try usd("0.001")),
                .init(.cleanup, model: "anthropic/claude-haiku-5.5", cost: 0, unpricedAnswers: 1),
            ])
    }

    @Test func theSpendIsSplitByModelMostFirstAndEstimatedWhenAnyPartIs() async throws {
        let store = try HistoryStore(url: url)
        try await save(
            store, entry(at: 1_000, cost: .reported(try usd("0.001"))),
            entry(at: 2_000, model: "xai-direct/grok-stt", cost: .estimated(try usd("0.003"))),
            entry(at: 3_000, cost: .reported(try usd("0.001"))),
            entry(.cleanup, at: 4_000, model: "anthropic/claude-haiku-5.5", cost: .reported(try usd("0.0005"))))

        let summary = try await everything(store)

        #expect(summary.cost == (try usd("0.0055")))
        #expect(summary.isCostEstimated)
        #expect(
            summary.models == [
                .init(.speech, model: "xai-direct/grok-stt", cost: try usd("0.003"), isEstimated: true),
                .init(.speech, model: Self.mai, cost: try usd("0.002")),
                .init(.cleanup, model: "anthropic/claude-haiku-5.5", cost: try usd("0.0005")),
            ])
    }

    @Test func topAppsAreByWordsWithTheNewestName() async throws {
        let store = try HistoryStore(url: url)
        try await save(
            store, entry(at: 1_000, words: 4, app: Self.mail), entry(at: 2_000, words: 1, app: Self.notes),
            entry(at: 3_000, words: 2, app: DictationApp(bundleID: "com.apple.Notes", name: "Notes 2")),
            entry(at: 4_000, words: 9))

        let summary = try await store.usage(from: .distantPast, to: .distantFuture, apps: 1)

        #expect(summary.apps == [.init(app: Self.mail, words: 4)])
        #expect(
            try await everything(store).apps == [
                .init(app: Self.mail, words: 4),
                .init(app: DictationApp(bundleID: "com.apple.Notes", name: "Notes 2"), words: 3),
            ])
    }

    @Test func aQueuedRecordIsReadFreshOnlyWhileItIsQueued() async throws {
        let store = try HistoryStore(url: url)
        var failed = dictation(at: 1_000)
        failed.status = .failed
        failed.latency.record(.stop, offset: .seconds(2))
        try await store.save(failed)
        let pasted = dictation(at: 2_000)
        try await store.save(pasted)

        #expect(try await store.queuedRecord(failed.id) == failed)
        #expect(try await store.queuedRecord(pasted.id) == nil)
    }

    /// The cost the Usage pane pays when it opens: two ranges over 10,000 dictations of two answers on average.
    /// Measured 2026-10-16 (debug build): about 18 ms for both. The bound is loose for other agents' builds on the same
    /// machine.
    @Test func aSummaryOf10000DictationsStaysFast() async throws {
        let store = try HistoryStore(url: url)
        let apps = [Self.notes, Self.mail, DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), nil]
        for index in 0..<10_000 {
            let id = DictationID()
            let time = TimeInterval(index)
            var usage = [
                entry(
                    at: time, for: id, model: index % 3 == 0 ? "x-ai/grok-stt-1.0" : Self.mai, words: 13,
                    cost: .reported(try usd("0.0003")), app: apps[index % apps.count])
            ]
            if index % 5 == 0 {
                usage.append(
                    entry(
                        .cleanup, at: time, for: id, model: "google/gemini-3.5-flash-lite", words: -1,
                        cost: .reported(try usd("0.0003"))))
            }
            try await store.save(dictation(at: time, usage))
        }
        let clock = ContinuousClock()
        var summary = UsageSummary()
        let time = try await clock.measure {
            summary = try await store.usage(from: .distantPast, to: .distantFuture)
            _ = try await store.usage(from: Date(timeIntervalSince1970: 5_000), to: .distantFuture)
        }

        #expect(summary.dictations == 10_000)
        #expect(summary.words == 128_000)
        #expect(summary.cost == (try usd("3.6")))
        #expect(time < .milliseconds(150))
    }
}
