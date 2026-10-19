import Foundation
import Testing

@testable import KotobaCore

/// The cleanup chord: record, transcribe, clean, paste the cleaned text. A failed cleanup pastes the raw transcript
/// and says so; the dictation is never lost.
struct PipelineCleanupTests {
    @Test func cleanupChordPastesTheCleanedText() async throws {
        let world = FakeWorld(transcript: "um open the auth dot ts file")
        let cleaner = FakeTextCleaner(result: .success("Open the auth.ts file."))
        let pipeline = world.makePipeline(cleaner: cleaner, dictionary: PersonalDictionary(terms: ["auth.ts"]))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Open the auth.ts file."])
        #expect(await cleaner.requests == [.init(transcript: "um open the auth dot ts file", vocabulary: ["auth.ts"])])
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pasted)
        #expect(record.transcript == "um open the auth dot ts file")
        #expect(record.cleanedText == "Open the auth.ts file.")
        #expect(await pipeline.state == .idle)
    }

    @Test func cleanerGetsTheRawTranscriptAndReplacementsRunOnceOnTheCleanedText() async throws {
        let world = FakeWorld(transcript: "open pie torch docs")
        let cleaner = FakeTextCleaner(result: .success("Open the pie torch docs."))
        let dictionary = PersonalDictionary(rules: [ReplacementRule(find: "pie torch", replacement: "PyTorch")])
        let pipeline = world.makePipeline(cleaner: cleaner, dictionary: dictionary)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.map(\.transcript) == ["open pie torch docs"])
        #expect(await cleaner.requests.map(\.vocabulary) == [["PyTorch"]])
        #expect(await world.paster.pasted == ["Open the PyTorch docs."])
        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "open PyTorch docs")
        #expect(record.cleanedText == "Open the PyTorch docs.")
    }

    @Test func aRuleWhoseReplacementContainsItsFindTextRunsOnlyOnce() async {
        let world = FakeWorld(transcript: "open kotoba")
        let cleaner = FakeTextCleaner(result: .success("Open kotoba."))
        let dictionary = PersonalDictionary(rules: [ReplacementRule(find: "kotoba", replacement: "kotoba.app")])
        let pipeline = world.makePipeline(cleaner: cleaner, dictionary: dictionary)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Open kotoba.app."])
    }

    /// Audit #5: an answer cut at the token limit is partial, so the raw transcript pastes, and the answer is billed
    /// with no words.
    @Test func aCutCleanupPastesTheRawTranscript() async throws {
        let world = FakeWorld(transcript: "um open the auth dot ts file and then run the tests")
        let cleaner = FakeTextCleaner(
            result: .success("Open the auth.ts file and"), cost: .reported(1), isComplete: false)
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(await world.paster.pasted == ["um open the auth dot ts file and then run the tests"])
        #expect(record.cleanedText == nil)
        #expect(await pipeline.state.notice == .cleanupFailed(record.id))
        let cleanup = try #require(await world.store.ledger.first { $0.kind == .cleanup })
        #expect(cleanup.deliveredWords == 0 && cleanup.cost == .reported(1))
    }

    @Test func failedCleanupPastesTheReplacedRawTranscript() async {
        let world = FakeWorld(transcript: "open pie torch docs")
        let dictionary = PersonalDictionary(rules: [ReplacementRule(find: "pie torch", replacement: "PyTorch")])
        let pipeline = world.makePipeline(
            cleaner: FakeTextCleaner(result: .failure(ProviderError.offline)), dictionary: dictionary)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["open PyTorch docs"])
    }

    @Test func plainChordNeverCallsTheCleaner() async {
        let world = FakeWorld(transcript: "raw words")
        let cleaner = FakeTextCleaner(result: .success("cleaned"))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.dictate(world)

        #expect(await world.paster.pasted == ["raw words"])
        #expect(await cleaner.requests.isEmpty)
        #expect(await cleaner.warmUps == 0)
    }

    @Test func cleanupModifierWarmsTheCleaner() async {
        let world = FakeWorld(transcript: "raw")
        let cleaner = FakeTextCleaner(result: .success("clean"))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.cleanupModifier)
        await pipeline.settle()

        #expect(await cleaner.warmUps == 1)
    }

    @Test func failedCleanupPastesTheRawTranscriptAndSaysSo() async throws {
        let world = FakeWorld(transcript: "raw words")
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .failure(ProviderError.offline)))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["raw words"])
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pasted)
        #expect(record.cleanedText == nil)
        #expect(await pipeline.state.notice == .cleanupFailed(record.id))
    }

    @Test func cleanupChordWithoutACleanerPastesTheRawTranscriptAndSaysSo() async throws {
        let world = FakeWorld(transcript: "raw words")
        let pipeline = world.makePipeline(cleaner: nil)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["raw words"])
        let record = try #require(await world.store.records.first)
        #expect(await pipeline.state.notice == .cleanupFailed(record.id))
    }

    @Test func deniedPasteShowsCopiedEvenWhenCleanupFailed() async throws {
        let world = FakeWorld(transcript: "raw words")
        await world.paster.deny(with: FakeError())
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .failure(ProviderError.offline)))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .copied)
        #expect(await world.pasteboard.text == "raw words")
        #expect(await pipeline.state.notice == .copied(record.id))
    }

    @Test func cleanedTextIsWhatACopyLeavesOnTheClipboard() async {
        let world = FakeWorld(transcript: "raw words")
        await world.paster.deny(with: FakeError())
        let pipeline = world.makePipeline(cleaner: FakeTextCleaner(result: .success("Clean words.")))

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.pasteboard.text == "Clean words.")
    }

    @Test func failedCleanupIsNotRetried() async {
        let world = FakeWorld(transcript: "raw words")
        let cleaner = FakeTextCleaner(result: .failure(ProviderError.server(status: 503)))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()
        await pipeline.retryPending()
        await pipeline.settle()

        #expect(await cleaner.requests.count == 1)
        #expect(await world.paster.pasted == ["raw words"])
    }

    @Test func cleanupHasItsOwnLatencyMarksBetweenResponseAndPaste() async throws {
        let world = FakeWorld(transcript: "raw")
        let gate = Gate()
        let cleaner = FakeTextCleaner(result: .success("clean"), gate: gate)
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        world.clock.advance(by: .seconds(5))
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        world.clock.advance(by: .milliseconds(900))
        await gate.open()
        await pipeline.settle()

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.response] == .seconds(5))
        #expect(latency.offsets[.cleanStart] == .seconds(5))
        #expect(latency.offsets[.cleanResponse] == .milliseconds(5_900))
        #expect(latency.offsets[.pasteSent] == .milliseconds(5_900))
    }

    @Test func failedTranscriptionOfACleanupDictationIsQueuedWithoutCleaning() async throws {
        let world = FakeWorld(transcript: "raw")
        await world.provider.fail(with: ProviderError.offline)
        let cleaner = FakeTextCleaner(result: .success("clean"))
        let pipeline = world.makePipeline(cleaner: cleaner)

        await pipeline.cleanupTap()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await cleaner.requests.isEmpty)
        #expect(try #require(await world.store.records.first).status == .failed)
    }
}

