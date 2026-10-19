import Foundation
import Testing

@testable import KotobaCore

/// Esc opens a 5 s Undo window: the mic goes off, Undo or a chord tap resumes the same recording.
struct PipelineUndoTests {
    @Test func escapeTurnsTheMicOffAndOffersUndo() async {
        let world = FakeWorld(transcript: "oops")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)

        #expect(await world.audio.isCapturing == false)
        #expect(await world.audio.isPaused)
        #expect(await pipeline.state.phase == .undoable)
        #expect(await world.store.records.isEmpty)
    }

    @Test func undoThenStopTranscribesTheWholeRecordingOnce() async throws {
        let world = FakeWorld(transcript: "first half and second half")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(3))
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(2))
        await pipeline.undo()
        #expect(await pipeline.state.phase == .recording(isLong: false))
        world.clock.advance(by: .seconds(4))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.audio.files.count == 1)
        #expect(await world.provider.requests.map(\.audio) == (await world.audio.files))
        #expect(await world.paster.pasted == ["first half and second half"])
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pasted)
        #expect(record.latency.offsets[.cancel] == .seconds(3))
        #expect(record.latency.offsets[.resume] == .seconds(5))
        #expect(record.latency.offsets[.stop] == .seconds(9))
    }

    @Test func aChordTapDuringTheWindowResumes() async {
        let world = FakeWorld(transcript: "resumed")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(1))
        await pipeline.tap(world)

        #expect(await world.audio.isCapturing)
        #expect(await world.audio.resumes == 1)
        #expect(await world.audio.files.count == 1)
        #expect(await pipeline.state.phase == .recording(isLong: false))

        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await world.paster.pasted == ["resumed"])
    }

    @Test func fiveSecondsWithoutUndoMakeTheCancelFinal() async throws {
        let world = FakeWorld(transcript: "gone")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .milliseconds(4_999))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .undoable)

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.provider.requests.isEmpty)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        #expect(record.audio.file == (await world.audio.files.first))

        await pipeline.undo()
        #expect(await pipeline.state == .idle)
        #expect(await world.audio.resumes == 0)
    }

    @Test func escapeAfterUndoOpensANewWindowThatCanExpire() async throws {
        let world = FakeWorld(transcript: "twice")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(4))
        await pipeline.undo()
        world.clock.advance(by: .seconds(3))
        await pipeline.handle(.escape)
        #expect(await pipeline.state.phase == .undoable)

        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.provider.requests.isEmpty)
        #expect(try #require(await world.store.records.first).status == .cancelled)
    }

    @Test func aShortcutPressDuringTheWindowDoesNotResume() async {
        let world = FakeWorld(transcript: "no")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)

        #expect(await world.audio.resumes == 0)
        #expect(await world.audio.isCapturing == false)
        #expect(await pipeline.state.phase == .undoable)
    }

    @Test func aHoldDuringTheWindowDoesNotResume() async {
        let world = FakeWorld(transcript: "no")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(500))
        await pipeline.handle(.chordUp)

        #expect(await world.audio.resumes == 0)
        #expect(await pipeline.state.phase == .undoable)
    }

    @Test func aFinishedTranscriptionDoesNotHideTheUndoWindow() async {
        let world = FakeWorld(transcript: "first")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await gate.open()
        await pipeline.settle()

        #expect(await pipeline.state.phase == .undoable)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()
        #expect(await pipeline.state == .idle)
    }

    @Test func aResumedLongRecordingStillShowsTheWarning() async {
        let world = FakeWorld(transcript: "long")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(601))
        await pipeline.settle()
        await pipeline.handle(.escape)
        await pipeline.undo()

        #expect(await pipeline.state.phase == .recording(isLong: true))
    }

    @Test func quitDuringTheUndoWindowKeepsTheAudioAsCancelled() async throws {
        let world = FakeWorld(transcript: "kept")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.shutdown()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        #expect(record.audio.file == (await world.audio.files.first))
        #expect(await world.audio.isCapturing == false)
    }

    @Test func quitDuringARecordingQueuesItForTheNextLaunch() async throws {
        let world = FakeWorld(transcript: "finish me later")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.shutdown()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .pending)
        #expect(await world.audio.isCapturing == false)
        let relaunched = world.makePipeline()
        await relaunched.retryPending()
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    /// Esc before the first buffer: nothing was recorded, so the final cancel keeps no row of 0 s and no file.
    @Test func aCancelWithNoAudioKeepsNoRow() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.audio.record(.zero)

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.store.records.isEmpty)
        #expect(await world.audio.discarded == (await world.audio.files))
    }
}
