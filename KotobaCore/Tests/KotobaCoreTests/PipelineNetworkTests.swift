import Foundation
import Testing

@testable import KotobaCore

/// Story 22: failed dictations are sent again when the network returns, without a menu click.
struct PipelineNetworkTests {
    @Test func aReturningNetworkSendsTheFailedDictationsAgain() async throws {
        let world = FakeWorld(transcript: "sent later", clipboard: "owner's")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await pipeline.networkChanged(isOnline: false)
        await world.provider.fail(with: nil)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(await pipeline.state.notice == .recovered(record.id))
        #expect(await world.pasteboard.text == "owner's")
    }

    @Test func theFirstOnlineReportIsNotAReturn() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        await pipeline.networkChanged(isOnline: true)

        await pipeline.settle()
        await pipeline.networkChanged(isOnline: true)

        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).status == .failed)
    }

    @Test func eachOutageGivesOneRetry() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await pipeline.networkChanged(isOnline: false)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()
        #expect(await world.provider.requests.count == 2)

        await pipeline.networkChanged(isOnline: false)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()
        #expect(await world.provider.requests.count == 3)
    }

    @Test func aReturningNetworkNeverSendsAPastedDictationAgain() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let pasted = try #require(await world.store.records.first)
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await pipeline.networkChanged(isOnline: false)
        await world.provider.fail(with: nil)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()

        #expect(await world.provider.requests.filter { $0.audio == pasted.audio.file }.count == 1)
        #expect(await world.store.records.map(\.status) == [.pasted, .recovered])
    }

    @Test func aReturningNetworkWaitsForTheLiveDictation() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        let queued = try #require(await world.store.records.first).id
        await world.provider.fail(with: nil)
        await pipeline.networkChanged(isOnline: false)

        await pipeline.tap(world)
        // Returns while the recording runs: the monitor never waits on a retry (review B7). The retry itself waits
        // until the recording ends, so nothing is sent yet.
        await pipeline.networkChanged(isOnline: true)
        #expect(await world.provider.requests.count == 1)

        await pipeline.tap(world)
        await pipeline.settle()
        let records = await world.store.records
        #expect(await world.provider.requests.count == 3)
        #expect(records.first { $0.id == queued }?.status == .recovered)
        #expect(records.first { $0.id != queued }?.status == .pasted)
    }

    @Test func aDictationWaitingForAKeyStaysQueuedWhenTheNetworkReturns() async throws {
        let world = FakeWorld(transcript: "needs a key")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.auth(status: 401))
        await pipeline.dictate(world)
        world.setup.missing = .key

        await pipeline.networkChanged(isOnline: false)
        await world.provider.fail(with: nil)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).needsSetup == .key)
    }
}
