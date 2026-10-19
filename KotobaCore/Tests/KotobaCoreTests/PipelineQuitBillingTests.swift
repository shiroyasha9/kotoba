import Foundation
import Testing

@testable import KotobaCore

/// Quit waits for every billed answer on its way to reach the usage ledger, within the one bound
/// (`DictationPipeline.quitWait`): a Transcribe Again, a primer, and the segments a quit or a cancel leaves unused.
/// Billed usage that quit drops is never counted.
struct PipelineQuitBillingTests {
    @Test func quitWaitsForATranscribeAgainAnswer() async throws {
        let world = FakeWorld(transcript: "Fix the log in bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        // The paste's restore is done, so quit waits for nothing else.
        world.clock.advance(by: ClipboardPaste.readSettle)
        await pipeline.settle()
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear("Fix the login bug.")
        let gate = Gate()
        await world.provider.hold(at: gate)

        async let again = pipeline.transcribeAgain(id)
        #expect(await eventually { await gate.hasWaiters })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.waiterCount(.sendsEnded) == 1 })
        await gate.open()
        await quit

        #expect(try #require(await world.store.records.first).transcript == "Fix the login bug.")
        #expect(await world.store.ledger.filter { $0.dictation == id }.count == 2)
        #expect(await again)
    }

    @Test func quitWaitsForATranscribeAgainNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "Fix the log in bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        let gate = Gate()
        await world.provider.hold(at: gate)

        async let again = pipeline.transcribeAgain(id)
        #expect(await eventually { await gate.hasWaiters })
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.waiterCount(.sendsEnded) == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(try #require(await world.store.records.first).transcript == "Fix the log in bug.")
        await gate.open()
        _ = await again
    }

    @Test func quitWaitsForAPrimerOnItsWayAndBillsIt() async throws {
        let world = FakeWorld(transcript: "unused")
        let cost = Cost.reported(Decimal(28) / 1_000_000)
        let primer = Gate()
        await world.provider.answerPrimes(
            with: Transcript(
                text: "", usage: TranscriptionUsage(audio: .seconds(1), cost: cost), model: "fake/model-1"),
            after: primer)
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        #expect(await eventually { await primer.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.billWaiterCount == 1 })
        await primer.open()
        await quit

        let record = try #require(await world.store.records.first)
        #expect(record.status == .pending)
        #expect(await world.store.ledger.filter { $0.cost == cost }.map(\.dictation) == [record.id])
    }

    @Test func quitWaitsForAPrimerNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "unused")
        let primer = Gate()
        await world.provider.answerPrimes(
            with: Transcript(text: "", usage: TranscriptionUsage(audio: .seconds(1), cost: .reported(1)), model: "m"),
            after: primer)
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        #expect(await eventually { await primer.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.billWaiterCount == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(await world.store.ledger.isEmpty)
        await primer.open()
        await pipeline.settle()
    }

    /// Quit during the Undo window cancels the recording; the segment that answered is billed before quit returns.
    @Test func quitWaitsForTheBillOfASegmentThatAnswered() async throws {
        let fixture = SegmentFixture()
        let world = await fixture.world()
        await world.provider.answerPrimes(with: nil)
        await world.provider.charge(.reported(0.001), audio: .seconds(1))
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { !FileManager.default.fileExists(atPath: first.file.path) })
        await pipeline.handle(.escape)
        let disk = Gate()
        await world.store.holdUsage(at: disk)

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.billWaiterCount == 1 })
        await disk.open()
        await quit

        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        let billed = await world.store.ledger.filter { $0.kind == .speech && $0.dictation == record.id }
        #expect(billed.map(\.cost) == [.reported(0.001)])
    }
}
