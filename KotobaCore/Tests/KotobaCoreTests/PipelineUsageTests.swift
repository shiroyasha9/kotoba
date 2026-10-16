import Foundation
import Testing

@testable import KotobaCore

/// Each billed answer becomes one usage ledger entry, for the Usage pane: values the answers already carry.
struct PipelineUsageTests {
    @Test func aPastedDictationAddsOneSpeechEntry() async throws {
        let world = FakeWorld(transcript: "ship it now")
        await world.provider.charge(.reported(Decimal(5) / 100_000), audio: .seconds(2))
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        let entry = try #require(await world.store.ledger.first)
        #expect(await world.store.ledger.count == 1)
        #expect(
            entry
                == UsageEntry(
                    id: entry.id, time: world.clock.date, dictation: record.id, kind: .speech, model: "fake/model-1",
                    audio: .seconds(2), deliveredWords: 3, spokenWords: 3, cost: .reported(Decimal(5) / 100_000),
                    app: DictationApp(bundleID: "test.app100", name: "App 100")))
    }

    /// Words are runs of non-space characters, as the History pane counts them.
    @Test func wordsAreRunsOfNonSpace() {
        #expect(DictationRecord.wordCount(of: " ship\tit\nnow\u{00A0}ok, auth.ts — done ") == 7)
        #expect(DictationRecord.wordCount(of: " \n ") == 0)
        #expect(DictationRecord.wordCount(of: "नमस्ते दुनिया") == 2)
    }

    @Test func aCleanupDictationAlsoAddsACleanupEntry() async throws {
        let world = FakeWorld(transcript: "um ship it")
        await world.provider.charge(.estimated(Decimal(3) / 100_000), audio: .seconds(1))
        let cleaner = FakeTextCleaner(result: .success("Ship it."), cost: .reported(Decimal(2) / 10_000))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        let ledger = await world.store.ledger
        #expect(ledger.map(\.kind) == [.speech, .cleanup])
        #expect(ledger.map(\.model) == ["fake/model-1", "fake/cleaner"])
        // The delivered text went from 3 words to 2; 3 were spoken.
        #expect(ledger.map(\.deliveredWords) == [3, -1])
        #expect(ledger.map(\.spokenWords) == [3, 0])
        #expect(ledger.map(\.cost) == [.estimated(Decimal(3) / 100_000), .reported(Decimal(2) / 10_000)])
        #expect(ledger[1].audio == .zero)
    }

    @Test func aFailedCleanupAddsOnlyTheSpeechEntry() async throws {
        let world = FakeWorld(transcript: "um ship it")
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .failure(ProviderError.offline)))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.store.ledger.map(\.kind) == [.speech])
    }

    @Test func aFailedRequestAddsNothing() async throws {
        let world = FakeWorld(transcript: "later")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(try #require(await world.store.records.first).status == .failed)
        #expect(await world.store.ledger.isEmpty)
    }

    /// Each try is its own entry, dated when its answer came, on the route that answered it.
    @Test func aRetryAddsItsOwnEntry() async throws {
        let world = FakeWorld(transcript: "second try")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        world.clock.advance(by: .seconds(3_600))

        await pipeline.retryPending()

        let ledger = await world.store.ledger
        #expect(ledger.count == 1)
        #expect(ledger.first?.time == world.clock.date)
        #expect(ledger.first?.deliveredWords == 2)
    }

    /// A retry run reads the queue once; by a row's turn a live try may have written it again. The retry sends the row
    /// as stored then, so it keeps the live try's latency marks.
    @Test func aRetrySendsTheRowAsStoredAtItsTurn() async throws {
        let world = FakeWorld(transcript: "later")
        let first = queued(at: "/tmp/first.flac")
        var second = queued(at: "/tmp/second.flac")
        try await world.store.save(first)
        try await world.store.save(second)
        let gate = Gate()
        await world.provider.hold(at: gate, onlyFor: first.audio.file)
        let pipeline = world.makePipeline()

        async let run: Void = pipeline.retryPending()
        #expect(await eventually { await gate.hasWaiters })
        second.latency.record(.stop, offset: .seconds(4))
        try await world.store.save(second)
        await gate.open()
        await run

        let stored = try #require(await world.store.records.first { $0.id == second.id })
        #expect(stored.status == .recovered)
        #expect(stored.latency.offsets[.stop] == .seconds(4))
    }

    private func queued(at path: String) -> DictationRecord {
        DictationRecord(
            id: DictationID(), createdAt: .now, audio: RecordedAudio(file: URL(filePath: path), duration: .seconds(2)),
            transcript: nil, status: .failed, latency: LatencyLog())
    }
}
