import Foundation
import Testing

@testable import KotobaCore

/// A capture start and an Undo's resume wait for the audio source before the recording is live again. A press, an
/// Undo or quit that comes meanwhile waits for its turn (`DictationPipeline.inTurn`), so it finds the recording: it
/// never begins a second capture over the first, and quit keeps the recording.
struct PipelineCaptureTurnTests {
    @Test func aPressDuringAnUndosResumeStopsTheResumedRecording() async throws {
        let world = FakeWorld(transcript: "one recording")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let gate = Gate()
        await world.audio.holdResume(at: gate)

        async let undone: Void = pipeline.undo()
        #expect(await eventually { await gate.hasWaiters })
        async let pressed: Void = pipeline.handle(.chordDown(.tapOrHold))
        #expect(await eventually { await pipeline.turnWaiterCount == 1 })
        await gate.open()
        await undone
        await pressed
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        let files = await world.audio.files
        #expect(files.count == 1)
        #expect(await world.paster.pasted == ["one recording"])
        let records = await world.store.records
        #expect(records.map(\.audio.file) == files)
        #expect(records.map(\.status) == [.pasted])
    }

    @Test func quitDuringACaptureStartKeepsTheRecording() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.audio.holdBegin(at: gate)

        async let pressed: Void = pipeline.handle(.chordDown(.tapOrHold))
        #expect(await eventually { await gate.hasWaiters })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.turnWaiterCount == 1 })
        await gate.open()
        await pressed
        await quit

        #expect(await world.audio.isCapturing == false)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pending)
        #expect(record.audio.file == (try #require(await world.audio.files.first)))
    }

    @Test func quitDuringAnUndosResumeKeepsTheRecording() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let gate = Gate()
        await world.audio.holdResume(at: gate)

        async let undone: Void = pipeline.undo()
        #expect(await eventually { await gate.hasWaiters })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.turnWaiterCount == 1 })
        await gate.open()
        await undone
        await quit

        #expect(await world.audio.isCapturing == false)
        #expect(await world.store.records.map(\.status) == [.pending])
        #expect(await world.provider.requests.isEmpty)
    }

    /// The press waited for an Undo's resume, and quit began meanwhile: it sends nothing.
    @Test func aPressThatWaitedForItsTurnDoesNothingOnceQuitBegan() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let gate = Gate()
        await world.audio.holdResume(at: gate)

        async let undone: Void = pipeline.undo()
        #expect(await eventually { await gate.hasWaiters })
        async let pressed: Void = pipeline.handle(.chordDown(.tapOrHold))
        #expect(await eventually { await pipeline.turnWaiterCount == 1 })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.turnWaiterCount == 2 })
        await gate.open()
        await undone
        await pressed
        await quit
        await pipeline.settle()

        #expect(await world.provider.requests.isEmpty)
        #expect(await world.store.records.map(\.status) == [.pending])
    }

    /// A resume that never returns (a stuck rebuild) holds the turn: quit still returns within its bound.
    @Test func quitWaitsForAStuckResumeNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let gate = Gate()
        await world.audio.holdResume(at: gate)

        async let undone: Void = pipeline.undo()
        #expect(await eventually { await gate.hasWaiters })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.turnWaiterCount == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(await world.provider.requests.isEmpty)
        await gate.open()
        await undone
    }

    /// The end of the Undo window closes the capture in its turn; the History save comes after it, so a press then
    /// records at once.
    @Test func aPressAfterTheUndoWindowEndsDoesNotWaitForTheHistorySave() async throws {
        let world = FakeWorld(transcript: "second")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let disk = Gate()
        await world.store.holdSaves(at: disk)

        world.clock.advance(by: .seconds(5))
        #expect(await eventually { await disk.hasWaiters })
        await pipeline.handle(.chordDown(.tapOrHold))

        #expect(await world.audio.isCapturing)
        #expect(await world.audio.files.count == 2)
        await disk.open()
        await pipeline.handle(.chordUp)
        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await world.store.records.map(\.status) == [.cancelled, .pasted])
    }

    /// Quit during that save waits for it, so the cancelled recording keeps its row.
    @Test func quitDuringTheSaveAfterTheUndoWindowKeepsTheRow() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let disk = Gate()
        await world.store.holdSaves(at: disk)
        world.clock.advance(by: .seconds(5))
        #expect(await eventually { await disk.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.cancelSaveWaiterCount == 1 })
        await disk.open()
        await quit

        #expect(await world.store.records.map(\.status) == [.cancelled])
    }

    @Test func quitWaitsForTheSaveAfterTheUndoWindowNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        let disk = Gate()
        await world.store.holdSaves(at: disk)
        world.clock.advance(by: .seconds(5))
        #expect(await eventually { await disk.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.cancelSaveWaiterCount == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        await disk.open()
        await pipeline.settle()
    }
}
