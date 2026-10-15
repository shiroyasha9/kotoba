import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// The readback session after a paste: field events in, reads and reported edits out (docs/spec.md, Owner round
/// 2026-10-16). Time moves only through `ManualClock`.
struct EditReadbackTests {
    static let pasted = "deploy it to versel today"
    static let fixed = "Notes: deploy it to Vercel today"

    @Test func anEditIsReportedWhenFocusLeaves() async throws {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        await world.type(Self.fixed)
        await world.quiet()
        await world.leave()

        let edit = try #require(await world.nextEdit())
        #expect(edit.pasted == Self.pasted)
        #expect(edit.edited == "deploy it to Vercel today")
        #expect(edit.appBundleID == "com.example.notes")
        #expect(edit.endedBy == .focusLeft)
        #expect(world.field.isClosed)
    }

    @Test func theFieldIsReadOnlyAfterTheOwnerStopsTyping() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        await world.type("deploy it to Vers today")
        world.clock.advance(by: .milliseconds(300))
        await world.type("deploy it to Vercel today")
        world.clock.advance(by: .milliseconds(300))
        await world.readback.settle()
        #expect(world.field.reads.isEmpty)

        world.clock.advance(by: .milliseconds(200))
        await world.readback.settle()
        #expect(world.field.reads.count == 1)
    }

    @Test func eachReadIsBoundedAroundTheInsertionPoint() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        await world.type(Self.fixed)
        await world.quiet()

        #expect(world.field.reads == [Self.pasted.utf16.count + 64])
    }

    @Test func withoutAChangeNothingIsReadAndTheTimeLimitEndsTheSession() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        #expect(await world.readback.isFollowing)

        world.clock.advance(by: .seconds(60))
        await world.readback.settle()

        #expect(world.field.reads.isEmpty)
        #expect(world.field.isClosed)
        #expect(await world.readback.isFollowing == false)
        #expect(await world.nextEdit() == nil)
    }

    @Test func theTimeLimitReportsTheLastEdit() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type(Self.fixed)
        await world.quiet()

        world.clock.advance(by: .seconds(60))
        await world.readback.settle()

        #expect(await world.nextEdit()?.endedBy == .timeLimit)
    }

    @Test func focusLeavingReadsAChangeNotReadYet() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        await world.type(Self.fixed)
        await world.leave()
        await world.readback.settle()

        #expect(world.field.reads.count == 1)
        #expect(await world.nextEdit()?.edited == "deploy it to Vercel today")
    }

    @Test func aSentMessageEndsTheSessionWithTheEditBeforeIt() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type(Self.fixed)
        await world.quiet()

        await world.type("")
        await world.quiet()

        let edit = await world.nextEdit()
        #expect(edit?.edited == "deploy it to Vercel today")
        #expect(edit?.endedBy == .textGone)
        #expect(edit?.isSettled == true)
        #expect(world.field.isClosed)
    }

    @Test func textSentWhileTheOwnerStillTypedGivesAnUnsettledEdit() async {
        let world = ReadbackWorld()
        await world.paste("call Orlina about dinner")
        await world.type("call Orle about dinner")
        await world.quiet()

        await world.type("call Orlen about dinner")
        await world.type("call Orlena about dinner")
        await world.type("")
        await world.quiet()

        let edit = await world.nextEdit()
        #expect(edit?.edited == "call Orle about dinner")
        #expect(edit?.endedBy == .textGone)
        #expect(edit?.isSettled == false)
    }

    @Test func theTimeLimitDoesNotReadWhileTheOwnerTypes() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type("deploy it to Vercel today")
        await world.quiet()
        world.clock.advance(by: .milliseconds(59_300))
        await world.type("deploy it to Vercel tod")

        world.clock.advance(by: .milliseconds(200))
        await world.readback.settle()

        #expect(world.field.reads.count == 1)
        let edit = await world.nextEdit()
        #expect(edit?.endedBy == .timeLimit)
        #expect(edit?.isSettled == false)
    }

    @Test func aFieldThatNeverGoesQuietIsReadAfterTheMaximumWait() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        for _ in 0..<20 {
            await world.type(Self.fixed)
            world.clock.advance(by: .milliseconds(100))
            await world.readback.settle()
        }

        #expect(world.field.reads.count == 1)
    }

    @Test func aClearedTerminalPromptEndsTheSessionInSecondsWhileItRedraws() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)

        for _ in 0..<20 {
            await world.type("")
            world.clock.advance(by: .milliseconds(100))
            await world.readback.settle()
        }

        #expect(await world.readback.isFollowing == false)
        #expect(world.field.isClosed)
    }

    @Test func turningLearningOffEndsTheSessionAndReportsNothing() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type(Self.fixed)
        await world.quiet()

        await world.readback.setEnabled(false)
        await world.readback.settle()

        #expect(world.field.isClosed)
        #expect(await world.readback.isFollowing == false)
        #expect(await world.nextEdit() == nil)
    }

    @Test func withLearningOffAPasteOpensNoField() async {
        let world = ReadbackWorld()
        await world.readback.setEnabled(false)

        await world.paste(Self.pasted)

        #expect(world.watcher.opens == 0)
    }

    struct Window: Sendable {
        var caret: Int
        var length: Int
        var range: Range<Int>
    }

    @Test(arguments: [
        Window(caret: Int.max, length: 100, range: 70..<100),
        Window(caret: -1, length: 100, range: 0..<30),
        Window(caret: 50, length: 100, range: 20..<80),
        Window(caret: 500, length: 100, range: 70..<100),
        Window(caret: 5, length: 0, range: 0..<0),
    ])
    func theReadRangeIsClampedToTheField(_ window: Window) {
        #expect(EditReadback.readRange(caret: window.caret, length: window.length, radius: 30) == window.range)
    }

    @Test func aNewDictationEndsTheSessionWithoutAnotherRead() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type(Self.fixed)
        await world.quiet()

        await world.type("deploy it to Vercel today, then ship")
        await world.readback.dictationStarted()
        world.clock.advance(by: .seconds(1))
        await world.readback.settle()

        #expect(world.field.reads.count == 1)
        #expect(world.field.isClosed)
        #expect(await world.nextEdit()?.endedBy == .nextDictation)
    }

    @Test func aFieldThatOpensAfterTheNextDictationStartedIsClosedAtOnce() async {
        let world = ReadbackWorld(holdingOpen: true)
        await world.readback.pasted(Self.pasted)
        #expect(await eventually { world.watcher.opens == 1 })

        await world.readback.dictationStarted()
        await world.watcher.gate.open()
        await world.readback.settle()

        #expect(world.field.isClosed)
        #expect(await world.readback.isFollowing == false)
    }

    @Test func anUnchangedPasteReportsNothing() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type("Notes: " + Self.pasted)
        await world.quiet()
        await world.leave()

        #expect(await world.nextEdit() == nil)
    }

    @Test func noReadableFieldMeansNoSession() async {
        let world = ReadbackWorld(hasField: false)
        await world.readback.pasted(Self.pasted)
        await world.readback.settle()

        #expect(world.watcher.opens == 1)
        #expect(await world.readback.isFollowing == false)
    }

    @Test func aLongDictationIsNotFollowed() async {
        let world = ReadbackWorld()
        await world.readback.pasted(Array(repeating: "word", count: 201).joined(separator: " "))
        await world.readback.settle()

        #expect(world.watcher.opens == 0)
    }

    @Test func theNextPasteEndsTheSessionBeforeItFollowsTheNewField() async {
        let world = ReadbackWorld()
        await world.paste(Self.pasted)
        await world.type(Self.fixed)
        await world.quiet()

        await world.paste("ship it now")

        #expect(world.watcher.opens == 2)
        #expect(await world.nextEdit()?.endedBy == .nextDictation)
        #expect(await world.readback.isFollowing)
    }
}
