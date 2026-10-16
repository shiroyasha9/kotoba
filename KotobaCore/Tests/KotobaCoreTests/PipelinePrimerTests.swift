import Foundation
import Testing

@testable import KotobaCore

/// The route's primer: one small billed request when a dictation is announced, so the answer at the stop does not pay
/// the route's cold start (`TranscriptionProvider.prime`).
struct PipelinePrimerTests {
    @Test func anAnnouncedDictationPrimesTheRouteOnce() async {
        let world = FakeWorld(transcript: "warm path")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await world.provider.primes == 1)

        await pipeline.tap(world)
        await pipeline.settle()
        #expect(await world.provider.primes == 1)
        #expect(await world.paster.pasted == ["warm path"])
    }

    @Test func aDroppedShortcutPressSendsNoPrimer() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.hold))
        world.clock.advance(by: .milliseconds(150))
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.provider.primes == 0)
    }

    @Test func aSlowPrimerNeverHoldsThePaste() async {
        let world = FakeWorld(transcript: "no wait")
        let primer = Gate()
        await world.provider.answerPrimes(with: nil, after: primer)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        let isPasted = await eventually { await world.paster.pasted == ["no wait"] }
        await primer.open()
        await pipeline.settle()

        #expect(isPasted)
    }

    /// The primer is billed, so its cost goes to the ledger with the dictation that sent it; it adds no audio and no
    /// words, so minutes and words per minute stay what the owner dictated.
    @Test func thePrimersCostGoesToTheLedgerWithNoAudioOrWords() async throws {
        let world = FakeWorld(transcript: "ship it")
        let primerCost = Cost.reported(Decimal(28) / 1_000_000)
        await world.provider.answerPrimes(
            with: Transcript(
                text: "", usage: TranscriptionUsage(audio: .seconds(1), cost: primerCost), model: "fake/model-1"))
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        let ledger = await world.store.ledger
        #expect(ledger.count == 2)
        let primerEntry = try #require(ledger.first { $0.cost == primerCost })
        #expect(primerEntry.dictation == record.id)
        #expect(primerEntry.kind == .speech)
        #expect(primerEntry.model == "fake/model-1")
        #expect(primerEntry.audio == .zero)
        #expect(primerEntry.deliveredWords == 0)
        #expect(primerEntry.spokenWords == 0)
    }

    // MARK: Long recordings

    /// The route stays warm for about 45 s after a primer (docs/research/latency-pass.md), so a live recording sends
    /// one more every `Settings.primerInterval`, and none after the stop.
    @Test func aLongRecordingSendsAnotherPrimerEachIntervalUntilTheStop() async {
        let world = FakeWorld(transcript: "a long prompt")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: interval - .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.primes == 1)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.primes == 2)
        world.clock.advance(by: interval)
        await pipeline.settle()
        #expect(await world.provider.primes == 3)

        await pipeline.tap(world)
        world.clock.advance(by: interval * 3)
        await pipeline.settle()
        #expect(await world.provider.primes == 3)
        #expect(await world.paster.pasted == ["a long prompt"])
    }

    @Test func aPrimerStillInFlightIsNotSentAgain() async {
        let world = FakeWorld(transcript: "slow route")
        let primer = Gate()
        await world.provider.answerPrimes(with: nil, after: primer)
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        world.clock.advance(by: interval)
        let isSentBeside = await eventually { await world.provider.primes > 1 }
        await primer.open()
        await pipeline.settle()

        #expect(isSentBeside == false)
        #expect(await world.provider.maxPrimesInFlight == 1)
        // The held primer's timer passed while it was on its way, so the next goes as soon as it is back.
        #expect(await world.provider.primes == 2)
    }

    @Test func escapeStopsTheRepeatedPrimers() async {
        let world = FakeWorld(transcript: "cancelled")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: interval * 2)
        await pipeline.settle()

        #expect(await world.provider.primes == 1)
    }

    @Test func undoPrimesAtOnceWhenTheLastPrimerIsOlderThanTheInterval() async {
        let world = FakeWorld(transcript: "resumed")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: interval - .seconds(1))
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(4))
        await pipeline.undo()
        await pipeline.settle()
        // The last primer is older than the interval: the next goes at the Undo.
        #expect(await world.provider.primes == 2)

        world.clock.advance(by: interval)
        await pipeline.settle()
        #expect(await world.provider.primes == 3)
    }

    @Test func aLiveRecordingArmsThePrimerTimer() async {
        let world = FakeWorld(transcript: "primed route")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval
        let start = world.clock.now

        await pipeline.tap(world)
        await pipeline.settle()

        #expect(world.clock.deadlines.contains { $0 > start && $0 <= start + interval })
    }

    /// A direct route has no primer: nothing is sent and no timer wakes during the recording.
    @Test func aRouteWithNoPrimerSendsNoneAndArmsNoTimer() async {
        let world = FakeWorld(transcript: "direct route", hasPrimer: false)
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval
        let start = world.clock.now

        await pipeline.tap(world)
        await pipeline.settle()
        #expect(!world.clock.deadlines.contains { $0 > start && $0 <= start + interval })
        world.clock.advance(by: interval * 3)
        await pipeline.settle()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primes == 0)
        #expect(await world.paster.pasted == ["direct route"])
    }

    /// Transcribe Again sends kept audio, not a new dictation: no primer and no primer timer.
    @Test func transcribeAgainSendsNoPrimer() async throws {
        let world = FakeWorld(transcript: "again")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        #expect(await pipeline.transcribeAgain(id))
        world.clock.advance(by: interval * 2)
        await pipeline.settle()

        #expect(await world.provider.primes == 1)
    }

    // MARK: Primer size

    /// A route that answered nothing within the warm window is cold: its primer is the large one. Within the window
    /// (a transcription or a primer answered) the silent one is enough, and every re-prime is silent.
    @Test func aColdRouteGetsTheLargePrimer() async {
        let world = FakeWorld(transcript: "cold start")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large])
    }

    @Test func aRouteThatAnsweredWithinTheWindowGetsTheSilentPrimer() async {
        let world = FakeWorld(transcript: "warm start")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.dictate(world)
        world.clock.advance(by: interval - .seconds(1))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large, .silent])
    }

    @Test func aPrimerAnswerAlsoKeepsTheRouteWarm() async {
        let world = FakeWorld(transcript: "cancelled")
        await world.provider.answerPrimes(
            with: Transcript(text: "", usage: TranscriptionUsage(audio: .seconds(1), cost: nil), model: "fake/model-1"))
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(10))
        await pipeline.settle()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large, .silent])
    }

    @Test func pastTheWindowTheRouteIsColdAgain() async {
        let world = FakeWorld(transcript: "cold again")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.dictate(world)
        world.clock.advance(by: interval + .seconds(1))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large, .large])
    }

    @Test func aFailedTranscriptionLeavesTheRouteCold() async {
        let world = FakeWorld(transcript: "offline")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(5))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large, .large])
    }

    @Test func rePrimesAreSilent() async {
        let world = FakeWorld(transcript: "long prompt")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: interval)
        await pipeline.settle()
        world.clock.advance(by: interval)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.large, .silent, .silent])
    }

    /// A route picked in the menu during a recording applies from the next primer: a route with none stops them.
    @Test func aSwitchToARouteWithNoPrimerStopsTheRePrimes() async {
        let world = FakeWorld(transcript: "switched")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.settle()
        world.provider.switchRoute(hasPrimer: false)
        world.clock.advance(by: interval * 3)
        await pipeline.settle()

        let now = world.clock.now
        #expect(await world.provider.primes == 1)
        #expect(!world.clock.deadlines.contains { $0 > now && $0 <= now + interval })
    }
}
