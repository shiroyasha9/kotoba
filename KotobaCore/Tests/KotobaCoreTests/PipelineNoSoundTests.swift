import Foundation
import Testing

@testable import KotobaCore

/// The live no-sound warning: meter levels in, the recording state out. The decision itself is in
/// `NoSoundPolicyTests`; these check that the pipeline feeds it and shows it.
struct PipelineNoSoundTests {
    @Test func aMutedMicWarnsWhileRecordingAndKeepsRecording() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0, for: .milliseconds(1_900))
        #expect(await pipeline.state == .recording(isLong: false))

        await world.meter(pipeline, 0, for: .milliseconds(100))

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
        #expect(await world.audio.isCapturing)
    }

    @Test func aMicThatSendsNoLevelsWarnsAtTheDeadline() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        world.clock.advance(by: .milliseconds(1_999))
        await pipeline.settle()
        #expect(await pipeline.state == .recording(isLong: false))

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
    }

    @Test func aMicThatStopsSendingWarns2sAfterItsLastSound() async {
        // A device that hangs: its levels stop with no configuration change.
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0.4, for: .seconds(1))
        world.clock.advance(by: .milliseconds(1_999))
        await pipeline.settle()
        #expect(await pipeline.state == .recording(isLong: false))

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
    }

    @Test func aMicThatStopsAgainAfterTheWarningClearedWarnsAgain() async {
        // Mic A lost, mic B opens and sends sound, then mic B stops too.
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.loseInput(pipeline)
        await world.meter(pipeline, 0.4, for: .milliseconds(500))
        #expect(await pipeline.state == .recording(isLong: false))

        world.clock.advance(by: .seconds(2))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
    }

    @Test func aStopCancelsTheDeadline() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))
        var states = pipeline.states.makeAsyncIterator()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: .seconds(2))
        await pipeline.settle()

        #expect(await states.next() == .recording(isLong: false))
        #expect(await states.next() == .transcribing)
        #expect(await states.next() == .idle)
        #expect(await pipeline.state == .idle)
    }

    @Test func soundClearsTheWarning() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0, for: .seconds(3))
        await world.meter(pipeline, 0.4, for: .milliseconds(100))

        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aQuietRoomNeverWarns() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0.0053, for: .seconds(30))

        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aHoldShorterThanTheDelayNeverWarns() async {
        let world = FakeWorld(transcript: "push to talk")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))
        var states = pipeline.states.makeAsyncIterator()

        await pipeline.handle(.chordDown)
        await world.meter(pipeline, 0, for: .milliseconds(1_900))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["push to talk"])
        #expect(await states.next() == .recording(isLong: false))
        #expect(await states.next() == .transcribing)
        #expect(await states.next() == .idle)
    }

    @Test func aMicThatDisconnectsMidRecordingWarnsAtOnce() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0.4, for: .seconds(1))
        await world.loseInput(pipeline)

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
    }

    @Test func theTimeTheMicWasOffForUndoIsNotSilence() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        await world.meter(pipeline, 0, for: .milliseconds(1_500))
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(4))
        await pipeline.undo()
        await world.meter(pipeline, 0, for: .milliseconds(1_900))
        #expect(await pipeline.state == .recording(isLong: false))

        await world.meter(pipeline, 0, for: .milliseconds(100))

        #expect(await pipeline.state == .recording(isLong: false, isSilent: true))
    }

    @Test func theLongRecordingWarningKeepsTheNoSoundWarning() async {
        let world = FakeWorld(transcript: "long")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(597))
        await world.meter(pipeline, 0, for: .seconds(3))
        await pipeline.settle()

        #expect(await pipeline.state == .recording(isLong: true, isSilent: true))
    }
}

extension FakeWorld {
    /// The meter sends `level` each 100 ms for `duration`, and the pipeline takes each one.
    func meter(_ pipeline: DictationPipeline, _ level: Float, for duration: Duration) async {
        for _ in 0..<Int(duration / .milliseconds(100)) {
            clock.advance(by: .milliseconds(100))
            let taken = await pipeline.handledSoundEvents
            await audio.deliverLevel(level)
            _ = await eventually { await pipeline.handledSoundEvents > taken }
        }
    }

    /// The mic is lost, and the pipeline takes the event.
    func loseInput(_ pipeline: DictationPipeline) async {
        let taken = await pipeline.handledSoundEvents
        await audio.loseInput()
        _ = await eventually { await pipeline.handledSoundEvents > taken }
    }
}
