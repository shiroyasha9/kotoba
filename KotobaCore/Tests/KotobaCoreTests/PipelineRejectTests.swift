import Foundation
import Testing

@testable import KotobaCore

/// A request the route refuses is kept, never retried, and says why.
struct PipelineRejectTests {
    @Test func aRefusedRequestIsRejectedAndNeverRetried() async throws {
        let world = FakeWorld(transcript: "refused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rejected(status: 400, message: "Unsupported audio"))

        await pipeline.dictate(world)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .rejected)
        #expect(record.rejectReason == .other)
        #expect(await pipeline.state == .rejected(record.id, .other))

        await world.provider.fail(with: nil)
        await pipeline.retryPending()
        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).status == .rejected)
    }

    // Lead decision 6: a dictation with no credit is kept and waits; adding credit is the owner's setup step.
    @Test func aDictationWithNoCreditIsKeptAndWaitsForCredit() async throws {
        let world = FakeWorld(transcript: "no credit")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.noCredit)

        await pipeline.dictate(world)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.needsSetup == .credit)
        #expect(record.rejectReason == nil)
        #expect(await pipeline.state == .needsSetup(record.id, .credit))

        await world.provider.fail(with: nil)
        await pipeline.networkChanged(isOnline: false)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()
        #expect(await world.provider.requests.count == 1)
    }

    @Test func theMenuRetrySendsANoCreditDictationAgain() async throws {
        let world = FakeWorld(transcript: "credit added")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.noCredit)
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.needsSetup == nil)
    }

    @Test func aSuccessfulDictationSendsTheNoCreditOnesAgain() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.noCredit)
        await pipeline.dictate(world)
        let waiting = try #require(await world.store.records.first).id

        await world.provider.fail(with: nil)
        await pipeline.dictate(world)
        await pipeline.settle()

        let records = await world.store.records
        #expect(records.first { $0.id == waiting }?.status == .recovered)
        #expect(records.first { $0.id != waiting }?.status == .pasted)
        #expect(await world.provider.requests.count == 3)
    }

    @Test func aRetryRefusedByTheRouteBecomesRejected() async throws {
        let world = FakeWorld(transcript: "later refused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await world.provider.fail(with: ProviderError.rejected(status: 400, message: "Unsupported audio"))
        await pipeline.retryPending()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .rejected)
        #expect(record.rejectReason == .other)
    }

    @Test func aLiveRefusalSaysWhyInTheState() async throws {
        let world = FakeWorld(transcript: "refused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rejected(status: 413, message: "Payload Too Large"))

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(await pipeline.state == .rejected(record.id, .other))
    }

    /// Routes send text with spaces or a newline around it; the pipeline trims it, and the cleaned text too.
    @Test func theAnswersAreTrimmedBeforeThePaste() async throws {
        let world = FakeWorld(transcript: " ship it \n")
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .success("Ship it.\n")))

        await pipeline.dictate(world)
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["ship it", "Ship it."])
        #expect(await world.store.records.map(\.transcript) == ["ship it", "ship it"])
    }

    /// The provider answers with no words; the pipeline decides it heard no speech.
    @Test(arguments: ["", " \n "])
    func anEmptyTranscriptGetsOneRetryThenIsRejected(heard: String) async throws {
        let world = FakeWorld(transcript: heard)
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        let failed = try #require(await world.store.records.first)
        #expect(failed.status == .failed)
        #expect(failed.rejectReason == nil)
        #expect(failed.transcript == nil)
        #expect(await pipeline.state == .failed(failed.id))
        #expect(await world.paster.pasteCount == 0)
        await pipeline.retryPending()
        let rejected = try #require(await world.store.records.first)
        #expect(rejected.status == .rejected)
        #expect(rejected.rejectReason == .emptyTranscript)
        await pipeline.retryPending()

        #expect(await world.provider.requests.count == 2)
    }

    /// An answer with no words is billed: each try is a ledger entry with no words and its cost.
    @Test func anEmptyTranscriptKeepsTheCostOfEachTry() async throws {
        let world = FakeWorld(transcript: "")
        await world.provider.charge(.reported(Decimal(5) / 100_000), audio: .seconds(2))
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        await pipeline.retryPending()

        let rejected = try #require(await world.store.records.first)
        #expect(rejected.status == .rejected)
        #expect(rejected.model == "fake/model-1")
        let ledger = await world.store.ledger
        #expect(ledger.map(\.dictation) == [rejected.id, rejected.id])
        #expect(ledger.map(\.deliveredWords) == [0, 0])
        #expect(ledger.map(\.cost) == [.reported(Decimal(5) / 100_000), .reported(Decimal(5) / 100_000)])
    }

    /// An empty cleanup answer pastes the raw transcript, as a failed cleanup does, and keeps the cleanup's cost.
    @Test func anEmptyCleanupKeepsItsCostAndPastesTheRawTranscript() async throws {
        let world = FakeWorld(transcript: "ship it")
        let cleaner = FakeTextCleaner(result: .success(" "), cost: .reported(Decimal(2) / 10_000))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(await world.paster.pasted == ["ship it"])
        #expect(record.cleanedText == nil)
        let cleanup = try #require(await world.store.ledger.last)
        #expect(cleanup.kind == .cleanup)
        #expect(cleanup.deliveredWords == 0)
        #expect(cleanup.cost == .reported(Decimal(2) / 10_000))
        #expect(await pipeline.state == .cleanupFailed(record.id))
    }
}
