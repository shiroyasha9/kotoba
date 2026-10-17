import Foundation
import Testing

@testable import KotobaCore

/// A dictation is sent at most three times in all without the owner (`RetrySelection.automaticAttempts`): a failure
/// that reached the route may have been billed, so launch and a returning network stop sending it again. The owner's
/// Retry always sends.
struct PipelineRetryCapTests {
    @Test func aServerErrorIsSentAgainOnItsOwnOnlyUntilThreeAttempts() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)

        await pipeline.retryAtLaunch()
        await pipeline.retryAtLaunch()
        let sentByThen = await world.provider.requests.count
        await pipeline.retryAtLaunch()
        await pipeline.networkChanged(isOnline: false)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()

        #expect(sentByThen == 3)
        #expect(await world.provider.requests.count == 3)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.attempts == 3)
    }

    @Test func theOwnersRetrySendsADictationPastTheCap() async throws {
        let world = FakeWorld(transcript: "at last")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await pipeline.retryAtLaunch()
        await pipeline.retryAtLaunch()
        let id = try #require(await world.store.records.first).id

        await world.provider.fail(with: FakeError())
        await pipeline.retryPending()
        await world.provider.fail(with: nil)
        await pipeline.retry([id])

        #expect(await world.provider.requests.count == 5)
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    /// No connection: nothing reached the route, so nothing was billed.
    @Test func anOfflineFailureUsesNoAttempt() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        for _ in 0..<4 {
            await pipeline.retryAtLaunch()
        }

        #expect(await world.provider.requests.count == 5)
        #expect(try #require(await world.store.records.first).attempts == 0)
    }

    /// A success status whose body does not parse: the same request gets the same answer, and it was billed.
    @Test func anUnreadableAnswerIsRejectedAndNotSentAgainOnItsOwn() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.unreadableAnswer(status: 200))
        await pipeline.dictate(world)

        await pipeline.retryAtLaunch()
        await pipeline.networkChanged(isOnline: false)
        await pipeline.networkChanged(isOnline: true)
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .rejected)
        #expect(await pipeline.state == .rejected(record.id, .other))
    }

    /// A live dictation that gets its text shows the route works again (a server outage ended with the network up):
    /// the failed dictations are sent then, not only at the next launch.
    @Test func aLiveTranscriptSendsTheFailedDictationsAgain() async throws {
        let world = FakeWorld(transcript: "back again")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.dictate(world)

        #expect(await world.provider.requests.count == 3)
        #expect(await world.store.records.map(\.status).sorted { $0.rawValue < $1.rawValue } == [.pasted, .recovered])
    }

    @Test func aLiveTranscriptSendsNoDictationPastTheCap() async throws {
        let world = FakeWorld(transcript: "back again")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await pipeline.retryAtLaunch()
        await pipeline.retryAtLaunch()

        await world.provider.fail(with: nil)
        await pipeline.dictate(world)

        #expect(await world.provider.requests.count == 4)
    }
}
