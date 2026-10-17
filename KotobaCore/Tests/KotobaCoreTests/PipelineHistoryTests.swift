import Foundation
import Testing

@testable import KotobaCore

/// What the History pane reads and does: each dictation keeps the app it went to, and Retry sends one dictation.
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

        // The next launch: a quitting pipeline sends nothing.
        await world.makePipeline().retry([cancelled.id])

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "said after all")
        #expect(await world.store.history[record.id] == [.cancelled, .failed, .recovered])
    }

    @Test func twoHistoryRetriesDuringARunJoin() {
        let first = DictationID()
        let second = DictationID()

        #expect(RetrySelection.only([first]).merged(with: .only([second])) == .only([first, second]))
    }

    @Test func aHistoryRetryJoinedWithANetworkRetryStillLeavesTheOthersThatWaitForAKey() {
        func record(_ id: DictationID, waitsForKey: Bool) -> DictationRecord {
            var record = DictationRecord(
                id: id, createdAt: .now, audio: RecordedAudio(file: URL(filePath: "/tmp/a.flac"), duration: .zero),
                transcript: nil, status: .failed, latency: LatencyLog())
            record.needsSetup = waitsForKey ? .key : nil
            return record
        }
        let chosen = DictationID()
        let merged = RetrySelection.only([chosen]).merged(with: .exceptNeedsSetup)

        #expect(merged.includes(record(chosen, waitsForKey: true)))
        #expect(merged.includes(record(DictationID(), waitsForKey: false)))
        #expect(!merged.includes(record(DictationID(), waitsForKey: true)))
        #expect(RetrySelection.exceptNeedsSetup.merged(with: .onlyNeedsSetup) == .all)
    }
}

