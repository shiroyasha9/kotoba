import Foundation
import Testing

@testable import KotobaCore

/// A transcription that does not answer in time fails as a timeout, not as offline: the wait grows with the audio
/// (a long recording on a slow uplink), up to a bound (`Settings.transcriptionTimeout(for:)`).
struct PipelineTimeoutTests {
    @Test(arguments: [
        (Duration.seconds(10), Duration.seconds(80)),
        (.seconds(20 * 60), .seconds(675)),
        (.seconds(2 * 60 * 60), .seconds(30 * 60)),
    ])
    func noAnswerInTimeFailsAsATimeoutAndKeepsTheAudio(recorded: Duration, wait: Duration) async throws {
        let world = FakeWorld(transcript: "too late")
        await world.audio.record(recorded)
        let gate = Gate()
        await world.provider.hold(at: gate)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: wait - .milliseconds(1))
        let endedBefore = await eventually { await pipeline.state.phase != .transcribing }
        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()
        await gate.open()

        #expect(endedBefore == false)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.attempts == 1)
        #expect(await world.paster.pasteCount == 0)
        #expect(await pipeline.state.notice == .timedOut(record.id))
    }

    /// A retry that times out says so too, not "Couldn’t reach".
    @Test func aRetryThatTimesOutSaysSo() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)

        async let retried: Void = pipeline.retryPending()
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(80))
        await retried
        await gate.open()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(await pipeline.state.notice == .timedOut(record.id))
    }

    @Test func anAnswerInTimeCancelsTheBound() async throws {
        let world = FakeWorld(transcript: "in time")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(100))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["in time"])
        #expect(try #require(await world.store.records.first).status == .pasted)
        #expect(await pipeline.state == .idle)
    }

    @Test(arguments: [ProviderError.timedOut])
    func aTimeoutIsTransientAndUsesAnAttempt(error: ProviderError) {
        #expect(error.recovery == .transient)
        #expect(error.usesAttempt)
        #expect(error.rejectReason == nil)
    }
}
