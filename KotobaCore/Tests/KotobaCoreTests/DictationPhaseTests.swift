import Foundation
import Testing

@testable import KotobaCore

/// The phase says what is live under any notice: learning from edits, and a development build's menu, wait for it.
struct DictationPhaseTests {
    /// Polish pastes over the owner's text with Backspaces; learning must not take that for an edit.
    @Test func polishIsLive() async {
        let world = FakeWorld(transcript: PipelinePolishTests.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: PipelinePolishTests.polished, cost: .reported(1), gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })

        #expect(await pipeline.state.phase == .polishing)
        #expect(await pipeline.state.phase.isLive)
        await gate.open()
        await pipeline.settle()
        #expect(await !pipeline.state.phase.isLive)
    }

    /// One dictation's error shows while the next one is in flight: the phase still says it is being transcribed.
    @Test func aNoticeOverADictationInFlightKeepsItsPhase() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.tap(world)
        let first = try #require(await world.audio.files.last)
        let firstGate = Gate()
        await world.provider.hold(at: firstGate, onlyFor: first)
        await pipeline.tap(world)
        #expect(await eventually { await firstGate.hasWaiters })
        await pipeline.tap(world)
        let second = try #require(await world.audio.files.last)
        let secondGate = Gate()
        await world.provider.hold(at: secondGate, onlyFor: second)
        await pipeline.tap(world)
        #expect(await eventually { await secondGate.hasWaiters })

        await firstGate.open()
        #expect(
            await eventually { await world.store.records.contains { $0.audio.file == first && $0.status == .failed } })
        let failed = try #require(await world.store.records.first { $0.audio.file == first })
        #expect(await eventually { await pipeline.state.notice == .failed(failed.id) })
        #expect(await pipeline.state.phase == .transcribing)
        #expect(await pipeline.state.phase.isLive)

        await world.provider.fail(with: nil)
        await secondGate.open()
        await pipeline.settle()
        #expect(await pipeline.state.phase == .idle)
    }

    /// Polish that ends with nothing to show (here its dictation was deleted from History during the request) still
    /// ends its phase, so learning goes on and no Polishing pill stays.
    @Test func polishThatShowsNothingStillEnds() async throws {
        let world = FakeWorld(transcript: PipelinePolishTests.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: PipelinePolishTests.polished, cost: .reported(1), gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        let record = try #require(await world.store.records.first)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        _ = try await world.store.delete([record.id])
        await gate.open()
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
    }

    /// A dictation that pastes during Polish leaves Polish live until its answer, which then pastes nothing (that
    /// dictation's text came last): learning waits for it, and the Polishing pill goes when it ends.
    @Test func aDictationDuringPolishLeavesItLive() async throws {
        let world = FakeWorld(transcript: PipelinePolishTests.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: PipelinePolishTests.polished, cost: .reported(1), gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(1))
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await world.paster.pasted.count == 2 })
        #expect(await eventually { await pipeline.state.phase != .transcribing })
        #expect(await pipeline.state == DictationState(.polishing))
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted.count == 2)
        #expect(await pipeline.state == .idle)
    }
}
