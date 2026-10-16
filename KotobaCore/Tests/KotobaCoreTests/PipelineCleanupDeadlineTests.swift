import Foundation
import Testing

@testable import KotobaCore

/// A live cleanup has `Settings.cleanupDeadline` (5 s) on the pipeline clock: after it the raw transcript pastes and
/// the pill says so. A mode that cleans every dictation must not hold each paste for a stalled cleaner. The late answer is
/// dropped, but it was billed, so its cost goes to the ledger.
struct PipelineCleanupDeadlineTests {
    let world = FakeWorld(transcript: "raw words")
    let gate = Gate()

    var cleaner: FakeTextCleaner {
        FakeTextCleaner(result: .success("clean words"), gate: gate, cost: .reported(Decimal(string: "0.0004") ?? 0))
    }

    @Test func aCleanupPastTheDeadlinePastesTheRawTranscriptAndSaysSo() async throws {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(5))

        #expect(await eventually { await world.paster.pasted == ["raw words"] })
        let record = try #require(await world.store.records.first)
        #expect(await eventually { await pipeline.state == .cleanupTooSlow(record.id) })
        #expect(record.cleanedText == nil)
        await gate.open()
        await pipeline.settle()
        #expect(await world.paster.pasted == ["raw words"])
        #expect(try #require(await world.store.records.first).cleanedText == nil)
    }

    @Test func aLateAnswerIsDroppedButItsCostIsKept() async throws {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(5))
        #expect(await eventually { await world.paster.pasted == ["raw words"] })
        await gate.open()
        await pipeline.settle()

        let cleanup = await world.store.ledger.filter { $0.kind == .cleanup }
        #expect(cleanup.map(\.cost) == [.reported(Decimal(string: "0.0004") ?? 0)])
        #expect(cleanup.map(\.deliveredWords) == [0])
        // Dated with its transcript, 5 s before it came: a day's figures never get half a dictation.
        let speech = await world.store.ledger.filter { $0.kind == .speech }
        #expect(cleanup.map(\.time) == speech.map(\.time))
    }

    /// A cleanup row takes its transcript's time, so its word change falls on the same day as the words it changes,
    /// also when the answer comes after midnight.
    @Test func aCleanupEntryIsDatedWithItsTranscript() async throws {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(4))
        await gate.open()
        await pipeline.settle()

        let ledger = await world.store.ledger
        #expect(ledger.map(\.kind) == [.speech, .cleanup])
        #expect(ledger.map(\.time) == [world.clock.date - 4, world.clock.date - 4])
    }

    @Test func aCleanupBeforeTheDeadlineIsPasted() async {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .milliseconds(4_900))
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted == ["clean words"])
        #expect(await pipeline.state == .idle)
    }

    /// A retry has no paste waiting on it, so its cleanup waits for the cleaner's own timeout, not the deadline.
    @Test func aRetriedCleanupWaitsPastTheDeadline() async throws {
        let pipeline = world.makePipeline(cleaner: cleaner, modes: ModeRules())
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()
        await world.provider.fail(with: nil)

        let retry = Task { await pipeline.retryPending() }
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .seconds(30))
        #expect(await world.store.records.first?.status == .failed)
        await gate.open()
        await retry.value

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.cleanedText == "clean words")
        // The retry's cleanup came 30 s after the retry's transcript, and is dated with it.
        let ledger = await world.store.ledger
        #expect(ledger.map(\.kind) == [.speech, .cleanup])
        #expect(ledger.map(\.time) == [world.clock.date - 30, world.clock.date - 30])
    }
}