/// Delete and the change stream: what an open History pane relies on.
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
        _ = await pipeline.delete([id])
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

        _ = await pipeline.delete([id])
        await gate.open()
        await pipeline.settle()

        #expect(await world.store.records.map(\.status) == [.pasted])
    }

    @Test func theActivityNamesEachDictationInFlightUntilItEnds() async throws {
        let world = FakeWorld(transcript: "sending")
        let pipeline = world.makePipeline()
        var activity = pipeline.activity.makeAsyncIterator()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        let id = try #require(await world.store.records.first?.id)

        #expect(await activity.next() == PipelineActivity(isQuiet: false, inFlight: [id]))
        await gate.open()
        await pipeline.settle()
        #expect(await activity.next() == PipelineActivity(isQuiet: true, inFlight: []))
    }

    @Test func aDictationThatEndsWhileAnotherIsSentLeavesTheActivity() async throws {
        let world = FakeWorld(transcript: "two at once")
        let pipeline = world.makePipeline()
        var activity = pipeline.activity.makeAsyncIterator()
        let first = Gate()
        await world.provider.hold(at: first)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await first.hasWaiters })
        let second = Gate()
        await world.provider.hold(at: second)
        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await second.hasWaiters })
        let ids = await world.store.records.map(\.id)
        try #require(ids.count == 2)

        await first.open()

        // The state stays "transcribing" for the second one, but the first one leaves the activity. Only the newest
        // value is kept, so older ones may come first.
        var latest = await activity.next()
        while latest?.inFlight.count == 2 {
            latest = await activity.next()
        }
        #expect(latest == PipelineActivity(isQuiet: false, inFlight: [ids[1]]))
        #expect(await pipeline.state == .transcribing)
        await second.open()
        await pipeline.settle()
    }

    @Test func eachChangeNamesItsDictation() async throws {
        let world = FakeWorld(transcript: "named")
        let pipeline = world.makePipeline()
        var changes = pipeline.historyChanges.makeAsyncIterator()

        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        _ = await pipeline.delete([id])

        // Saved pending at the stop, saved pasted with its answer's ledger entry, then deleted.
        #expect(await changes.next() == .saved(id, isUsageAdded: false))
        #expect(await changes.next() == .saved(id, isUsageAdded: true))
        #expect(await changes.next() == .deleted([id]))
    }

    /// No answer was billed, so the Usage and Insights panes have nothing to read again.
    @Test func aDictationWithNoAnswerAddsNoUsage() async throws {
        let world = FakeWorld(transcript: "offline")
        let pipeline = world.makePipeline()
        var changes = pipeline.historyChanges.makeAsyncIterator()
        await world.provider.fail(with: FakeError())

        await pipeline.dictate(world)

        let id = try #require(await world.store.records.first?.id)
        #expect(await changes.next() == .saved(id, isUsageAdded: false))
        #expect(await changes.next() == .saved(id, isUsageAdded: false))
    }

    /// The store keeps the billed answer of a retry whose row was deleted during it, so the ledger changed.
    @Test func aRetryOfADeletedDictationAnnouncesItsUsage() async throws {
        let world = FakeWorld(transcript: "too late")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.fail(with: nil)
        let gate = Gate()
        await world.provider.hold(at: gate)
        var changes = pipeline.historyChanges.makeAsyncIterator()
        // The two saves of the failed dictation.
        _ = await changes.next()
        _ = await changes.next()

        let retry = Task { await pipeline.retry([id]) }
        #expect(await eventually { await gate.hasWaiters })
        _ = await pipeline.delete([id])
        await gate.open()
        await retry.value

        #expect(await changes.next() == .deleted([id]))
        #expect(await changes.next() == .usageAdded)
        #expect(await world.store.ledger.count == 1)
    }

    /// A failed dictation is in the queue already: Retry writes no queue change, so it announces none.
    @Test func aRetryAnnouncesOnlyTheWritesItMade() async throws {
        let world = FakeWorld(transcript: "second try")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        let id = try #require(await world.store.records.first?.id)
        await world.provider.fail(with: nil)
        var changes = pipeline.historyChanges.makeAsyncIterator()
        _ = await changes.next()
        _ = await changes.next()

        await pipeline.retry([id])

        #expect(await changes.next() == .saved(id, isUsageAdded: true))
    }

    @Test func aRetryOfACancelledDictationAnnouncesItsQueueWrite() async throws {
        let world = FakeWorld(transcript: "after all")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()
        let id = try #require(await world.store.records.first?.id)
        var changes = pipeline.historyChanges.makeAsyncIterator()
        _ = await changes.next()

        await pipeline.retry([id])

        #expect(await changes.next() == .saved(id, isUsageAdded: false))
        #expect(await changes.next() == .saved(id, isUsageAdded: true))
    }

    /// Home and the menu's counts read the rows; the History section of General measures the kept audio.
    @Test func eachChangeSaysWhatItChanged() {
        let id = DictationID()
        let changes: [HistoryChange] = [
            .saved(id, isUsageAdded: false), .saved(id, isUsageAdded: true), .deleted([id]), .audioDeleted([id]),
            .usageAdded,
        ]

        #expect(changes.map(\.isRowChanged) == [true, true, true, false, false])
        #expect(changes.map(\.isKeptAudioChanged) == [true, true, true, true, false])
    }

    @Test func onlyLedgerWritesAddUsage() {
        let id = DictationID()

        #expect(HistoryChange.saved(id, isUsageAdded: true).isUsageAdded)
        #expect(HistoryChange.usageAdded.isUsageAdded)
        #expect(!HistoryChange.saved(id, isUsageAdded: false).isUsageAdded)
        #expect(!HistoryChange.deleted([id]).isUsageAdded)
        #expect(!HistoryChange.audioDeleted([id]).isUsageAdded)
    }

    @Test func aFailedDeleteAnnouncesNothingAndSaysSo() async throws {
        let world = FakeWorld(transcript: "kept")
        let pipeline = world.makePipeline()
        var changes = pipeline.historyChanges.makeAsyncIterator()
        await world.store.failDeletes(with: FakeError())

        #expect(await !pipeline.delete([DictationID()]))
        await pipeline.dictate(world)

        let id = try #require(await world.store.records.first?.id)
        #expect(await changes.next() == .saved(id, isUsageAdded: false))
    }

    /// A dictation whose audio file cannot be removed stays, so it never leaves audio with no row; the window keeps its
    /// row and says so.
    @Test func aDeleteThatKeepsADictationAnnouncesOnlyTheRestAndSaysSo() async throws {
        let world = FakeWorld(transcript: "two")
        let pipeline = world.makePipeline()
        var changes = pipeline.historyChanges.makeAsyncIterator()
        await pipeline.dictate(world)
        await pipeline.dictate(world)
        let ids = await world.store.records.map(\.id)
        try #require(ids.count == 2)
        await world.store.keepAudio(of: [ids[0]])

        #expect(await !pipeline.delete(Set(ids)))

        #expect(await world.store.records.map(\.id) == [ids[0]])
        // Each dictation was saved twice: pending at the stop, then pasted.
        for _ in 0..<4 {
            _ = await changes.next()
        }
        #expect(await changes.next() == .deleted([ids[1]]))
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
