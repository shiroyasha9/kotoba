import Foundation
import Testing

@testable import KotobaCore

/// A double tap of a separate push-to-talk chord records hands-free (`Settings.doubleTapGap`): the first tap is
/// dropped as every short push-to-talk press is, and the second press, soon after its release, is a hands-free press.
struct PipelineDoubleTapTests {
    @Test func aDoubleTapRecordsHandsFreeUntilTheNextTap() async {
        let world = FakeWorld(transcript: "locked")
        let pipeline = world.makePipeline()

        await pipeline.doubleTap(world)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: false))
        #expect(await world.audio.isCapturing)
        #expect(await world.audio.discarded.count == 1)
        #expect(await world.paster.pasteCount == 0)

        await pipeline.press(.hold)
        await pipeline.settle()
        #expect(await world.paster.pasted == ["locked"])
        #expect(await world.store.records.count == 1)
    }

    @Test func theSecondTapShowsAtItsRelease() async {
        let world = FakeWorld(transcript: "shown")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(150))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.settle()
        #expect(await pipeline.state == .idle)
        await pipeline.handle(.chordUp)

        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aHandsFreeTapStopsADoubleTapDictation() async {
        let world = FakeWorld(transcript: "stopped")
        let pipeline = world.makePipeline()
        await pipeline.doubleTap(world)
        world.clock.advance(by: .seconds(2))

        await pipeline.press(.toggle)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["stopped"])
    }

    @Test func escCancelsADoubleTapDictationWithUndo() async {
        let world = FakeWorld(transcript: "cancelled")
        let pipeline = world.makePipeline()
        await pipeline.doubleTap(world)

        await pipeline.handle(.escape)

        #expect(await pipeline.state == .undoable)
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func aSecondPressHeldPastTheThresholdKeepsRecordingAfterItsRelease() async {
        let world = FakeWorld(transcript: "held lock")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(200))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .seconds(2))
        await pipeline.settle()
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(2))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: false))
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func aSecondPressAtTheEndOfTheGapIsADoubleTap() async {
        let world = FakeWorld(transcript: "edge")
        let pipeline = world.makePipeline()

        await pipeline.doubleTap(world, gap: .milliseconds(300))

        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aHandsFreeShortcutPressBetweenTheTapsClearsTheFirstTap() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.press(.hold)
        await pipeline.handle(.chordDown(.toggle))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(100))
        await pipeline.press(.hold)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 3)
    }

    @Test func aSecondPressAfterTheGapIsAnotherShortPress() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(301))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 2)
        #expect(await world.store.records.isEmpty)
    }

    @Test func aShortcutOnTheSecondPressIsDropped() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(50))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 2)
        #expect(await world.store.records.isEmpty)
    }

    @Test func aShortcutPressIsNotAFirstTap() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 2)
    }

    @Test func aQuickThirdTapStopsWithTooLittleAudioAndDropsIt() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()
        await pipeline.doubleTap(world)
        await world.audio.record(.milliseconds(200))

        world.clock.advance(by: .milliseconds(150))
        await pipeline.press(.hold)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.paster.pasteCount == 0)
        #expect(await world.provider.requests.isEmpty)
    }

    @Test func theStopTapIsNotAFirstTap() async {
        let world = FakeWorld(transcript: "stopped")
        let pipeline = world.makePipeline()
        await pipeline.doubleTap(world)
        world.clock.advance(by: .seconds(2))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.paster.pasted == ["stopped"])
    }

    @Test func aDoubleTapDoesNotResumeInTheUndoWindow() async {
        let world = FakeWorld(transcript: "cancelled")
        let pipeline = world.makePipeline()
        await pipeline.press(.toggle)
        await pipeline.handle(.escape)

        await pipeline.doubleTap(world)

        #expect(await pipeline.state == .undoable)
        #expect(await world.audio.resumes == 0)
    }

    /// With one chord for both a tap starts hands-free, so a double tap starts and stops, and the stop is dropped.
    @Test func aDoubleTapOfOneChordForBothStartsAndDrops() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()
        await world.audio.record(.milliseconds(250))

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .milliseconds(150))
        await pipeline.press(.tapOrHold)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.isCapturing == false)
        #expect(await world.provider.requests.isEmpty)
    }
}

extension DictationPipeline {
    /// Two push-to-talk taps, `gap` apart.
    func doubleTap(_ world: FakeWorld, gap: Duration = .milliseconds(150)) async {
        await press(.hold)
        world.clock.advance(by: gap)
        await press(.hold)
        await settle()
    }
}
