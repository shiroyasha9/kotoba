import Foundation
import Testing

@testable import KotobaCore

/// Quit while a dictation is being sent waits a little for its answer (`DictationPipeline.quitWait`), so the billed
/// text is saved and the next launch does not send it again (audit C6).
struct PipelineQuitTests {
    @Test func quitWaitsForTheAnswerOfADictationInFlight() async throws {
        let world = FakeWorld(transcript: "almost lost")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        await gate.open()
        await quit

        let record = try #require(await world.store.records.first)
        #expect(record.status == .pasted)
        #expect(record.transcript == "almost lost")
    }

    @Test func quitWaitsNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "never came")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(try #require(await world.store.records.first).status == .pending)
        await gate.open()
        await pipeline.settle()
    }

    @Test func quitWithNothingInFlightReturnsAtOnce() async {
        let world = FakeWorld(transcript: "done")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)

        await pipeline.shutdown()

        #expect(await pipeline.quitWaiters.isEmpty)
    }
}