// MARK: - Fakes

actor FakeTextCleaner: TextCleaner {
    struct Request: Equatable {
        var transcript: String
        var vocabulary: [String]
        var mode = AppMode.code
    }

    private let result: Result<String, any Error>
    private let gate: Gate?
    private let cost: Cost?
    private let isComplete: Bool
    private(set) var requests: [Request] = []
    private(set) var warmUps = 0

    init(result: Result<String, any Error>, gate: Gate? = nil, cost: Cost? = nil, isComplete: Bool = true) {
        self.result = result
        self.gate = gate
        self.cost = cost
        self.isComplete = isComplete
    }

    func warmUp() async {
        warmUps += 1
    }

    func clean(_ transcript: String, vocabulary: [String], mode: AppMode) async throws -> RewrittenText {
        requests.append(Request(transcript: transcript, vocabulary: vocabulary, mode: mode))
        await gate?.pass()
        return RewrittenText(text: try result.get(), model: "fake/cleaner", cost: cost, isComplete: isComplete)
    }
}

extension FakeWorld {
    func makePipeline(cleaner: (any TextCleaner)?, dictionary: PersonalDictionary = PersonalDictionary())
        -> DictationPipeline
    {
        DictationPipeline(
            ports: .init(
                audio: audio, provider: provider, paster: paster, pasteboard: pasteboard, clock: clock, store: store,
                cleaner: cleaner),
            settings: .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests"), dictionary: dictionary)
        )
    }
}

extension DictationPipeline {
    /// Cleanup chord down and up within the tap threshold.
    func cleanupTap() async {
        await handle(.chordDown(.tapOrHold))
        await handle(.cleanupModifier)
        await handle(.chordUp)
    }
}
