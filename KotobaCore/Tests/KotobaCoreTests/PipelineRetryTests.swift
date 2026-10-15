import Foundation
import Testing

@testable import KotobaCore

/// Audio is never lost: failed dictations stay queued and retry.
struct PipelineRetryTests {

    @Test func aFailedTranscriptionKeepsTheAudioQueued() async throws {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.audio.file == (await world.audio.files.first))
        #expect(await world.paster.pasteCount == 0)
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.state == .failed(record.id))
    }

    @Test func theAudioIsSavedBeforeTheTranscriptArrives() async throws {
        let world = FakeWorld(transcript: "slow network")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)

        await pipeline.tap(world)
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })
        #expect(await eventually { await !world.store.records.isEmpty })

        let saved = try #require(await world.store.records.first)
        #expect(saved.status == .pending)
        await gate.open()
        await pipeline.settle()
        #expect(await world.store.history[saved.id] == [.pending, .pasted])
    }

    @Test func aRetryNeverTouchesTheClipboard() async throws {
        let world = FakeWorld(transcript: "second try", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        let changeCount = await world.pasteboard.changeCount

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await world.pasteboard.changeCount == changeCount)
        #expect(await world.paster.pasteCount == 0)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "second try")
        #expect(await pipeline.state == .recovered(record.id))
    }

    @Test func recoveredTranscriptsAreListedNewestFirst() async {
        let world = FakeWorld(transcript: "recovered")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()
        world.clock.advance(by: .seconds(60))
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let listed = await pipeline.retries.recovered()
        let ids = await world.store.records.map(\.id)
        #expect(listed.map(\.id) == ids.reversed())
    }

    @Test func copyingARecoveredTranscriptPutsItOnTheClipboardAndOffTheList() async throws {
        let world = FakeWorld(transcript: "copy me")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let item = try #require(await pipeline.retries.recovered().first)
        await pipeline.retries.copy(item)

        #expect(await world.pasteboard.text == "copy me")
        #expect(await world.pasteboard.isTransient == false)
        #expect(await pipeline.retries.recovered().isEmpty)
        #expect(try #require(await world.store.records.first).status == .copied)
    }

    @Test func recoveredTranscriptsLeaveTheListAfter24Hours() async {
        let world = FakeWorld(transcript: "old")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        world.clock.advance(by: .seconds(24 * 60 * 60))
        #expect(await pipeline.retries.recovered().count == 1)
        world.clock.advance(by: .seconds(1))
        #expect(await pipeline.retries.recovered().isEmpty)
    }

    @Test func aRetryThatFailsAgainStaysQueued() async throws {
        let world = FakeWorld(transcript: "unreachable")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: FakeError())
        await pipeline.dictate(world)

        await pipeline.retryPending()

        #expect(try #require(await world.store.records.first).status == .failed)
        #expect(await world.provider.requests.count == 2)
    }

    @Test func aNetworkFailureStaysRetryable() async throws {
        let world = FakeWorld(transcript: "offline")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)

        await pipeline.dictate(world)

        #expect(try #require(await world.store.records.first).status == .failed)
    }

    @Test func anAuthErrorWaitsForAKeyAndIsNotRetriedOnItsOwn() async throws {
        let world = FakeWorld(transcript: "needs a key")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.auth(status: 401))

        await pipeline.dictate(world)
        let record = try #require(await world.store.records.first)
        #expect(record.status == .failed)
        #expect(record.needsSetup == .key)
        #expect(await pipeline.state == .needsSetup(record.id, .key))

        await world.provider.fail(with: nil)
        await pipeline.retryPending(.exceptNeedsSetup)
        #expect(await world.provider.requests.count == 1)
        #expect(try #require(await world.store.records.first).status == .failed)
    }

    @Test func savingAKeyRetriesOnlyTheDictationsThatWaitedForIt() async throws {
        let world = FakeWorld(transcript: "now with a key", clipboard: "owner's")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.auth(status: nil))
        await pipeline.dictate(world)
        let waiting = try #require(await world.store.records.first).id
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)

        await world.provider.fail(with: nil)
        await pipeline.retryPending(.onlyNeedsSetup)

        let records = await world.store.records
        let retried = try #require(records.first { $0.id == waiting })
        #expect(retried.status == .recovered)
        #expect(retried.needsSetup == nil)
        #expect(records.first { $0.id != waiting }?.status == .failed)
        #expect(await world.provider.requests.count == 3)
        #expect(await world.pasteboard.text == "owner's")
        #expect(await world.paster.pasteCount == 0)
    }

    @Test func aRetryNeverSendsADictationThatFinishedMeanwhile() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)
        let queued = try #require(await world.store.records.first)
        let queuedGate = Gate()
        await world.provider.hold(at: queuedGate, onlyFor: queued.audio.file)

        await pipeline.tap(world)
        let live = try #require(await world.audio.files.last)
        let liveGate = Gate()
        await world.provider.hold(at: liveGate, onlyFor: live)
        await pipeline.tap(world)
        #expect(await eventually { await liveGate.hasWaiters })
        #expect(await eventually { await world.store.records.contains { $0.audio.file == live } })

        // The retry reads the queue (the live row included) and waits while the live one runs.
        async let retried: Void = pipeline.retryPending()
        await liveGate.open()
        await pipeline.settle()
        #expect(await eventually { await queuedGate.hasWaiters })
        await queuedGate.open()
        await retried

        let liveRecord = try #require(await world.store.records.first { $0.audio.file == live })
        #expect(liveRecord.status == .pasted)
        #expect(await world.provider.requests.filter { $0.audio == live }.count == 1)
    }

    @Test func aRetryResultDoesNotHideALiveTranscription() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        await pipeline.tap(world)
        let live = try #require(await world.audio.files.last)
        let liveGate = Gate()
        await world.provider.hold(at: liveGate, onlyFor: live)
        await pipeline.tap(world)
        #expect(await eventually { await liveGate.hasWaiters })
        async let retried: Void = pipeline.retryPending()

        #expect(await eventually { await world.provider.requests.count >= 3 } == false)
        #expect(await pipeline.state == .transcribing)
        await liveGate.open()
        await pipeline.settle()
        await retried
        #expect(await world.provider.requests.count == 3)
    }

    @Test func theMenuRetrySkipsDictationsThatWaitWhileTheSetupIsMissing() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        world.setup.missing = .endpoint
        await world.provider.fail(with: ProviderError.needsSetup(provider: "Azure", item: .endpoint))
        await pipeline.dictate(world)
        #expect(await pipeline.state == .needsSetup(try #require(await world.store.records.first).id, .endpoint))

        await world.provider.fail(with: nil)
        await pipeline.retryPending()
        #expect(await world.provider.requests.count == 1)

        world.setup.missing = nil
        await pipeline.retryPending()
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    @Test func aSavedSettingRetriesTheWaitingDictationsOnlyWhenTheRouteIsReady() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        world.setup.missing = .key
        await world.provider.fail(with: ProviderError.auth(status: 401))
        await pipeline.dictate(world)
        await world.provider.fail(with: nil)

        await pipeline.setupChanged()
        #expect(await world.provider.requests.count == 1)

        world.setup.missing = nil
        await pipeline.setupChanged()
        #expect(try #require(await world.store.records.first).status == .recovered)
    }

    @Test func eachHistoryWriteIsAnnounced() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        let changes = ChangeCounter()
        let watcher = Task {
            for await _ in pipeline.historyChanges {
                await changes.record()
            }
        }
        defer { watcher.cancel() }
        await world.provider.fail(with: ProviderError.offline)

        await pipeline.dictate(world)

        #expect(await eventually { await changes.isAnnounced })
    }
}

private actor ChangeCounter {
    private(set) var isAnnounced = false

    func record() {
        isAnnounced = true
    }

}
