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
}
