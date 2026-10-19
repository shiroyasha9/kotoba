import Foundation
import Testing

@testable import KotobaCore

/// The screen locks, the Mac sleeps or another user takes the session: a hands-free recording stops and what it
/// recorded is transcribed, never lost; no text pastes while the owner is away (it would go to the lock screen), so it
/// waits on the clipboard.
struct PipelineAwayTests {
    @Test(arguments: [Absence.screenLocked, .asleep, .sessionInactive])
    func aLiveRecordingStopsAndItsTextIsCopied(absence: Absence) async throws {
        let world = FakeWorld(transcript: "Ship it.")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)

        await pipeline.absenceBegan(absence)
        await pipeline.settle()

        #expect(await world.audio.isCapturing == false)
        #expect(await world.paster.keystrokes == [])
        #expect(await world.pasteboard.text == "Ship it.")
        let record = try #require(await world.store.records.first)
        #expect(record.status == .copied)
        #expect(await pipeline.state == .copied(record.id))
    }

    @Test func aDictationInFlightAtTheLockIsCopied() async throws {
        let world = FakeWorld(transcript: "Ship it.")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        await pipeline.absenceBegan(.screenLocked)
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.keystrokes == [])
        #expect(try #require(await world.store.records.first).status == .copied)
    }

    /// A paste waits for the release of the next push-to-talk press; the screen locks while it is held, and its
    /// release is lost. The lock ends the wait: the text is copied, never pasted after the unlock.
    @Test func aPasteWaitingForAReleaseLostAtTheLockIsCopied() async throws {
        let world = FakeWorld(transcript: "Ship it.")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.handle(.chordDown(.tapOrHold))
        await gate.open()
        #expect(await eventually { await pipeline.releaseWaiters.count == 1 })

        await pipeline.absenceBegan(.screenLocked)
        try #require(await eventually { await pipeline.releaseWaiters.isEmpty })
        await pipeline.settle()
        await pipeline.absenceEnded(.screenLocked)

        #expect(await world.paster.keystrokes == [])
        let first = try #require(await world.store.records.first)
        #expect(first.status == .copied)
    }

    /// Locked and asleep at once: only the end of both brings pasting back.
    @Test func pastingComesBackWhenEveryAbsenceEnded() async {
        let world = FakeWorld(transcript: "Back.")
        let pipeline = world.makePipeline()
        await pipeline.absenceBegan(.screenLocked)
        await pipeline.absenceBegan(.asleep)
        await pipeline.absenceEnded(.asleep)
        await pipeline.dictate(world)
        let pastedWhileLocked = await world.paster.pasteCount

        await pipeline.absenceEnded(.screenLocked)
        await pipeline.dictate(world)

        #expect(pastedWhileLocked == 0)
        #expect(await world.paster.pasted == ["Back."])
    }

    /// Polish answers while the screen is locked: its ⌘V would go to the lock screen, so the polished text waits on
    /// the clipboard.
    @Test func aPolishThatAnswersWhileTheOwnerIsAwayIsCopied() async throws {
        let world = FakeWorld(transcript: PipelinePolishTests.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: PipelinePolishTests.polished, gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.absenceBegan(.screenLocked)
        await gate.open()
        await pipeline.settle()

        let id = try #require(await world.store.records.first?.id)
        #expect(await world.paster.pasted == [PipelinePolishTests.spoken])
        #expect(await world.pasteboard.text == PipelinePolishTests.polished)
        #expect(await pipeline.state == .polished(id, isReplaced: false))
    }

    @Test func nothingLiveMeansNothingChanges() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.absenceBegan(.asleep)
        await pipeline.settle()

        #expect(await world.store.records.isEmpty)
        #expect(await pipeline.state == .idle)
    }
}
