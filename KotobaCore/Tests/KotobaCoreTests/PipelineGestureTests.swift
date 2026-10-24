import Foundation
import Testing

@testable import KotobaCore

/// Separate hands-free and push-to-talk chords: a hands-free press toggles, a push-to-talk press records while held,
/// and a press of either stops a running recording. With one chord for both, `PipelineHotkeyTests` covers the gestures.
struct PipelineGestureTests {
    // MARK: Hands-free

    @Test func aLongHandsFreeHoldKeepsRecordingAfterItsRelease() async {
        let world = FakeWorld(transcript: "hands free")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.toggle))
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.audio.isCapturing)
        #expect(await world.paster.pasteCount == 0)

        await pipeline.press(.toggle)
        await pipeline.settle()
        #expect(await world.paster.pasted == ["hands free"])
    }

    @Test func aHandsFreeTapStartsAndTheNextTapPastes() async {
        let world = FakeWorld(transcript: "toggle")
        let pipeline = world.makePipeline()

        await pipeline.press(.toggle)
        #expect(await pipeline.state.phase == .recording(isLong: false))
        await pipeline.press(.toggle)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["toggle"])
    }

    @Test func aKeyTypedDuringTheHandsFreeStartIsAShortcut() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.toggle))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.isCapturing == false)
        #expect(await world.audio.discarded.count == 1)
        #expect(await world.store.records.isEmpty)
    }

    // MARK: Push to talk

    @Test func pushToTalkCapturesAtKeyDownShowsAtTheThresholdAndPastesAtRelease() async {
        let world = FakeWorld(transcript: "push to talk")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        #expect(await world.audio.isCapturing)
        world.clock.advance(by: .milliseconds(399))
        await pipeline.settle()
        #expect(await pipeline.state == .idle)
        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false, isPushToTalk: true))

        world.clock.advance(by: .seconds(2))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["push to talk"])
        #expect(await world.audio.isCapturing == false)
    }

    /// The release's own time is under the threshold, but the pipeline handled it after the threshold had announced
    /// the press (a busy moment): the start cue played and the pill showed, so the release ends it as push to talk,
    /// with the stop cue and a paste. It is no dropped tap, so the next push-to-talk press makes no double tap.
    @Test func aPushToTalkReleaseHandledAfterTheAnnouncementStopsAndPastes() async {
        let world = FakeWorld(transcript: "announced")
        let pipeline = world.makePipeline()
        let pressedAt = world.clock.now

        await pipeline.handle(.chordDown(.hold), at: pressedAt)
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false, isPushToTalk: true))
        await pipeline.handle(.chordUp, at: pressedAt + .milliseconds(300))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["announced"])
        #expect(await world.audio.discarded.isEmpty)
        #expect(await world.audio.isCapturing == false)
        world.clock.advance(by: .milliseconds(50))
        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false, isPushToTalk: true))
    }

    @Test func aShortPushToTalkPressIsDroppedWithNoCue() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()
        var states = pipeline.states.makeAsyncIterator()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(150))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.audio.isCapturing == false)
        #expect(await world.audio.discarded.count == 1)
        #expect(await world.store.records.isEmpty)
        #expect(await world.provider.requests.isEmpty)
        // The dropped press emitted nothing; the first states belong to the dictation after it.
        await pipeline.dictate(world)
        #expect(await states.next()?.phase == .recording(isLong: false))
        #expect(await states.next()?.phase == .transcribing)
    }

    @Test func aKeyTypedDuringAPushToTalkPressIsAShortcut() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordInterrupted)
        world.clock.advance(by: .seconds(1))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 1)
        #expect(await world.store.records.isEmpty)
    }

    @Test func aKeyTypedAfterPushToTalkShowsIsTyping() async {
        let world = FakeWorld(transcript: "kept")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(500))
        await pipeline.settle()
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["kept"])
    }

    // MARK: One chord through the other

    @Test func handsFreeReachedThroughPushToTalkTogglesBeforeTheCue() async {
        let world = FakeWorld(transcript: "upgraded")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(80))
        await pipeline.handle(.gestureChanged(.toggle))
        world.clock.advance(by: .milliseconds(80))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(3))
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func aGestureChangeAfterTheCueIsIgnored() async {
        let world = FakeWorld(transcript: "held")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(500))
        await pipeline.settle()
        await pipeline.handle(.gestureChanged(.toggle))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["held"])
    }

    @Test func pushToTalkReachedThroughHandsFreeDropsAShortPress() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.toggle))
        await pipeline.handle(.gestureChanged(.hold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.discarded.count == 1)
    }

    // MARK: Cross-chord presses

    @Test func aPushToTalkPressStopsAHandsFreeRecording() async {
        let world = FakeWorld(transcript: "stopped by the other chord")
        let pipeline = world.makePipeline()
        await pipeline.press(.toggle)

        let stop = world.clock.now
        await pipeline.handle(.chordDown(.hold))
        await world.waitForReleaseWait(pipeline, pressedAt: stop)
        let pastedWhileHeld = await world.paster.pasteCount
        world.clock.advance(by: .seconds(1))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(pastedWhileHeld == 0)
        #expect(await world.paster.pasted == ["stopped by the other chord"])
        #expect(await world.audio.files.count == 1)
        #expect(await world.audio.isCapturing == false)
        #expect(await pipeline.state == .idle)
    }

    @Test func aHandsFreePressStopsAHandsFreeRecordingStartedByAHold() async {
        let world = FakeWorld(transcript: "long start")
        let pipeline = world.makePipeline()
        await pipeline.handle(.chordDown(.toggle))
        world.clock.advance(by: .seconds(1))
        await pipeline.handle(.chordUp)

        await pipeline.press(.toggle)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["long start"])
    }

    // MARK: Undo window

    @Test func aPushToTalkTapDoesNotResumeInTheUndoWindow() async {
        let world = FakeWorld(transcript: "cancelled")
        let pipeline = world.makePipeline()
        await pipeline.press(.toggle)
        await pipeline.handle(.escape)

        await pipeline.press(.hold)

        #expect(await pipeline.state.phase == .undoable)
        #expect(await world.audio.resumes == 0)
    }

    @Test func aHandsFreeTapReachedThroughPushToTalkResumesInTheUndoWindow() async {
        let world = FakeWorld(transcript: "resumed")
        let pipeline = world.makePipeline()
        await pipeline.press(.toggle)
        await pipeline.handle(.escape)

        await pipeline.handle(.chordDown(.hold))
        await pipeline.handle(.gestureChanged(.toggle))
        await pipeline.handle(.chordUp)

        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.audio.resumes == 1)
    }

    // MARK: Missed releases

    /// The tap was off at the release (`KeyInput.tapReenabled`) and reports the chord-up when it is back.
    @Test func aPushToTalkReleaseFoundLateStopsAndPastes() async {
        let world = FakeWorld(transcript: "late release")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .seconds(3))
        await pipeline.settle()
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["late release"])
    }

    @Test func aHandsFreeReleaseFoundLateKeepsRecording() async {
        let world = FakeWorld(transcript: "late release")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.toggle))
        world.clock.advance(by: .seconds(3))
        await pipeline.settle()
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await world.paster.pasteCount == 0)
    }
}

extension DictationPipeline {
    /// Chord down and up within the tap threshold, with the gesture of the chord pressed.
    func press(_ gesture: ChordGesture) async {
        await handle(.chordDown(gesture))
        await handle(.chordUp)
    }
}
