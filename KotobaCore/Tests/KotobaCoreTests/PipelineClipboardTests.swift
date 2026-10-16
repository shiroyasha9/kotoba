import Foundation
import Testing

@testable import KotobaCore

/// Clipboard snapshot, transient write and restore.
struct PipelineClipboardTests {

    @Test func theClipboardComesBackAfterTheRestoreDelay() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        #expect(await world.pasteboard.text == "dictated")
        #expect(await world.pasteboard.isTransient)

        world.clock.advance(by: .milliseconds(999))
        await pipeline.settle()
        #expect(await world.pasteboard.text == "dictated")

        world.clock.advance(by: .milliseconds(1))
        await pipeline.settle()
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    @Test func aCopyAfterThePasteIsNotOverwritten() async {
        let world = FakeWorld(transcript: "dictated")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        await world.pasteboard.userCopies("copied later")
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "copied later")
    }

    @Test func aSecondPasteDoesNotWaitAndTheOriginalClipboardComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .milliseconds(300))
        await pipeline.dictate(world)
        #expect(await world.paster.pasted == ["dictated", "dictated"])

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
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
