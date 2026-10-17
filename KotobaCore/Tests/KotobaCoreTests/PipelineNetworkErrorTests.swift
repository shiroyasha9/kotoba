import Foundation
import Testing

@testable import KotobaCore

/// Failures that are not "offline": a network that blocks the secure connection, and a kept audio file that is gone.
struct PipelineNetworkErrorTests {
    /// The network is up but blocks the connection (a captive portal): the pill says so, the audio stays queued, and
    /// the next send would be blocked the same way.
    @Test func aBlockedConnectionSaysSoAndKeepsTheAudioQueued() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.connectionBlocked)

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.attempts == 0)
        #expect(await pipeline.state == .connectionBlocked(record.id))
    }

    /// The owner's endpoint does not resolve: a typo in it, or DNS down. The pill names the host, and the dictation
    /// stays in the automatic retries, as no request reached a route.
    @Test func aHostThatDoesNotResolveIsNamedAndRetried() async throws {
        let world = FakeWorld(transcript: "found")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.hostNotFound(host: "myspeech.cognitiveservices.azure.com"))
        await pipeline.dictate(world)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.attempts == 0)
        #expect(await pipeline.state == .hostNotFound(record.id, host: "myspeech.cognitiveservices.azure.com"))

        await world.provider.fail(with: nil)
        await pipeline.retryAtLaunch()

        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    /// The audio file was deleted outside kotoba: nothing can be sent, so it leaves the queue and is not retried.
    @Test func aMissingAudioFileIsRejectedAndNotRetried() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.audioMissing)
        await pipeline.dictate(world)

        await pipeline.retryAtLaunch()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .rejected)
        #expect(await world.provider.requests.count == 1)
        #expect(await pipeline.state == .rejected(record.id, .audioMissing))
    }
}
