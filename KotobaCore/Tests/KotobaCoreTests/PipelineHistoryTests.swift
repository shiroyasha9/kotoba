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
