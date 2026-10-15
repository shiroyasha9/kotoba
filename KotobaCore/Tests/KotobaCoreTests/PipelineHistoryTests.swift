import Foundation
import Testing

@testable import KotobaCore

/// What the History window reads and does: each dictation keeps the app it went to, and Retry sends one dictation.
struct PipelineHistoryTests {

    @Test func aDictationKeepsTheAppInFrontAtTheStop() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.frontApp.activate(200)
        await pipeline.tap(world)
        world.frontApp.activate(300)
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.app == DictationApp(bundleID: "test.app200", name: "App 200"))
    }

    @Test func aCancelledDictationKeepsTheAppInFrontAtTheCancel() async throws {
        let world = FakeWorld(transcript: "never sent")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.frontApp.activate(200)
        await pipeline.handle(.escape)
        await pipeline.shutdown()
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        #expect(record.app?.bundleID == "test.app200")
    }

    @Test func anUnknownFrontAppKeepsNoApp() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        world.frontApp.activate(nil)

        await pipeline.dictate(world)

        #expect(try #require(await world.store.records.first).app == nil)
    }

    @Test func retryingOneDictationLeavesTheOthersQueued() async throws {
        let world = FakeWorld(transcript: "second try")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        await pipeline.dictate(world)
        let first = try #require(await world.store.records.first)

        await world.provider.fail(with: nil)
        await pipeline.retry([first.id])

        let statuses = await world.store.records.map { ($0.id, $0.status) }
        #expect(statuses.first { $0.0 == first.id }?.1 == .recovered)
        #expect(statuses.filter { $0.1 == .failed }.count == 1)
    }

    @Test func retryingACancelledDictationTranscribesItsAudio() async throws {
        let world = FakeWorld(transcript: "said after all")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        await pipeline.shutdown()
        let cancelled = try #require(await world.store.records.first)
        #expect(cancelled.status == .cancelled && cancelled.isRetryable)

        await pipeline.retry([cancelled.id])

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "said after all")
        #expect(await world.store.history[record.id] == [.cancelled, .failed, .recovered])
    }

    @Test func twoHistoryRetriesDuringARunJoin() {
        let first = DictationID()
        let second = DictationID()

        #expect(RetrySelection.only([first]).merged(with: .only([second])) == .only([first, second]))
        #expect(RetrySelection.only([first]).merged(with: .exceptNeedsSetup) == .all)
    }
}

/// Delete and the change stream: what an open History window relies on.
struct PipelineHistoryChangeTests {

    @Test func aDictationDeletedDuringItsRetryStaysDeleted() async throws {
        let world = FakeWorld(transcript: "too late")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)

        let retry = Task { await pipeline.retry([id]) }
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.delete([id])
        await gate.open()
        await retry.value

        #expect(await world.store.records.isEmpty)
        #expect(await pipeline.state != .recovered(id))
    }

    @Test func aDictationInFlightIsNotDeleted() async throws {
        let world = FakeWorld(transcript: "still sending")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        let id = try #require(await world.store.records.first?.id)

        await pipeline.delete([id])
        await gate.open()
        await pipeline.settle()

        #expect(await world.store.records.map(\.status) == [.pasted])
    }

    @Test func eachChangeNamesItsDictation() async throws {
        let world = FakeWorld(transcript: "named")
        let pipeline = world.makePipeline()
        var changes = pipeline.historyChanges.makeAsyncIterator()

        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await pipeline.delete([id])

        // Saved pending at the stop, saved pasted, then deleted.
        #expect(await changes.next() == .saved(id))
        #expect(await changes.next() == .saved(id))
        #expect(await changes.next() == .deleted([id]))
    }

    @Test func aRejectedDictationIsSentAgainAndCanFailAgain() async throws {
        let world = FakeWorld(transcript: "with credit")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.rejected(status: 400, message: "Unsupported audio"))
        await pipeline.dictate(world)
        let rejected = try #require(await world.store.records.first)
        #expect(rejected.status == .rejected && rejected.isRetryable)

        await world.provider.fail(with: FakeError())
        await pipeline.retry([rejected.id])
        // A retry that fails again leaves a failed dictation, which the menu's Retry counts.
        #expect(try #require(await world.store.records.first).status == .failed)

        await world.provider.fail(with: nil)
        await pipeline.retry([rejected.id])
        #expect(try #require(await world.store.records.first).status == .recovered)
    }
}
