import Foundation
import Testing

@testable import KotobaCore

/// Cleanup or plain is decided when the dictation is announced (tap release or hold threshold):
/// cleanup if the cleanup modifier was down at any moment since chord-down. A Hyper key presses
/// all four modifiers at once in any order, so the order of the keys must not matter.
struct PipelineCleanupModeTests {
    let world = FakeWorld(transcript: "raw words")
    let cleaner = FakeTextCleaner(result: .success("clean words"))

    @Test func theModifierAtChordDownMakesACleanupDictation() async {
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.cleanupModifier)
        await pipeline.handle(.chordUp)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["clean words"])
    }

    @Test func theModifierReleasedBeforeTheDecisionStillCounts() async {
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.cleanupModifier)
        world.clock.advance(by: .milliseconds(500))
        await pipeline.settle()
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["clean words"])
    }

    @Test func theModifierAfterTheCueIsIgnored() async {
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.tap(world)
        await pipeline.handle(.cleanupModifier)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["raw words"])
        #expect(await cleaner.requests.isEmpty)
    }

    @Test func theModifierAfterTheHoldThresholdIsIgnored() async {
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()
        await pipeline.handle(.cleanupModifier)
        world.clock.advance(by: .milliseconds(100))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["raw words"])
    }

    @Test func theCleanerWarmsWhenTheModifierIsSeen() async {
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.settle()
        #expect(await cleaner.warmUps == 0)
        await pipeline.handle(.cleanupModifier)
        await pipeline.settle()

        #expect(await cleaner.warmUps == 1)
    }

    @Test func aRetriedCleanupDictationIsCleaned() async throws {
        let pipeline = world.makePipeline(cleaner: cleaner)
        await world.provider.fail(with: ProviderError.offline)

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.cleanupModifier)
        await pipeline.handle(.chordUp)
        await pipeline.tap(world)
        await pipeline.settle()
        #expect(try #require(await world.store.records.first).output == .cleanup(.code))

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "raw words")
        #expect(record.cleanedText == "clean words")
        let item = try #require(await pipeline.retries.recovered().first)
        await pipeline.retries.copy(item)
        #expect(await world.pasteboard.text == "clean words")
    }
}
