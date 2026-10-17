import Foundation
import Testing

@testable import KotobaCore

/// Spoken line breaks in the pipeline: off by default; on, the stored and pasted text has the breaks, the cleaner gets
/// them, and a break is text in the paste, never a Return.
struct PipelineLineBreakTests {
    @Test func offByDefaultPastesTheWords() async {
        let world = FakeWorld(transcript: "First point. New line. Second point.")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["First point. New line. Second point."])
    }

    @Test func onPastesAndKeepsTheBreaksWithNoReturn() async throws {
        let world = FakeWorld(transcript: "First point. New line. Second point. New paragraph. Third.")
        let pipeline = world.makePipeline()
        await pipeline.updateLineBreakPhrase(isOn: true)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["First point.\nSecond point.\n\nThird."])
        #expect(await world.paster.keystrokes == [.commandV])
        // History, Paste Last and Copy Last give the text that was pasted.
        #expect(try #require(await world.store.records.first).transcript == "First point.\nSecond point.\n\nThird.")
    }

    /// The breaks are made before the cleanup, so the cleaner gets breaks, not words it could drop.
    @Test func theCleanerGetsTheBreaks() async {
        let world = FakeWorld(transcript: "um first point. New line. second point.")
        let cleaner = FakeTextCleaner(result: .success("First point.\nSecond point."))
        let pipeline = world.makePipeline(cleaner: cleaner)
        await pipeline.updateLineBreakPhrase(isOn: true)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.transcript) == ["um first point.\nsecond point."])
        #expect(await world.paster.pasted == ["First point.\nSecond point."])
    }

    /// A last "new line" before the submit phrase leaves no break at the end: Return follows the text itself.
    @Test func aBreakBeforeTheSubmitPhraseIsDropped() async {
        let world = FakeWorld(transcript: "Fix the bug. New line. Press enter.")
        let pipeline = world.makePipeline()
        await pipeline.updateLineBreakPhrase(isOn: true)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["Fix the bug."])
        #expect(await world.paster.keystrokes == [.commandV, .returnKey])
    }

    /// The command is matched on what the owner said, before the replacements: a rule can neither make nor break it.
    @Test func replacementsRunAfterTheBreaks() async {
        let dictionary = PersonalDictionary(rules: [
            ReplacementRule(find: "new line", replacement: "NewLine"),
            ReplacementRule(find: "next row", replacement: "new line"),
        ])
        let world = FakeWorld(transcript: "Item one. New line. Item two, next row.")
        let pipeline = world.makePipeline(cleaner: nil, dictionary: dictionary)
        await pipeline.updateLineBreakPhrase(isOn: true)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["Item one.\nItem two, new line."])
    }

    @Test func aRetryMakesTheBreaksToo() async throws {
        let world = FakeWorld(transcript: "Line one. New line. Line two.")
        let pipeline = world.makePipeline()
        await pipeline.updateLineBreakPhrase(isOn: true)
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        #expect(try #require(await world.store.records.first).transcript == "Line one.\nLine two.")
    }
}
