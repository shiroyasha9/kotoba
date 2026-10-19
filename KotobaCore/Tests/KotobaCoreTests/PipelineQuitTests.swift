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
        // 2026-10-17). The row says so, and Paste Last finds it at the next launch.
        #expect(record.status == .notPasted)
        #expect(await world.paster.pasteCount == 0)
        #expect(await world.pasteboard.text == "user's clipboard")

        await world.makePipeline().pasteLast()
        #expect(await world.paster.pasted == ["almost lost"])
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
        #expect(await pipeline.retryTimer == nil)
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
        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        await gate.open()
        await quit

        // Quit waited for the send on its way: its billed answer is saved, and the next launch does not send it.
        #expect(await world.store.records.filter { $0.status == .recovered }.count == 1)
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
        world.clock.advance(by: ClipboardGuard.readSettle)
        await pipeline.settle()

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

    /// Quit returns before a clipboard restore could run, so nothing pastes from the menu once it began.
    @Test func pasteLastAndPasteAgainDoNothingOnceQuitBegan() async throws {
        let world = FakeWorld(transcript: "said")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        let id = try #require(await world.store.records.first?.id)
        let pastes = await world.paster.pasteCount

        await pipeline.shutdown()
        await pipeline.pasteLast()
        await pipeline.pasteAgain("said", of: id)
        await pipeline.polishLast()

        #expect(await world.paster.pasteCount == pastes)
    }

    /// A paste that went out before quit gets its restore before quit returns, so the owner's clipboard comes back.
    @Test func quitWaitsForTheRestoreOfAPasteThatWentOut() async {
        let world = FakeWorld(transcript: "pasted")
        let pipeline = world.makePipeline()
        await world.paster.readLater()
        await pipeline.dictate(world)

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.clipboard.isQuitWaiting })
        _ = await world.pasteboard.appReads()
        let restoreAt = world.clock.now + ClipboardGuard.readSettle
        #expect(await eventually { world.clock.deadlines.contains(restoreAt) })
        world.clock.advance(by: ClipboardGuard.readSettle)
        await quit

        #expect(await world.pasteboard.text == "user's clipboard")
    }

    @Test func quitWaitsForARestoreNoLongerThanItsBound() async {
        let world = FakeWorld(transcript: "pasted")
        let pipeline = world.makePipeline()
        await world.paster.readLater()
        await pipeline.dictate(world)

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.clipboard.isQuitWaiting })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(await world.pasteboard.text == "pasted")
    }

    @Test func quitWaitsForARetrySendNoLongerThanItsBound() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)
        async let run: Void = pipeline.retryPending()
        #expect(await eventually { await gate.hasWaiters })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        world.clock.advance(by: DictationPipeline.quitWait)
        await quit

        #expect(try #require(await world.store.records.first).status == .failed)
        await gate.open()
        await run
    }

    /// A retry run that waits for a live dictation to end sends nothing once quit began.
    @Test func aWaitingRetryRunSendsNothingOnceQuitBegan() async throws {
        let world = FakeWorld(transcript: "live")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.server(status: 503))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        async let run: Void = pipeline.retryPending()
        #expect(await eventually { await pipeline.quietWaiters.count == 1 })

        async let quit: Void = pipeline.shutdown()
        #expect(await eventually { await pipeline.quitWaiters.count == 1 })
        await gate.open()
        await quit
        await run

        #expect(await world.provider.requests.count == 2)
    }
}
