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

    @Test func anEmptyTranscriptGetsOneRetryThenIsRejected() async throws {
        let world = FakeWorld(transcript: "")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.emptyTranscript)

        await pipeline.dictate(world)
        #expect(try #require(await world.store.records.first).status == .failed)
        #expect(try #require(await world.store.records.first).rejectReason == nil)
        await pipeline.retryPending()
        let rejected = try #require(await world.store.records.first)
        #expect(rejected.status == .rejected)
        #expect(rejected.rejectReason == .emptyTranscript)
        await pipeline.retryPending()

        #expect(await world.provider.requests.count == 2)
    }
}
