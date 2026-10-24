import Foundation
import Testing

@testable import KotobaCore

/// The primer's size: silent on a warm route; on a cold one the silent primer, then the large one when it answered
/// while the recording is live (`PrimerSize`, docs/research/latency-pass.md sections 2.1 and 2.2).
struct PipelinePrimerSizeTests {
    private static let answer = Transcript(
        text: "", usage: TranscriptionUsage(audio: .seconds(1), cost: nil), model: "fake/model-1")

    /// A route that answered nothing within the warm window is cold. The silent primer goes first, as it warms most of
    /// the route within about 2 s; when it answered and the recording is still live, the large one follows for the
    /// rest. Within the window the silent one is enough, and every re-prime is silent.
    @Test func aColdRouteGetsTheSilentPrimerThenTheLargeOne() async {
        let world = FakeWorld(transcript: "cold start")
        await world.provider.answerPrimes(with: Self.answer)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .large])
        #expect(await world.provider.maxPrimesInFlight == 1)
    }

    /// A short dictation stops before the silent primer answered: the large one is not sent.
    @Test func aStopBeforeTheSilentPrimerAnsweredSendsNoLargeOne() async {
        let world = FakeWorld(transcript: "short")
        let primer = Gate()
        await world.provider.answerPrimes(with: Self.answer, after: primer)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await world.paster.pasteCount > 0 })
        await primer.open()
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent])
    }

    @Test func aFailedSilentPrimerSendsNoLargeOne() async {
        let world = FakeWorld(transcript: "unreachable")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent])
    }

    @Test func aRouteThatAnsweredWithinTheWindowGetsOnlyTheSilentPrimer() async {
        let world = FakeWorld(transcript: "warm start")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.dictate(world)
        world.clock.advance(by: interval - .seconds(1))
        await world.provider.answerPrimes(with: Self.answer)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .silent])
    }

    @Test func aPrimerAnswerAlsoKeepsTheRouteWarm() async {
        let world = FakeWorld(transcript: "cancelled")
        await world.provider.answerPrimes(with: Self.answer)
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        await pipeline.settle()
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(10))
        await pipeline.settle()
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .large, .silent])
    }

    @Test func pastTheWindowTheRouteIsColdAgain() async {
        let world = FakeWorld(transcript: "cold again")
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.dictate(world)
        world.clock.advance(by: interval + .seconds(1))
        await world.provider.answerPrimes(with: Self.answer)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .silent, .large])
    }

    @Test func aFailedTranscriptionLeavesTheRouteCold() async {
        let world = FakeWorld(transcript: "offline")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(5))
        await world.provider.answerPrimes(with: Self.answer)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .silent, .large])
    }

    @Test func rePrimesAreSilent() async {
        let world = FakeWorld(transcript: "long prompt")
        await world.provider.answerPrimes(with: Self.answer)
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: interval)
        await pipeline.settle()
        world.clock.advance(by: interval)
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .large, .silent, .silent])
    }

    /// The large primer follows only the silent one sent at the announcement: when that one fails, a later re-prime
    /// that answers sends no large one.
    @Test func aFailedFirstPrimerCancelsTheLargeOneForGood() async {
        let world = FakeWorld(transcript: "unreachable first")
        let primer = Gate()
        await world.provider.answerPrimes(with: nil, after: primer)
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await primer.open()
        await pipeline.settle()
        await world.provider.answerPrimes(with: Self.answer)
        world.clock.advance(by: interval + .seconds(1))
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .silent])
    }

    /// Esc while the silent primer is on its way: the dictation is no longer live when it answers, so no large one
    /// follows, also not after an Undo and a re-prime.
    @Test func anEscapeBeforeTheSilentAnswerCancelsTheLargeOne() async {
        let world = FakeWorld(transcript: "paused")
        let primer = Gate()
        await world.provider.answerPrimes(with: Self.answer, after: primer)
        let pipeline = world.makePipeline()
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval

        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await primer.open()
        await pipeline.settle()
        world.clock.advance(by: .seconds(2))
        await pipeline.undo()
        world.clock.advance(by: interval + .seconds(1))
        await pipeline.settle()

        #expect(await world.provider.primeSizes == [.silent, .silent])
    }
}
