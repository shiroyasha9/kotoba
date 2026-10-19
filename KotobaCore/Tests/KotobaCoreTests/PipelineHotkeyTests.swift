import Foundation
import Testing

@testable import KotobaCore

/// Hotkey state machine: tap vs hold, start, Esc, the long-recording warning, the state stream.
///
/// Style: hotkey events in, outcomes out (text pasted, clipboard restored, audio kept,
/// latency recorded). Assert on what the fakes saw, never on the pipeline's private state.
struct PipelineHotkeyTests {
    @Test func tapToStartThenTapToStopPastesTheTranscript() async {
        let world = FakeWorld(transcript: "run make check")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["run make check"])
        let record = await world.store.records.first
        #expect(record?.status == .pasted)
        #expect(record?.transcript == "run make check")
        #expect(await world.audio.isCapturing == false)
    }

    @Test func aShortTapKeepsRecording() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.audio.isCapturing)
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func holdingPastTheThresholdIsPushToTalk() async {
        let world = FakeWorld(transcript: "push to talk")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["push to talk"])
        #expect(await world.audio.isCapturing == false)
    }

    @Test func aHoldJustUnderTheThresholdIsATap() async {
        let world = FakeWorld(transcript: "toggle")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(399))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.audio.isCapturing)
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func thePasteWaitsUntilTheStopChordIsReleased() async {
        let world = FakeWorld(transcript: "no stray modifiers")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)

        await pipeline.handle(.chordDown(.tapOrHold))
        let pastedWhileHeld = await eventually { await world.paster.pasteCount > 0 }
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(pastedWhileHeld == false)
        #expect(await world.paster.pasted == ["no stray modifiers"])
    }

    // MARK: Start, cancel, warning

    @Test func theRecordingStateComesOnlyAfterCaptureStarted() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.audio.holdBegin(at: gate)

        async let pressed: Void = pipeline.handle(.chordDown(.tapOrHold))
        #expect(await eventually { await gate.hasWaiters })
        #expect(await pipeline.state == .idle)
        await gate.open()
        await pressed
        await pipeline.handle(.chordUp)

        #expect(await world.audio.isCapturing)
        #expect(await pipeline.state.phase == .recording(isLong: false))
    }

    @Test func aTapCapturesAtOnceButShowsAndSoundsOnlyAtRelease() async throws {
        let world = FakeWorld(transcript: "tap")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        #expect(await world.audio.isCapturing)
        #expect(await pipeline.state == .idle)
        world.clock.advance(by: .milliseconds(150))
        await pipeline.handle(.chordUp)
        #expect(await pipeline.state.phase == .recording(isLong: false))

        await pipeline.tap(world)
        await pipeline.settle()
        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.cue] == .milliseconds(150))
    }

    @Test func aHoldShowsAndSoundsWhenTheThresholdPasses() async {
        let world = FakeWorld(transcript: "hold")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(399))
        await pipeline.settle()
        #expect(await pipeline.state == .idle)

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.audio.isCapturing)
    }

    @Test func aShortcutPressNeverShowsOrSounds() async {
        let world = FakeWorld(transcript: "after the shortcut")
        let pipeline = world.makePipeline()
        var states = pipeline.states.makeAsyncIterator()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(120))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        await pipeline.dictate(world)

        // The shortcut emitted nothing; the first states belong to the dictation after it.
        #expect(await states.next()?.phase == .recording(isLong: false))
        #expect(await states.next()?.phase == .transcribing)
        #expect(await states.next() == .idle)
    }

    @Test func tapAndHoldUseTheKeyEventTimesNotWhenTheyAreHandled() async {
        let world = FakeWorld(transcript: "slow start")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.audio.holdBegin(at: gate)
        let pressedAt = world.clock.now

        async let pressed: Void = pipeline.handle(.chordDown(.tapOrHold), at: pressedAt)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .milliseconds(600))
        await gate.open()
        await pressed
        await pipeline.handle(.chordUp, at: pressedAt + .milliseconds(380))

        #expect(await world.audio.isCapturing)
        #expect(await pipeline.state.phase == .recording(isLong: false))
    }

    @Test func aCaptureThatCannotStartShowsCaptureFailed() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()
        await world.audio.failBegin(with: FakeError())

        await pipeline.tap(world)

        #expect(await pipeline.state.notice == .captureFailed)
        #expect(await world.store.records.isEmpty)
    }

    /// The adapter lost the capture before the stop: nothing was written, so no dictation with a made-up length is
    /// kept, and nothing is sent.
    @Test func aStopThatFindsNoCaptureKeepsNothing() async {
        let world = FakeWorld(transcript: "never recorded")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await world.audio.loseCapture()

        await pipeline.tap(world)
        await pipeline.settle()

        // Not `.captureFailed`, which names a missing mic or mic access.
        #expect(await pipeline.state.notice == .nothingRecorded)
        #expect(await world.store.records.isEmpty)
        #expect(await world.provider.requests.isEmpty)
    }

    @Test func aQuitThatFindsNoCaptureKeepsNothing() async {
        let world = FakeWorld(transcript: "never recorded")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await world.audio.loseCapture()

        await pipeline.shutdown()

        #expect(await world.store.records.isEmpty)
    }

    @Test func escapeCancelsAndKeepsTheAudio() async {
        let world = FakeWorld(transcript: "never sent")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.provider.requests.isEmpty)
        #expect(await world.paster.pasteCount == 0)
        let record = await world.store.records.first
        #expect(record?.status == .cancelled)
        #expect(record?.audio.file == (await world.audio.files.first))
        #expect(await pipeline.state == .idle)
    }

    @Test func aKeyPressedWithTheChordIsAShortcutAndLeavesNoTrace() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.audio.isCapturing == false)
        #expect(await world.audio.discarded.count == 1)
        #expect(await world.store.records.isEmpty)
        #expect(await world.provider.requests.isEmpty)
        #expect(await world.paster.pasteCount == 0)
        #expect(await pipeline.state == .idle)
    }

    @Test func aKeyPressedDuringAnAnnouncedHoldIsOrdinaryTyping() async {
        let world = FakeWorld(transcript: "hold and type")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(500))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false))
        await pipeline.handle(.chordInterrupted)

        #expect(await world.audio.isCapturing)
        #expect(await world.audio.discarded.isEmpty)
        #expect(await pipeline.state.phase == .recording(isLong: false))
    }

    @Test func aKeyPressedAfterTheStartTapIsOrdinaryTyping() async {
        let world = FakeWorld(transcript: "keep going")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.chordInterrupted)

        #expect(await world.audio.isCapturing)
        #expect(await world.audio.discarded.isEmpty)
        #expect(await pipeline.state.phase == .recording(isLong: false))
    }

    @Test func tenMinutesOfRecordingWarnsButKeepsRecording() async {
        let world = FakeWorld(transcript: "long")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(599))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false))

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: true))
        #expect(await world.audio.isCapturing)
    }

    @Test func theWarningOfAStoppedRecordingNeverFires() async {
        let world = FakeWorld(transcript: "short")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: .seconds(700))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
    }

    @Test func statesStreamInOrder() async {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()
        var states = pipeline.states.makeAsyncIterator()

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await states.next()?.phase == .recording(isLong: false))
        #expect(await states.next()?.phase == .transcribing)
        #expect(await states.next() == .idle)
    }

}
