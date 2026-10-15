import Foundation
import Testing

@testable import KotobaCore

/// The pointer on the Undo pill holds the 5 s Undo window; when it leaves, the window runs on from
/// the time that was left, as the pill's bar does.
struct PipelineUndoHoldTests {
    @Test func aHeldWindowDoesNotClose() async {
        let world = FakeWorld(transcript: "held")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(2))
        await pipeline.holdUndoWindow(true)
        world.clock.advance(by: .seconds(60))
        await pipeline.settle()

        #expect(await pipeline.state == .undoable)
        #expect(await world.store.records.isEmpty)
    }

    @Test func aReleasedWindowClosesAfterTheTimeThatWasLeft() async throws {
        let world = FakeWorld(transcript: "released")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(2))
        await pipeline.holdUndoWindow(true)
        world.clock.advance(by: .seconds(60))
        await pipeline.holdUndoWindow(false)
        world.clock.advance(by: .milliseconds(2_999))
        await pipeline.settle()
        #expect(await pipeline.state == .undoable)

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(try #require(await world.store.records.first).status == .cancelled)
    }

    @Test func undoWorksWhileTheWindowIsHeld() async {
        let world = FakeWorld(transcript: "back")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.holdUndoWindow(true)
        world.clock.advance(by: .seconds(30))
        await pipeline.undo()

        #expect(await pipeline.state == .recording(isLong: false))
        #expect(await world.audio.resumes == 1)
    }

    @Test func aReleaseWithoutAHoldChangesNothing() async {
        let world = FakeWorld(transcript: "plain")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(3))
        await pipeline.holdUndoWindow(false)
        world.clock.advance(by: .seconds(2))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
    }

    @Test func aHoldWithNoWindowDoesNotCarryToTheNextWindow() async {
        let world = FakeWorld(transcript: "next")
        let pipeline = world.makePipeline()

        await pipeline.holdUndoWindow(true)
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
    }

    @Test func quitWhileTheWindowIsHeldKeepsTheAudioAsCancelled() async throws {
        let world = FakeWorld(transcript: "kept")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.holdUndoWindow(true)
        await pipeline.shutdown()

        #expect(try #require(await world.store.records.first).status == .cancelled)
    }
}
