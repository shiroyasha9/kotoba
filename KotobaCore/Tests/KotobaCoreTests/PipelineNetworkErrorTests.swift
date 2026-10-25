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
        #expect(await pipeline.state.notice == .connectionBlocked(record.id))
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
        #expect(await pipeline.state.notice == .hostNotFound(record.id, host: "myspeech.cognitiveservices.azure.com"))

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
        #expect(await pipeline.state.notice == .rejected(record.id, .audioMissing))
    }

    /// The recording is longer than the route takes in one request: it is refused before any upload, kept, and not
    /// sent again, as the same send fails the same way. History's Transcribe Again With can send it on another route.
    @Test func aRecordingTooLongForTheRouteIsRejectedAndNotRetried() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.tooLong(bytes: 30_000_000, limit: 25_000_000))
        await pipeline.dictate(world)

        await pipeline.retryAtLaunch()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .rejected)
        #expect(record.attempts == 0)
        #expect(await world.provider.requests.count == 1)
        #expect(await pipeline.state.notice == .rejected(record.id, .tooLong))
    }
}
