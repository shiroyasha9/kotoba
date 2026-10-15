import Foundation
import Testing

@testable import KotobaCore

struct RetryQueueTests {
    let world = FakeWorld(transcript: "recovered")

    func makeQueue() -> RetryQueue {
        RetryQueue(
            steps: TranscriptionSteps(provider: world.provider, cleaner: nil, clock: world.clock),
            store: world.store,
            clock: world.clock,
            clipboard: ClipboardGuard(pasteboard: world.pasteboard)
        )
    }

    /// `run` with the test settings and nothing in flight.
    func run(
        _ queue: RetryQueue, _ selection: RetrySelection,
        skipping: @escaping @Sendable (DictationID) -> Bool = { _ in false }
    )
        async -> [DictationRecord]
    {
        await queue.run(
            selection, settings: { .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests")) },
            skipping: { skipping($0) })
    }

    func queued(_ status: DictationRecord.Status) async throws -> DictationRecord {
        let record = DictationRecord(
            id: DictationID(),
            createdAt: world.clock.date,
            audio: RecordedAudio(file: URL(filePath: "/tmp/\(UUID().uuidString).flac"), duration: .seconds(2)),
            transcript: nil,
            status: status,
            latency: LatencyLog()
        )
        try await world.store.save(record)
        return record
    }

    @Test func pendingAndFailedAreRetriedButRejectedIsNot() async throws {
        let pending = try await queued(.pending)
        let failed = try await queued(.failed)
        _ = try await queued(.rejected)

        let results = await run(makeQueue(), .all)

        #expect(results.map(\.id) == [pending.id, failed.id])
        #expect(results.allSatisfy { $0.status == .recovered && $0.transcript == "recovered" })
        #expect(await world.provider.requests.count == 2)
    }

    @Test func aDictationInFlightIsSkipped() async throws {
        let inFlight = try await queued(.pending)
        let queuedOne = try await queued(.failed)

        let results = await run(makeQueue(), .all, skipping: { [id = inFlight.id] in $0 == id })

        #expect(results.map(\.id) == [queuedOne.id])
    }

    @Test func copiedTranscriptsLeaveTheRecoveredList() async throws {
        _ = try await queued(.failed)
        let queue = makeQueue()
        _ = await run(queue, .all)

        let item = try #require(await queue.recovered().first)
        await queue.copy(item)

        #expect(await queue.recovered().isEmpty)
    }

    @Test func aRetryAskedForDuringARunRunsAfterIt() async throws {
        _ = try await queued(.failed)
        var waiting = DictationRecord(
            id: DictationID(), createdAt: world.clock.date,
            audio: RecordedAudio(file: URL(filePath: "/tmp/waiting.flac"), duration: .seconds(2)),
            transcript: nil, status: .failed, latency: LatencyLog())
        waiting.needsSetup = .key
        try await world.store.save(waiting)
        let gate = Gate()
        await world.provider.hold(at: gate)
        let queue = makeQueue()

        async let first = run(queue, .exceptNeedsSetup)
        #expect(await eventually { await gate.hasWaiters })
        let second = await run(queue, .onlyNeedsSetup)
        await gate.open()
        let firstResults = await first

        #expect(second.isEmpty)
        #expect(firstResults.count == 2)
        #expect(await world.store.records.first { $0.id == waiting.id }?.status == .recovered)
    }
}
