import Foundation
import Testing

@testable import KotobaCore

/// The personal dictionary in the pipeline: keyterms go with the request, find-and-replace runs
/// on the transcript before paste.
struct PipelineDictionaryTests {
    let dictionary = PersonalDictionary(
        terms: ["Claude Code", "kotoba"],
        rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")]
    )

    @Test func aRuleReplacesTheTextThatIsPastedAndStored() async throws {
        let world = FakeWorld(transcript: "open cloud code now")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(dictionary)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["open Claude Code now"])
        #expect(try #require(await world.store.records.first).transcript == "open Claude Code now")
    }

    @Test func theRequestCarriesTheKeyterms() async throws {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()
        await pipeline.updateDictionary(dictionary)

        await pipeline.dictate(world)

        #expect(try #require(await world.provider.requests.first).dictionaryTerms == dictionary.keyterms)
    }

    @Test func anUpdateAppliesToTheNextDictation() async throws {
        let world = FakeWorld(transcript: "cloud code")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        await pipeline.updateDictionary(dictionary)
        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["cloud code", "Claude Code"])
        #expect(await world.provider.requests.map(\.dictionaryTerms) == [[], dictionary.keyterms])
    }

    @Test func aRetryAppliesTheReplacementsAndSendsTheKeyterms() async throws {
        let world = FakeWorld(transcript: "fix cloud code")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await pipeline.updateDictionary(dictionary)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        #expect(try #require(await world.store.records.first).transcript == "fix Claude Code")
        #expect(await world.provider.requests.last?.dictionaryTerms == dictionary.keyterms)
    }
}
