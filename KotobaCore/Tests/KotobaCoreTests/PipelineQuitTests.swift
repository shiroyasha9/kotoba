import Foundation
import Testing

@testable import KotobaCore

/// Quit while a dictation is being sent waits a little for its answer (`DictationPipeline.quitWait`), so the billed
/// text is saved and the next launch does not send it again.
struct PipelineQuitTests {
    @Test func quitWaitsForTheAnswerOfADictationInFlight() async throws {
        let world = FakeWorld(transcript: "almost lost")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        await gate.open()
        await quit

        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "almost lost")
        // Quit returns before a restore could run: the text is not pasted and the clipboard is left alone (lead,
        // 2026-10-17). Paste Last finds it at the next launch.
        #expect(record.status == .copied)
        #expect(await world.paster.pasteCount == 0)
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    /// Nothing new is sent once quit began: what is sent now could be billed now and again at the next launch.
    @Test func aDictationThatAnswersDuringQuitSendsNoQueuedOne() async throws {
        let world = FakeWorld(transcript: "second")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        await gate.open()
        await quit
        await pipeline.settle()

        #expect(await world.provider.requests.count == 2)
    }

    @Test func quitCancelsTheRunTheRouteAskedFor() async {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rateLimited(retryAfter: .seconds(30)))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        await pipeline.shutdown()
        world.clock.advance(by: .seconds(30))
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
    }

    @Test func aRetryRunSendsNoMoreOnceQuitBegan() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)

        async let run: Void = pipeline.retryPending()
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.shutdown()
        await gate.open()
        await run

        #expect(await world.provider.requests.count == 3)
    }

    @Test func noRecordingStartsOnceQuitBegan() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.shutdown()
        await pipeline.tap(world)

        #expect(await pipeline.state == .idle)
        #expect(await world.audio.files.isEmpty)
    }

    @Test func quitWaitsNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "never came")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(try #require(await world.store.records.first).status == .pending)
        await gate.open()
        await pipeline.settle()
    }

    @Test func quitWithNothingInFlightReturnsAtOnce() async {
        let world = FakeWorld(transcript: "done")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)

        await pipeline.shutdown()

        #expect(await world.store.records.map(\.status) == [.pasted])
    }

    /// Quit before the first buffer: no row of 0 s for the next launch to send, and no file.
    @Test func quitBeforeAnyAudioKeepsNoRow() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await world.audio.record(.zero)
        await pipeline.tap(world)

        await pipeline.shutdown()

        #expect(await world.store.records.isEmpty)
        #expect(await world.audio.discarded == (await world.audio.files))
    }
}
