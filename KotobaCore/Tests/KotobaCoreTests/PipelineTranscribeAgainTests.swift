import Foundation
import Testing

@testable import KotobaCore

/// History's "Transcribe Again": a dictation that has its text sends its kept audio again, with the current speech
/// model or another one, and keeps the new text. Nothing is pasted or copied, and a miss keeps the old text.
struct PipelineTranscribeAgainTests {
    @Test func theNewTextReplacesTheOldWithNoPasteAndNoClipboardChange() async throws {
        let world = FakeWorld(transcript: "Fix the log in bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear("Fix the login bug.")

        #expect(await pipeline.transcribeAgain(id))
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "Fix the login bug.")
        #expect(record.status == .pasted)
        #expect(await world.paster.pasted == ["Fix the log in bug."])
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.state == .idle)
    }

    @Test func anotherModelGoesWithTheRequestAndItsAnswerIsBilled() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)

        #expect(await pipeline.transcribeAgain(id, model: "x-ai/grok-stt-1.0"))

        #expect(await world.provider.requests.map(\.model) == [nil, "x-ai/grok-stt-1.0"])
        #expect(await world.store.ledger.filter { $0.dictation == id }.count == 2)
    }

    @Test func aFailedRequestKeepsTheTextAndShowsNoError() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.fail(with: FakeError())

        #expect(await pipeline.transcribeAgain(id) == false)

        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "Fix the login bug.")
        #expect(record.status == .pasted)
        #expect(await pipeline.state == .idle)
    }

    @Test func anAnswerWithNoWordsKeepsTheTextAndIsBilled() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear(" ")

        #expect(await pipeline.transcribeAgain(id) == false)

        #expect(await world.store.records.first?.transcript == "Fix the login bug.")
        #expect(await world.store.ledger.filter { $0.dictation == id }.count == 2)
    }

    @Test func aDictationWhoseAudioWasDeletedSendsNothing() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        var record = PipelinePasteAgainTests.record("Fix the login bug.", at: 1_000, .pasted)
        record.isAudioDeleted = true
        try await world.store.save(record)

        #expect(await pipeline.transcribeAgain(record.id) == false)

        #expect(await world.provider.requests.isEmpty)
    }

    @Test func aDictationWithNoTextIsLeftToRetry() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        try await world.store.save(PipelinePasteAgainTests.record("", at: 1_000, .failed))
        let id = try #require(await world.store.records.first?.id)

        #expect(await pipeline.transcribeAgain(id) == false)

        #expect(await world.provider.requests.isEmpty)
        #expect(await world.store.records.first?.status == .failed)
    }

    @Test func aCleanupDictationIsCleanedAgain() async throws {
        let world = FakeWorld(transcript: "um open the auth dot ts file")
        let cleaner = FakeTextCleaner(result: .success("Open the auth.ts file."))
        let pipeline = world.makePipeline(cleaner: cleaner, dictionary: PersonalDictionary())
        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear("um open the off dot ts file")

        #expect(await pipeline.transcribeAgain(id))

        #expect(await cleaner.requests.map(\.transcript).last == "um open the off dot ts file")
        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "um open the off dot ts file")
        #expect(record.cleanedText == "Open the auth.ts file.")
    }

    @Test func theLatencyMarksStay() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let before = try #require(await world.store.records.first)

        #expect(await pipeline.transcribeAgain(before.id))

        #expect(await world.store.records.first?.latency == before.latency)
    }
}
