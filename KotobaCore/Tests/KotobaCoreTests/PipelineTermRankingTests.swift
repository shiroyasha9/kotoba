import Foundation
import Testing

@testable import KotobaCore

/// Rank and cap through the pipeline: the request sends the ranked keyterms, and each dictation with text reports what
/// it sent and which terms its text has.
struct PipelineTermRankingTests {
    /// 120 terms, over the cap of 100.
    let dictionary = PersonalDictionary(terms: (0..<120).map { "term\($0)" })

    @Test func theRequestSendsTheRanked100() async throws {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(dictionary)
        let now = world.clock.date
        let use = [
            "term119": TermUse(isPinned: true),
            "term110": TermUse(uses: 3, lastUsedAt: now),
            "term105": TermUse(addedAt: now),
        ]
        await pipeline.updateTermUse(use)

        await pipeline.dictate(world)

        let sent = try #require(await world.provider.requests.first).dictionaryTerms
        #expect(sent == TermRanking.keyterms(of: dictionary, use: use, at: now))
        #expect(sent.count == 100)
        #expect(sent.prefix(3) == ["term119", "term110", "term105"])
        #expect(Array(sent.dropFirst(3)) == (0..<97).map { "term\($0)" })
    }

    @Test func theCleanerGetsTheSameRanked100() async throws {
        let world = FakeWorld(transcript: "hello")
        let cleaner = FakeTextCleaner(result: .success("Hello."))
        let pipeline = world.makePipeline(cleaner: cleaner, dictionary: dictionary)
        await pipeline.updateTermUse(["term119": TermUse(isPinned: true)])

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        let sent = try #require(await world.provider.requests.first).dictionaryTerms
        #expect(sent.first == "term119")
        #expect(await cleaner.requests.map(\.vocabulary) == [sent])
    }

    @Test func aPastedDictationReportsTheSentTermsAndItsHits() async throws {
        let world = FakeWorld(transcript: "ship term3 and term118 today")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(dictionary)
        var reports = pipeline.termReports.makeAsyncIterator()

        await pipeline.dictate(world)

        let report = try #require(await reports.next())
        #expect(report.sent == Array(dictionary.terms.prefix(100)))
        // term118 was not sent, and the text has it: it counts, so it can earn its place back.
        #expect(report.hits == ["term3", "term118"])
        #expect(report.at == world.clock.date)
    }

    @Test func aHitIsFoundAfterTheReplacements() async throws {
        let world = FakeWorld(transcript: "open cloud code")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(
            PersonalDictionary(rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")]))
        var reports = pipeline.termReports.makeAsyncIterator()

        await pipeline.dictate(world)

        #expect(try #require(await reports.next()).hits == ["Claude Code"])
    }

    @Test func aFailedDictationReportsNothingAndItsRetryReports() async throws {
        let world = FakeWorld(transcript: "term7 again")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(dictionary)
        var reports = pipeline.termReports.makeAsyncIterator()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let report = try #require(await reports.next())
        #expect(report.hits == ["term7"])
        #expect(report.sent.count == 100)
    }
}
