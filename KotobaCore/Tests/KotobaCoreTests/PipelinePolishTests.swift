import Foundation
import Testing

@testable import KotobaCore

/// Polish (docs/spec.md, "Polish and View Changes"): the last dictation rewritten on request, pasted over the old text
/// when the selector finds it, billed with no words, and never pasted in part.
struct PipelinePolishTests {
    static let spoken = "Okay so fix the, the login bug in auth.ts."
    static let polished = "Fix the login bug in auth.ts."

    @Test func polishReplacesTheLastDictationAndKeepsBothTexts() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: Self.polished, cost: .reported(Decimal(4) / 10_000))
        let selector = FakeSelector(finds: true)
        let pipeline = world.makePipeline(polisher: polisher, selector: selector)
        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        await pipeline.handle(.polishLast)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(await polisher.texts == [Self.spoken])
        #expect(await selector.requests == [Self.spoken])
        #expect(await world.paster.pasted == [Self.spoken, Self.polished])
        #expect(await pipeline.state == .polished(record.id, isReplaced: true))
        #expect(record.transcript == Self.spoken)
        #expect(record.polishedText == Self.polished)
        #expect(record.latestText == Self.polished)
        let entry = try #require(await world.store.ledger.last)
        #expect(entry.kind == .polish)
        #expect(entry.dictation == record.id)
        #expect(entry.deliveredWords == 0 && entry.spokenWords == 0 && entry.audio == .zero)
        #expect(entry.cost == .reported(Decimal(4) / 10_000))

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    @Test func aCutAnswerPastesNothingAndIsBilled() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: "Fix the", cost: .reported(1), isComplete: false)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await world.paster.pasted == [Self.spoken])
        #expect(await pipeline.state == .polishFailed(.cutOff))
        #expect(try #require(await world.store.records.first).polishedText == nil)
        #expect(await world.store.ledger.contains { $0.kind == .polish && $0.cost == .reported(1) })
    }

    @Test func aLateAnswerPastesNothingAndIsBilledWhenItComes() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: Self.polished, cost: .reported(1), gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        #expect(await pipeline.state == .polishing)
        world.clock.advance(by: .seconds(10))
        #expect(await eventually { await pipeline.state == .polishFailed(.tooSlow) })
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted == [Self.spoken])
        #expect(try #require(await world.store.records.first).polishedText == nil)
        #expect(await world.store.ledger.contains { $0.kind == .polish && $0.deliveredWords == 0 })
    }

    @Test(arguments: [
        (ProviderError.auth(status: 401), PolishFailure.needsSetup(.key)),
        (.noCredit, .needsSetup(.credit)),
        (.offline, .failed),
        (.rejected(status: 400, message: "no"), .failed),
    ])
    func aFailedRequestSaysWhyAndChangesNothing(_ error: ProviderError, _ failure: PolishFailure) async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let pipeline = world.makePipeline(polisher: FakePolisher(error: error), selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await pipeline.state == .polishFailed(failure))
        #expect(await world.paster.pasted == [Self.spoken])
        #expect(try #require(await world.store.records.first).polishedText == nil)
    }

    @Test func anEmptyAnswerFails() async {
        let world = FakeWorld(transcript: Self.spoken)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: "  \n"), selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.polishLast()

        #expect(await pipeline.state == .polishFailed(.failed))
        #expect(await world.paster.pasted == [Self.spoken])
    }

    @Test func withNoDictationThereIsNothingToPolish() async {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: Self.polished)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))

        await pipeline.polishLast()

        #expect(await pipeline.state == .polishFailed(.nothingToPolish))
        #expect(await polisher.texts.isEmpty)
    }

    @Test func duringARecordingPolishDoesNothing() async {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: Self.polished)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        await pipeline.tap(world)

        await pipeline.polishLast()

        #expect(await polisher.texts.isEmpty)
        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aDictationThatStartsDuringTheRequestWins() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let selector = FakeSelector(finds: true)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: Self.polished, gate: gate), selector: selector)
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.tap(world)
        await gate.open()
        #expect(await eventually { await !pipeline.isPolishing })

        #expect(await world.paster.pasted == [Self.spoken])
        #expect(await selector.requests.isEmpty)
        #expect(await pipeline.state == .recording(isLong: false))
        #expect(try #require(await world.store.records.first).polishedText == Self.polished)
    }

    /// The selection takes its time too: a dictation that starts meanwhile gets the old selection back, not a field
    /// whose text a ⌘V or a key would replace.
    @Test func aDictationDuringTheSelectionGetsTheOldSelectionBack() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let selector = FakeSelector(answer: .selected, gate: gate)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: Self.polished), selector: selector)
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.tap(world)
        await gate.open()
        #expect(await eventually { await !pipeline.isPolishing })

        #expect(await selector.restores == 1)
        #expect(await world.paster.pasted == [Self.spoken])
        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func aDictationPastedDuringTheRequestWins() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let selector = FakeSelector(finds: true)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: Self.polished, gate: gate), selector: selector)
        await pipeline.dictate(world)
        let first = try #require(await world.store.records.first?.id)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        await world.provider.hear("Ship it.")
        world.clock.advance(by: .seconds(2))
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await world.paster.pasted.count == 2 })
        await gate.open()
        #expect(await eventually { await !pipeline.isPolishing })
        await pipeline.settle()

        #expect(await world.paster.pasted == [Self.spoken, "Ship it."])
        #expect(await selector.requests.isEmpty)
        #expect(await world.store.records.first { $0.id == first }?.polishedText == Self.polished)
        #expect(await pipeline.state == .idle)
    }

    @Test func polishAndTranscribeAgainNeverOverlap() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let polisher = FakePolisher(answer: Self.polished, gate: gate)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        #expect(await pipeline.transcribeAgain(id) == false)
        await gate.open()
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).transcript == Self.spoken)
    }

    @Test func undoAfterASecondPolishBringsBackTheFirst() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: Self.polished)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        await pipeline.polishLast()
        await polisher.answer("Fix the auth.ts login bug.")
        await pipeline.polishLast()
        let id = try #require(await world.store.records.first?.id)

        await pipeline.undoPolish(id)

        #expect(await world.paster.pasted.last == Self.polished)
        #expect(try #require(await world.store.records.first).polishedText == Self.polished)
    }

    @Test func anotherAppInFrontGetsNoPasteAndTheTextIsCopied() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let gate = Gate()
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished, gate: gate), selector: FakeSelector(finds: true))
        await pipeline.dictate(world)

        await pipeline.handle(.polishLast)
        #expect(await eventually { await gate.hasWaiters })
        world.frontApp.activate(200)
        await gate.open()
        await pipeline.settle()

        let id = try #require(await world.store.records.first?.id)
        #expect(await world.paster.pasted == [Self.spoken])
        #expect(await world.pasteboard.text == Self.polished)
        #expect(await pipeline.state == .polished(id, isReplaced: false))
    }

    @Test func lastDictationActionsAndTheNextPolishUseThePolishedText() async {
        let world = FakeWorld(transcript: Self.spoken)
        let polisher = FakePolisher(answer: Self.polished)
        let pipeline = world.makePipeline(polisher: polisher, selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        await pipeline.polishLast()
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        await pipeline.handle(.pasteLast)
        await pipeline.settle()
        await pipeline.polishLast()

        #expect(await world.paster.pasted == [Self.spoken, Self.polished, Self.polished, Self.polished])
        #expect(await polisher.texts == [Self.spoken, Self.polished])
    }

    @Test func undoSelectsThePolishedTextAndPastesTheOldOne() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let selector = FakeSelector(finds: true)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: Self.polished), selector: selector)
        await pipeline.dictate(world)
        await pipeline.polishLast()
        let id = try #require(await world.store.records.first?.id)

        await pipeline.undoPolish(id)

        #expect(await selector.requests == [Self.spoken, Self.polished])
        #expect(await world.paster.pasted == [Self.spoken, Self.polished, Self.spoken])
        #expect(try #require(await world.store.records.first).polishedText == nil)
        #expect(await pipeline.state == .idle)
    }

    @Test func undoWhenThePolishedTextChangedCopiesTheOldText() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let selector = FakeSelector(finds: true)
        let pipeline = world.makePipeline(polisher: FakePolisher(answer: Self.polished), selector: selector)
        await pipeline.dictate(world)
        await pipeline.polishLast()
        let id = try #require(await world.store.records.first?.id)
        await selector.setFinds(false)

        await pipeline.undoPolish(id)

        #expect(await world.paster.pasted == [Self.spoken, Self.polished])
        #expect(await world.pasteboard.text == Self.spoken)
        #expect(await pipeline.state == .copied(id))
        #expect(try #require(await world.store.records.first).polishedText == nil)
    }

    @Test func transcribeAgainDropsThePolishedText() async throws {
        let world = FakeWorld(transcript: Self.spoken)
        let pipeline = world.makePipeline(
            polisher: FakePolisher(answer: Self.polished), selector: FakeSelector(finds: true))
        await pipeline.dictate(world)
        await pipeline.polishLast()
        let id = try #require(await world.store.records.first?.id)
        await world.provider.hear("Fix the login bug in auth.ts, please.")

        #expect(await pipeline.transcribeAgain(id))

        let record = try #require(await world.store.records.first)
        #expect(record.polishedText == nil)
        #expect(record.latestText == "Fix the login bug in auth.ts, please.")
    }
}

