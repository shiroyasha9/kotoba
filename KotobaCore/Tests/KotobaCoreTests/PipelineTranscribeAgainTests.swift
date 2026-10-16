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
    @Test func theLedgerCountsTheDictationOnceAndItsWordsAsTheNewText() async throws {
        let world = FakeWorld(transcript: "Fix the log in bug.")
        await world.provider.charge(.reported(Decimal(5) / 100_000), audio: .seconds(2))
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear("Fix the login bug.")

        #expect(await pipeline.transcribeAgain(id))

        let entries = await world.store.ledger.filter { $0.dictation == id }
        let again = try #require(entries.last)
        #expect(entries.count == 2)
        #expect(entries.map(\.deliveredWords).reduce(0, +) == 4)
        #expect(entries.map(\.spokenWords).reduce(0, +) == 5)
        #expect(entries.filter { $0.spokenWords > 0 }.count == 1)
        #expect(again.deliveredWords == -1)
        #expect(again.spokenWords == 0)
        #expect(again.audio == .seconds(2))
        #expect(again.cost == .reported(Decimal(5) / 100_000))
    }

    @Test func aFailedRequestBillsNoWords() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear(" ")

        #expect(await pipeline.transcribeAgain(id) == false)

        let again = try #require(await world.store.ledger.filter { $0.dictation == id }.last)
        #expect(again.deliveredWords == 0)
        #expect(again.spokenWords == 0)
    }

    @Test func aCleanupMissKeepsTheRowAndBillsTheSpeechAnswer() async throws {
        let world = FakeWorld(transcript: "um open the off dot ts file")
        let cleaner = FakeTextCleaner(result: .failure(FakeError()))
        let pipeline = world.makePipeline(cleaner: cleaner)
        var record = PipelinePasteAgainTests.record("um open the auth dot ts file", at: 1_000, .pasted)
        record.output = .cleanup(.code)
        record.cleanedText = "Open the auth.ts file."
        try await world.store.save(record)

        #expect(await pipeline.transcribeAgain(record.id) == false)

        let stored = try #require(await world.store.records.first)
        #expect(stored.transcript == "um open the auth dot ts file")
        #expect(stored.cleanedText == "Open the auth.ts file.")
        let entries = await world.store.ledger.filter { $0.dictation == record.id }
        // The cleaner gave no answer, so only the speech answer was billed.
        #expect(entries.map(\.kind) == [.speech])
        #expect(entries.allSatisfy { $0.deliveredWords == 0 && $0.spokenWords == 0 })
    }

    @Test func aCleanupDictationsLedgerAddsUpToItsNewText() async throws {
        let world = FakeWorld(transcript: "um open the auth dot ts file")
        let cleaner = FakeTextCleaner(result: .success("Open the auth.ts file now."))
        let pipeline = world.makePipeline(cleaner: cleaner)
        var record = PipelinePasteAgainTests.record("um open the auth dot ts file", at: 1_000, .pasted)
        record.output = .cleanup(.code)
        record.cleanedText = "Open the auth.ts file."
        record.usage = [
            UsageEntry(
                time: record.createdAt, dictation: record.id, kind: .speech, model: "fake/model-1",
                deliveredWords: 7, spokenWords: 7, cost: nil),
            UsageEntry(
                time: record.createdAt, dictation: record.id, kind: .cleanup, model: "fake/cleaner",
                deliveredWords: -3, cost: nil),
        ]
        try await world.store.save(record)

        #expect(await pipeline.transcribeAgain(record.id))

        let entries = await world.store.ledger.filter { $0.dictation == record.id }
        #expect(entries.map(\.deliveredWords).reduce(0, +) == 5)
        #expect(entries.map(\.spokenWords).reduce(0, +) == 7)
    }

    @Test func aSecondCallForTheSameRowIsRefusedAndTheRowIsPublished() async throws {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        let gate = Gate()
        await world.provider.hold(at: gate)

        let first = Task { await pipeline.transcribeAgain(id) }
        #expect(await eventually { await gate.hasWaiters })
        #expect(await pipeline.lastActivity.transcribingAgain == [id])
        #expect(await pipeline.lastActivity.isQuiet)
        #expect(await pipeline.transcribeAgain(id) == false)
        await gate.open()

        #expect(await first.value)
        #expect(await pipeline.lastActivity.transcribingAgain == [])
        #expect(await world.provider.requests.count == 2)
    }
}
