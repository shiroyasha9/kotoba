import Foundation
import Testing

@testable import KotobaCore

/// Clipboard snapshot, transient write and restore.
struct PipelineClipboardTests {

    @Test func theClipboardComesBackOnceTheAppReadTheText() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["dictated"])
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await world.pasteboard.isTransient == false)
    }

    /// A read ends the wait for it: no timer is left to wake at idle.
    @Test func aReadPasteLeavesNoTimer() async {
        let world = FakeWorld(transcript: "dictated")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(world.clock.deadlines.isEmpty)
    }

    /// Handy #502: a busy app handles Cmd-V seconds later. The clipboard waits for its read, not for a fixed time, so
    /// it never pastes the old clipboard.
    @Test func aSlowAppGetsTheTranscriptAndThenTheClipboardComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()
        await world.paster.readLater()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(9))
        await pipeline.settle()
        let read = await world.pasteboard.appReads()
        await pipeline.settle()

        #expect(read == "dictated")
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    /// No app read the text within `Settings.readWait`: the paste went nowhere, so the text stays on the clipboard
    /// (lead, 2026-10-17) and the pill says so; the earlier clipboard is gone.
    @Test func aPasteNoAppReadLeavesTheTextOnTheClipboard() async throws {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()
        await world.paster.readLater()

        await pipeline.dictate(world)
        world.clock.advance(by: .milliseconds(9_999))
        await pipeline.settle()
        let stateBefore = await pipeline.state
        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()

        #expect(stateBefore == .idle)
        #expect(await world.pasteboard.text == "dictated")
        #expect(await world.pasteboard.isTransient == false)
        #expect(await world.pasteboard.appReads() == "dictated")
        let record = try #require(await world.store.records.first)
        #expect(record.status == .copied)
        #expect(await pipeline.state == .copied(record.id))
    }

    /// A clipboard manager that ignores the transient marker reads the text before the Cmd-V: its read is not the
    /// paste target's, so the clipboard does not come back early (the target would paste the old one).
    @Test func anEarlyReaderIsNotThePasteTarget() async throws {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        await world.pasteboard.readEachWriteAsAManager()
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        let afterThePaste = await world.pasteboard.text
        world.clock.advance(by: .seconds(10))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["dictated"])
        #expect(afterThePaste == "dictated")
        #expect(await world.pasteboard.text == "dictated")
    }

    /// A pasted into a busy app that never read it, then B: A's row says copied, not pasted; B's read brings the
    /// owner's clipboard back.
    @Test func aPasteReplacedBeforeAnyReadIsMarkedCopied() async throws {
        let world = FakeWorld(transcript: "first", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()
        await world.paster.readLater()
        await pipeline.dictate(world)

        await world.provider.hear("second")
        await pipeline.dictate(world)
        await world.pasteboard.appReads()
        await pipeline.settle()

        let records = await world.store.records
        #expect(records.map(\.transcript) == ["first", "second"])
        #expect(records.map(\.status) == [.copied, .pasted])
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.state == .idle)
    }

    @Test func aCopyAfterThePasteIsNotOverwritten() async {
        let world = FakeWorld(transcript: "dictated")
        let pipeline = world.makePipeline()
        await world.paster.readLater()

        await pipeline.dictate(world)
        await world.pasteboard.userCopies("copied later")
        await world.pasteboard.appReads()
        world.clock.advance(by: .seconds(10))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "copied later")
        #expect(await pipeline.state == .idle)
    }

    @Test func aSecondPasteDoesNotWaitAndTheOriginalClipboardComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .milliseconds(300))
        await pipeline.dictate(world)
        #expect(await world.paster.pasted == ["dictated", "dictated"])
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    @Test func aDeniedPasteLeavesTheTranscriptOnTheClipboard() async throws {
        let world = FakeWorld(transcript: "keep me")
        let pipeline = world.makePipeline()
        await world.paster.deny(with: FakeError())

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "keep me")
        #expect(await world.pasteboard.isTransient == false)
        let record = await world.store.records.first
        #expect(record?.status == .copied)
        #expect(await pipeline.state == .copied(try #require(record).id))
    }

    @Test func aCopyDuringRecordingIsWhatComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "before")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()
        await world.pasteboard.userCopies("copied while speaking")
        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["dictated"])
        #expect(await world.pasteboard.text == "copied while speaking")
    }

    @Test func aCopyDuringTranscriptionIsWhatComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "before")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)

        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        await world.pasteboard.userCopies("copied while waiting")
        await gate.open()
        await pipeline.settle()
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["dictated"])
        #expect(await world.pasteboard.text == "copied while waiting")
    }

    @Test func theSnapshotIsTakenAtTheAnnouncementNotForAShortcut() async throws {
        let world = FakeWorld(transcript: "dictated")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordInterrupted)
        await pipeline.handle(.chordUp)
        await pipeline.settle()
        #expect(await world.pasteboard.snapshots == 0)

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        #expect(await eventually { await world.pasteboard.snapshots == 1 })
        world.clock.advance(by: .seconds(4))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.pasteboard.snapshots == 1)
        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.snapshotReady] == .milliseconds(100))
    }
}
