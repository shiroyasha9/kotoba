import Foundation
import Testing

@testable import KotobaCore

/// The ledger of what is live, as a pure type: transitions in, answers and the announced activity out.
struct LiveDictationsTests {
    struct Take: Identifiable {
        let id = DictationID()
        var note = 0
    }

    typealias Live = LiveDictations<Take>

    let keyDown = ContinuousClock.now

    static func makeLive() -> Live {
        Live(announce: AsyncStream.makeStream(of: PipelineActivity.self).continuation)
    }

    func makeLive() -> Live {
        Self.makeLive()
    }

    func window(_ take: Take) -> UndoWindow<Take> {
        UndoWindow(item: take, duration: .seconds(5), at: keyDown) { _ in Task {} }
    }

    @Test func aRecordingIsLiveUntilItEnds() {
        var live = makeLive()
        let take = Take()

        live.start(take, keyDown: keyDown)
        #expect(live.recording?.id == take.id)
        #expect(!live.isQuiet)
        #expect(live.isDictationLive)
        #expect(live.hasRecording)
        live.announce(take.id, at: keyDown)
        #expect(!live.activity.isQuiet)

        live.end(take.id)
        #expect(live.recording == nil)
        #expect(live.isQuiet)
        #expect(!live.isDictationLive)
        #expect(live.activity == PipelineActivity(isQuiet: true, inFlight: []))
    }

    @Test func aStoppedDictationIsSentUntilItEnds() {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)

        live.stop(take.id, at: keyDown + .seconds(2))
        #expect(live.recording == nil)
        #expect(!live.hasRecording)
        #expect(live.isDictationLive)
        #expect(live.isSending(take.id))
        #expect(live.sendStep == .transcribing)
        #expect(live.activity == PipelineActivity(isQuiet: false, inFlight: [take.id]))

        live.end(take.id)
        #expect(!live.isSending(take.id))
        #expect(live.sendStep == nil)
        #expect(live.activity == PipelineActivity(isQuiet: true, inFlight: []))
    }

    /// One dictation still being transcribed keeps the step on transcribing.
    @Test func theSendStepIsCleaningOnlyWhenEverySendIsWithTheCleaner() {
        var live = makeLive()
        let first = Take()
        let second = Take()
        live.start(first, keyDown: keyDown)
        live.stop(first.id, at: keyDown)
        live.start(second, keyDown: keyDown)
        live.stop(second.id, at: keyDown)

        live.cleanupStarted(first.id)
        #expect(live.sendStep == .transcribing)
        live.cleanupStarted(second.id)
        #expect(live.sendStep == .cleaning)
    }

    /// Esc to Undo: the dictation stays live in its Undo window and while its capture resumes.
    @Test func aPausedRecordingStaysLiveUntilItResumes() {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)

        live.pause(window(take), at: keyDown + .seconds(1))
        #expect(live.recording == nil)
        #expect(live.paused?.item.id == take.id)
        #expect(live.hasRecording)

        let paused = live.unpause()
        #expect(paused?.item.id == take.id)
        #expect(live.paused == nil)
        #expect(!live.hasRecording)
        #expect(live.isDictationLive)

        live.resume(take, at: keyDown + .seconds(2))
        #expect(live.recording?.id == take.id)
        let log = live.end(take.id)
        #expect(log?.duration(from: .cancel, to: .resume) == .seconds(1))
    }

    /// A press that turns out to be a shortcut changes nothing the windows show: the activity counts a recording from
    /// its cue. Paste Again and a retry still wait for it.
    @Test func theActivityCountsARecordingFromItsCue() {
        var live = makeLive()
        let take = Take()

        live.start(take, keyDown: keyDown)
        #expect(live.activity.isQuiet)
        #expect(!live.isQuiet)
        live.end(take.id)
        #expect(live.activity.isQuiet)

        let next = Take()
        live.start(next, keyDown: keyDown)
        live.stop(next.id, at: keyDown)
        #expect(live.activity == PipelineActivity(isQuiet: false, inFlight: [next.id]))
    }

    /// The live recording has one place. A recording that takes it (a start or a resume that raced another) ends the
    /// one it replaces, so no dictation stays live with nothing left to end it.
    @Test(arguments: [true, false])
    func aRecordingThatTakesThePlaceEndsTheOneItReplaces(isResumeFirst: Bool) {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.pause(window(take), at: keyDown)
        _ = live.unpause()
        let next = Take()

        if isResumeFirst {
            live.resume(take, at: keyDown)
            live.start(next, keyDown: keyDown)
        } else {
            live.start(next, keyDown: keyDown)
            live.resume(take, at: keyDown)
        }
        let winner = isResumeFirst ? next : take
        #expect(live.recording?.id == winner.id)
        live.end(winner.id)
        #expect(live.isQuiet)
    }

    @Test func anEndedUndoWindowLeavesNothingLive() {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.pause(window(take), at: keyDown)

        live.end(take.id)
        #expect(live.paused == nil)
        #expect(live.isQuiet)
    }

    @Test func theLatencyMarksAreOffsetsFromKeyDownUntilTheDictationEnds() throws {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.announce(take.id, at: keyDown + .milliseconds(300))
        live.stop(take.id, at: keyDown + .seconds(2))

        let sent = try #require(live.latency(of: take.id))
        #expect(sent.keyDown == keyDown)
        #expect(sent.log.offsets == [.keyDown: .zero, .cue: .milliseconds(300), .stop: .seconds(2)])

        let log = live.end(take.id)
        #expect(log == sent.log)
        live.mark(.cue, of: take.id, at: keyDown)
        #expect(live.latency(of: take.id) == nil)
        let again = live.end(take.id)
        #expect(again == nil)
    }

    /// Return while recording goes to that recording; just after the stop it goes to the dictation that stopped,
    /// while that one is being sent.
    @Test func aReturnGoesToTheRecordingOrTheDictationJustStopped() {
        var live = makeLive()
        let first = Take()
        live.start(first, keyDown: keyDown)
        live.askSubmit()
        #expect(live.isSubmitAsked(first.id))
        live.end(first.id)

        let second = Take()
        live.start(second, keyDown: keyDown)
        live.stop(second.id, at: keyDown)
        #expect(!live.isSubmitAsked(second.id))
        live.askSubmit()
        #expect(live.isSubmitAsked(second.id))

        live.end(second.id)
        live.askSubmit()
        #expect(!live.isSubmitAsked(second.id))
    }
}
