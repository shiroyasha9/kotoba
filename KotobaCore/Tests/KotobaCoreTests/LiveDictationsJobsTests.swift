import Foundation
import Testing

@testable import KotobaCore

/// The ledger's jobs (Polish, Transcribe Again, a retry send), quit, and the waits on what is live.
struct LiveDictationsJobsTests {
    typealias Live = LiveDictationsTests.Live
    typealias Take = LiveDictationsTests.Take

    let keyDown = ContinuousClock.now

    func makeLive() -> Live {
        LiveDictationsTests.makeLive()
    }

    /// Parks a waiter on `condition`, applies `change`, and says whether the change woke it. A waiter it left parked
    /// is released, so the test never hangs.
    func wakes(_ condition: Live.Condition, _ live: inout Live, by change: (inout Live) -> Void) async -> Bool {
        var isWoken = false
        await withCheckedContinuation { continuation in
            live.wait(until: condition, continuation)
            change(&live)
            isWoken = live.waiterCount(condition) == 0
            if !isWoken { live.release(condition) }
        }
        return isWoken
    }

    /// `live.begin(job)`, outside `#expect`, which cannot call a mutating member.
    func begins(_ job: Live.Job, _ live: inout Live) -> Bool {
        live.begin(job)
    }

    /// Polish makes the pipeline busy but is no dictation: a dictation that starts during it overtakes it.
    @Test func polishIsLiveButNoDictation() {
        var live = makeLive()

        #expect(begins(.polish, &live))
        #expect(!live.isQuiet)
        #expect(!live.isDictationLive)
        #expect(!live.activity.isQuiet)
        #expect(!begins(.polish, &live))

        live.end(.polish)
        #expect(live.isQuiet)
        #expect(live.activity.isQuiet)
    }

    @Test func polishBeginsOnlyWhenNothingIsLiveAndNoDictationIsSentAgain() {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        #expect(!begins(.polish, &live))
        live.end(take.id)

        #expect(begins(.transcribeAgain(take.id), &live))
        #expect(!begins(.polish, &live))
        live.end(.transcribeAgain(take.id))
        #expect(begins(.polish, &live))
    }

    /// Transcribe Again pastes nothing: the pipeline stays quiet, and the activity lists the dictation.
    @Test func transcribeAgainIsRefusedWhileItsDictationIsSentOrDuringPolish() {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.stop(take.id, at: keyDown)
        #expect(!begins(.transcribeAgain(take.id), &live))
        live.end(take.id)

        #expect(begins(.transcribeAgain(take.id), &live))
        #expect(live.isQuiet)
        #expect(live.activity == PipelineActivity(isQuiet: true, inFlight: [], transcribingAgain: [take.id]))
        #expect(!begins(.transcribeAgain(take.id), &live))
        live.end(.transcribeAgain(take.id))
        #expect(live.activity.transcribingAgain.isEmpty)

        #expect(begins(.polish, &live))
        #expect(!begins(.transcribeAgain(take.id), &live))
    }

    @Test func aRetrySendBeginsOnlyWhenNothingIsLive() {
        var live = makeLive()
        #expect(begins(.polish, &live))
        #expect(!begins(.retrySend, &live))
        live.end(.polish)

        #expect(begins(.retrySend, &live))
        #expect(live.isRunning(.retrySend))
        #expect(live.isQuiet)
    }

    @Test func nothingBeginsOnceQuitBegan() {
        var live = makeLive()
        live.beginQuit()

        #expect(live.isQuitting)
        #expect(!begins(.polish, &live))
        #expect(!begins(.retrySend, &live))
        #expect(!begins(.transcribeAgain(DictationID()), &live))
    }

    @Test func aQuietWaiterWakesWhenTheLastLiveDictationOrPolishEnds() async {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.stop(take.id, at: keyDown)
        #expect(begins(.transcribeAgain(DictationID()), &live))

        #expect(await !wakes(.quiet, &live) { $0.cleanupStarted(take.id) })
        #expect(await wakes(.quiet, &live) { $0.end(take.id) })
        _ = live.begin(.polish)
        #expect(await wakes(.quiet, &live) { $0.end(.polish) })
    }

    /// Quit wakes the retry run that waits for quiet, so it sees quit began and sends nothing.
    @Test func quitWakesTheQuietWaiters() async {
        var live = makeLive()
        live.start(Take(), keyDown: keyDown)

        #expect(await wakes(.quiet, &live) { $0.beginQuit() })
    }

    /// Quit waits for every send on its way: the dictations being sent and a retry send.
    @Test func theSendsEndWhenNoDictationIsSentAndNoRetrySends() async {
        var live = makeLive()
        let take = Take()
        live.start(take, keyDown: keyDown)
        live.stop(take.id, at: keyDown)
        #expect(!live.areSendsEnded)
        live.end(take.id)
        #expect(live.areSendsEnded)

        _ = live.begin(.retrySend)
        let next = Take()
        live.start(next, keyDown: keyDown)
        live.stop(next.id, at: keyDown)
        #expect(await !wakes(.sendsEnded, &live) { $0.end(next.id) })
        #expect(await wakes(.sendsEnded, &live) { $0.end(.retrySend) })
    }

    /// Every job sends a billed request (Polish, Transcribe Again, a retry send): quit waits for each.
    @Test(arguments: [Live.Job.polish, .transcribeAgain(DictationID()), .retrySend])
    func quitWaitsForEveryJob(_ job: Live.Job) async {
        var live = makeLive()
        _ = live.begin(job)
        #expect(!live.areSendsEnded)

        #expect(await wakes(.sendsEnded, &live) { $0.end(job) })
    }

    /// A recording is no send: quit keeps it as pending, it does not wait for it.
    @Test func aRecordingIsNoSendOnItsWay() {
        var live = makeLive()
        live.start(Take(), keyDown: keyDown)

        #expect(live.areSendsEnded)
    }

    @Test func aReleaseWakesTheWaitersOfQuitsBound() async {
        var live = makeLive()
        _ = live.begin(.retrySend)

        #expect(await wakes(.sendsEnded, &live) { $0.release(.sendsEnded) })
    }

    @Test func aWaiterWhoseConditionHoldsGoesOnAtOnce() async {
        var live = makeLive()

        #expect(await wakes(.quiet, &live) { _ in })
        #expect(await wakes(.sendsEnded, &live) { _ in })
    }
}
