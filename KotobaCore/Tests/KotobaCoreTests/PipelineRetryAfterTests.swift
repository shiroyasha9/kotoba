import Foundation
import Testing

@testable import KotobaCore

/// The route asked to wait (`ProviderError.rateLimited`, from a `Retry-After` header): the waiting dictations are sent
/// once that time passed, on the pipeline clock, with no launch or network change needed.
struct PipelineRetryAfterTests {
    @Test func aLiveDictationRefusedForNowIsSentWhenTheRouteSaid() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: .seconds(60)))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        world.clock.advance(by: .seconds(59))
        await pipeline.settle()
        #expect(await world.provider.requests.count == 1)

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.requests.count == 2)
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    @Test func aRetryRunStoppedByTheRouteGoesOnWhenTheRouteSaid() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        await pipeline.dictate(world)
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: .seconds(30)))
        await pipeline.retryAtLaunch()
        #expect(await world.provider.requests.count == 3)
        await world.provider.fail(with: nil)

        world.clock.advance(by: .seconds(30))
        await pipeline.settle()

        #expect(await world.provider.requests.count == 5)
        #expect(await world.store.records.allSatisfy { $0.status == .recovered })
    }

    @Test func noWaitFromTheRouteSchedulesNothing() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: nil))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        world.clock.advance(by: .seconds(24 * 60 * 60))
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
    }

    /// A wait of a second would wake kotoba every second while the route refuses; one of hours waits for launch or the
    /// network instead.
    @Test(arguments: [
        (Duration.seconds(1), DictationPipeline.retryAfterBounds.lowerBound),
        (.seconds(2 * 60 * 60), DictationPipeline.retryAfterBounds.upperBound),
    ])
    func theWaitIsKeptWithinBounds(asked: Duration, waited: Duration) async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: asked))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        world.clock.advance(by: waited - .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.requests.count == 1)

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.requests.count == 2)
    }
}