// MARK: - Fakes

actor FakePolisher: TextPolisher {
    private var result: Result<String, any Error>
    private let cost: Cost?
    private let isComplete: Bool
    private let gate: Gate?
    private(set) var texts: [String] = []

    init(answer: String, cost: Cost? = nil, isComplete: Bool = true, gate: Gate? = nil) {
        result = .success(answer)
        self.cost = cost
        self.isComplete = isComplete
        self.gate = gate
    }

    init(error: any Error) {
        result = .failure(error)
        cost = nil
        isComplete = true
        gate = nil
    }

    func answer(_ text: String) {
        result = .success(text)
    }

    func polish(_ text: String) async throws -> RewrittenText {
        texts.append(text)
        await gate?.pass()
        return RewrittenText(text: try result.get(), model: "fake/polisher", cost: cost, isComplete: isComplete)
    }
}

/// Finds every text asked for, or none.
actor FakeSelector: PastedTextSelector {
    private var answer: SelectionResult
    private let gate: Gate?
    private(set) var requests: [String] = []
    /// How many times the pipeline asked for the old selection back.
    private(set) var restores = 0

    init(answer: SelectionResult = .untouched, gate: Gate? = nil) {
        self.answer = answer
        self.gate = gate
    }

    /// Finds every text asked for (`.selected`), or none (`.untouched`).
    init(finds: Bool) {
        self.init(answer: finds ? .selected : .untouched)
    }

    func setFinds(_ finds: Bool) {
        answer = finds ? .selected : .untouched
    }

    func select(_ text: String, in app: DictationApp?) async -> SelectionResult {
        requests.append(text)
        await gate?.pass()
        return answer
    }

    func restoreSelection() async {
        restores += 1
    }
}

extension FakeWorld {
    func makePipeline(
        polisher: any TextPolisher, selector: any PastedTextSelector, input: FakeInput? = nil
    ) -> DictationPipeline {
        DictationPipeline(
            ports: .init(
                audio: audio, provider: provider, paster: paster, pasteboard: pasteboard, clock: clock, store: store,
                frontApp: { [frontApp] in frontApp.current }, polisher: polisher, selector: selector,
                inputMark: { input?.current }),
            settings: .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests"), noSoundWarning: .seconds(3_600))
        )
    }
}
