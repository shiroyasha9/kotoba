import Foundation
import Synchronization
import Testing

@testable import KotobaCore

struct RetryQueueTests {
    let world = FakeWorld(transcript: "recovered")

    func makeQueue() -> RetryQueue {
        RetryQueue(
            steps: TranscriptionSteps(
                provider: world.provider, cleaner: nil, clock: world.clock, store: world.store,
                work: PendingWork(clock: world.clock)),
            store: world.store,
            clock: world.clock,
            paste: ClipboardPaste(
                pasteboard: world.pasteboard, paster: world.paster, frontApp: { nil }, place: nil,
                readWait: .seconds(10), work: PendingWork(clock: world.clock), clock: world.clock)
        )
    }

    static let settings = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp/kotoba-tests"))

    /// `run` with the test settings and nothing live: each send begins, unless `start` says otherwise.
    func run(
        _ queue: RetryQueue, _ selection: RetrySelection,
        start: @escaping @Sendable (DictationID) -> RetryQueue.SendStart = { _ in .began(Self.settings) },
        endSend: @escaping @Sendable () async -> Void = {}
    )
        async -> [DictationRecord]
    {
        await queue.run(selection, waitUntilQuiet: {}, beginSend: { start($0) }, endSend: endSend)
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

    /// The next send would fail the same way (no network, a rate limit, a locked key store): the run
    /// stops, and the rest stay queued for the next trigger, unsent and unbilled.
    @Test(arguments: [
        ProviderError.offline, .connectionBlocked, .rateLimited(retryAfter: .seconds(30)), .keyUnavailable,
    ])
    func aFailureThatHitsEveryDictationStopsTheRun(error: ProviderError) async throws {
        _ = try await queued(.failed)
        _ = try await queued(.failed)
        await world.provider.fail(with: error)

        _ = await run(makeQueue(), .all)

        #expect(await world.provider.requests.count == 1)
        #expect(try await world.store.pendingRetries().count == 2)
    }

    /// A failure of one dictation only (a server error, or a timeout, whose limit grows with the audio) does not stop
    /// the others.
    @Test(arguments: [ProviderError.server(status: 502), .timedOut])
    func aFailureOfOneDictationDoesNotStopTheRun(error: ProviderError) async throws {
        _ = try await queued(.failed)
        _ = try await queued(.failed)
        await world.provider.fail(with: error)

        _ = await run(makeQueue(), .all)

        #expect(await world.provider.requests.count == 2)
    }

    @Test func aDictationInFlightIsSkipped() async throws {
        let inFlight = try await queued(.pending)
        let queuedOne = try await queued(.failed)

        let results = await run(makeQueue(), .all) { [id = inFlight.id] in $0 == id ? .inFlight : .began(Self.settings)
        }

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

    /// The store cannot write a recovered transcript (a full disk): the run stops, as the next answer would be billed
    /// and lost the same way. The menu still lists the text until the owner copies it, and no later run in this
    /// process sends it again.
    @Test func aRecoveredTranscriptTheStoreCannotWriteStaysInTheMenuAndStopsTheRun() async throws {
        let first = try await queued(.failed)
        _ = try await queued(.failed)
        await world.store.failUpdates(with: CocoaError(.fileWriteOutOfSpace))
        let queue = makeQueue()

        let results = await run(queue, .all)

        #expect(results.map(\.id) == [first.id])
        #expect(await world.provider.requests.count == 1)
        #expect(await queue.recovered().map(\.id) == [first.id])

        await world.store.failUpdates(with: nil)
        let second = await run(queue, .all)

        #expect(!second.contains { $0.id == first.id })
        #expect(await world.provider.requests.count == 2)
    }

    /// A retry asked for during the run is dropped too once the store cannot write: its answer would be lost the
    /// same way.
    @Test func aStoreThatCannotWriteEndsTheRetryAskedForDuringTheRun() async throws {
        _ = try await queued(.failed)
        var waiting = try await queued(.failed)
        waiting.needsSetup = .key
        try await world.store.save(waiting)
        let gate = Gate()
        await world.provider.hold(at: gate)
        let queue = makeQueue()

        async let first = run(queue, .exceptNeedsSetup)
        #expect(await eventually { await gate.hasWaiters })
        _ = await run(queue, .onlyNeedsSetup)
        await world.store.failUpdates(with: CocoaError(.fileWriteOutOfSpace))
        await gate.open()
        _ = await first

        #expect(await world.provider.requests.count == 1)
    }

    /// Quit: no send begins once the pipeline says it stopped, and the run ends there.
    @Test func aStoppedPipelineEndsTheRun() async throws {
        _ = try await queued(.failed)
        _ = try await queued(.failed)

        let results = await run(makeQueue(), .all) { _ in .stopped }

        #expect(results.isEmpty)
        #expect(await world.provider.requests.isEmpty)
    }

    /// The send ends only after its answer is saved, so quit, which waits for that end, never loses a billed answer.
    @Test func theSendEndsAfterItsAnswerIsSaved() async throws {
        let record = try await queued(.failed)
        let statuses = Mutex<[DictationRecord.Status?]>([])

        _ = await run(
            makeQueue(), .all,
            endSend: { [store = world.store] in
                // A failed read shows as nil, which the expectation below refuses.
                let status = try? await store.status(of: record.id)
                statuses.withLock { $0.append(status) }
            })

        #expect(statuses.withLock { $0 } == [.recovered])
    }

    @Test func aRecoveredTranscriptTheStoreCannotWriteLeavesTheMenuOnceCopied() async throws {
        _ = try await queued(.failed)
        await world.store.failUpdates(with: CocoaError(.fileWriteOutOfSpace))
        let queue = makeQueue()
        _ = await run(queue, .all)

        let item = try #require(await queue.recovered().first)
        await queue.copy(item)

        #expect(await queue.recovered().isEmpty)
        #expect(await world.pasteboard.text == "recovered")
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
