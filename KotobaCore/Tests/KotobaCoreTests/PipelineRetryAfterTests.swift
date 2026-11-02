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
        await pipeline.tap(world)
        await pipeline.tap(world)
        await world.sendAgainInPlace(times: TranscriptionSteps.rateLimitedSends - 1)
        await pipeline.settle()
        await world.provider.fail(with: nil)

        world.clock.advance(by: .seconds(24 * 60 * 60))
        await pipeline.settle()

        #expect(await world.provider.requests.count == TranscriptionSteps.rateLimitedSends)
    }

    /// A wait of a few seconds would wake kotoba every few seconds while the route refuses; one of hours waits for
    /// launch or the network instead.
    @Test(arguments: [
        (Duration.seconds(3), DictationPipeline.retryAfterBounds.lowerBound),
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

/// A refusal for now with a short wait (OpenRouter's 429 with `Retry-After: 1`) is sent again in place after that wait,
/// up to `TranscriptionSteps.rateLimitedSends` sends in all: the owner sees the spinner, then the paste, not an error.
struct PipelineRateLimitInPlaceTests {
    @Test(arguments: [Duration.seconds(1), Duration.seconds(2), nil])
    func aShortWaitSendsAgainAndPastes(asked: Duration?) async throws {
        let world = FakeWorld(transcript: "second try")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: asked))
        await pipeline.tap(world)
        await pipeline.tap(world)
        let wait = asked ?? TranscriptionSteps.rateLimitWaitUnsaid
        await world.clock.waitForTimer(at: world.clock.now + wait)
        await world.provider.fail(with: nil)

        world.clock.advance(by: wait - .milliseconds(1))
        #expect(await world.provider.requests.count == 1)
        #expect(await pipeline.state.phase == .transcribing)
        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(await world.provider.requests.count == 2)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pasted)
        #expect(record.transcript == "second try")
        #expect(await world.paster.pasteCount == 1)
        #expect(await pipeline.state.notice == nil)
    }

    @Test func theLastRefusalFailsTheDictation() async throws {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: .seconds(1)))
        await pipeline.tap(world)
        await pipeline.tap(world)
        await world.sendAgainInPlace(times: TranscriptionSteps.rateLimitedSends - 1)
        await pipeline.settle()

        #expect(await world.provider.requests.count == TranscriptionSteps.rateLimitedSends)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(await world.paster.pasteCount == 0)
    }

    /// A longer wait goes to the pipeline's scheduled retry (`PipelineRetryAfterTests`), so the dictation fails at once.
    @Test func aLongerWaitFailsAtOnce() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        let asked = TranscriptionSteps.longestRateLimitWaitInPlace + .milliseconds(1)
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: asked))
        await pipeline.dictate(world)

        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).status == .failed)
    }
}

extension FakeWorld {
    /// Lets the route's wait pass `times` times, each once its send in place is armed; every refusal here waits 1 s.
    func sendAgainInPlace(times: Int) async {
        for _ in 0..<times {
            await clock.waitForTimer(at: clock.now + TranscriptionSteps.rateLimitWaitUnsaid)
            clock.advance(by: TranscriptionSteps.rateLimitWaitUnsaid)
        }
    }
}
