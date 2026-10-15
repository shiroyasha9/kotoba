import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// Pasting through the pipeline starts a session; the next dictation ends it.
struct PipelineReadbackTests {
    @Test func aPasteStartsASessionAndTheNextDictationEndsIt() async {
        let world = FakeWorld(transcript: "deploy it to versel today")
        let readback = ReadbackWorld()
        let pipeline = world.makePipeline(readback: readback.readback)

        await pipeline.dictate(world)
        await readback.readback.settle()
        #expect(readback.watcher.opens == 1)
        #expect(await readback.readback.isFollowing)

        await pipeline.tap(world)
        await readback.readback.settle()
        #expect(await readback.readback.isFollowing == false)
        #expect(readback.field.isClosed)
    }

    @Test func aPasteWhileTheNextDictationRecordsStartsNoSession() async {
        let world = FakeWorld(transcript: "deploy it to versel today")
        let gate = Gate()
        await world.provider.hold(at: gate)
        let readback = ReadbackWorld()
        let pipeline = world.makePipeline(readback: readback.readback)

        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()
        await readback.readback.settle()

        #expect(await world.paster.pasteCount == 1)
        #expect(readback.watcher.opens == 0)
    }
}

/// A strong correction is added at once; a weak one waits in Suggestions. Without the pill's Undo, or when the edit
/// may hold half a word, all wait.
struct ReadbackChoiceTests {
    static let strong = DetectedCorrection(
        candidate: SuggestionCandidate(heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .edit),
        isStrong: true)
    static let weak = DetectedCorrection(
        candidate: SuggestionCandidate(heard: "add it", corrected: "audit", proposes: .term, origin: .edit),
        isStrong: false)

    static func edit(_ reason: EditReadback.EndReason, isSettled: Bool = true) -> EditReadback.Edit {
        EditReadback.Edit(pasted: "a", edited: "b", appBundleID: nil, endedBy: reason, isSettled: isSettled)
    }

    @Test(arguments: [EditReadback.EndReason.focusLeft, .textGone, .timeLimit])
    func strongIsAddedAndWeakIsSuggested(endedBy reason: EditReadback.EndReason) {
        let choice = ReadbackChoice(corrections: [Self.strong, Self.weak], of: Self.edit(reason))

        #expect(choice.add == [Self.strong.candidate])
        #expect(choice.suggest == [Self.weak])
    }

    @Test func aSessionTheNextDictationEndedOnlySuggests() {
        let choice = ReadbackChoice(corrections: [Self.strong, Self.weak], of: Self.edit(.nextDictation))

        #expect(choice.add.isEmpty)
        #expect(choice.suggest == [Self.strong, Self.weak])
    }

    @Test func anUnsettledEditOnlySuggests() {
        let choice = ReadbackChoice(corrections: [Self.strong], of: Self.edit(.textGone, isSettled: false))

        #expect(choice.add.isEmpty)
        #expect(choice.suggest == [Self.strong])
    }
}
