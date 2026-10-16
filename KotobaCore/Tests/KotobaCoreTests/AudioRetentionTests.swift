import Foundation
import Testing

@testable import KotobaCore

/// Story 31: a transcribed dictation keeps its audio for the chosen period; one without text keeps it until it has
/// text or the owner deletes it. Only the audio goes, never the row.
struct AudioRetentionTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    static func record(
        _ status: DictationRecord.Status, transcribed age: TimeInterval, recoveredAge: TimeInterval? = nil,
        isAudioDeleted: Bool = false
    ) -> DictationRecord {
        var record = DictationRecord(
            id: DictationID(), createdAt: now - age,
            audio: RecordedAudio(file: URL(filePath: "/tmp/a.flac"), duration: .seconds(5)), transcript: nil,
            status: status, recoveredAt: recoveredAge.map { now - $0 }, latency: LatencyLog())
        record.isAudioDeleted = isAudioDeleted
        return record
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let retention: AudioRetention
        let record: DictationRecord
        let isExpired: Bool
        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "pasted 8 days ago, 7 days", retention: .sevenDays, record: record(.pasted, transcribed: 8 * day),
            isExpired: true),
        Case(
            name: "pasted 6 days ago, 7 days", retention: .sevenDays, record: record(.pasted, transcribed: 6 * day),
            isExpired: false),
        Case(
            name: "exactly 1 day: kept", retention: .oneDay, record: record(.copied, transcribed: day),
            isExpired: false),
        Case(
            name: "1 day and 1 s: deleted", retention: .oneDay, record: record(.copied, transcribed: day + 1),
            isExpired: true),
        Case(
            name: "29 days, 30 days", retention: .thirtyDays, record: record(.pasted, transcribed: 29 * day),
            isExpired: false),
        Case(
            name: "31 days, 30 days", retention: .thirtyDays, record: record(.pasted, transcribed: 31 * day),
            isExpired: true),
        Case(
            name: "forever keeps a year", retention: .forever, record: record(.pasted, transcribed: 365 * day),
            isExpired: false),
        Case(
            name: "recovered 2 days ago counts from the retry", retention: .sevenDays,
            record: record(.recovered, transcribed: 30 * day, recoveredAge: 2 * day), isExpired: false),
        Case(
            name: "copied after a retry 8 days ago", retention: .sevenDays,
            record: record(.copied, transcribed: 30 * day, recoveredAge: 8 * day), isExpired: true),
        Case(
            name: "audio already deleted", retention: .oneDay,
            record: record(.pasted, transcribed: 30 * day, isAudioDeleted: true), isExpired: false),
    ]

    @Test(arguments: cases)
    func theRetentionPeriodDecides(_ example: Case) {
        #expect(example.retention.isExpired(example.record, at: Self.now) == example.isExpired)
    }

    /// Failed, cancelled, refused or queued audio waits for a retry, whatever its age.
    @Test(arguments: [DictationRecord.Status.pending, .failed, .cancelled, .rejected])
    func aDictationWithoutTextKeepsItsAudio(_ status: DictationRecord.Status) {
        let record = Self.record(status, transcribed: 365 * Self.day)
        #expect(!AudioRetention.oneDay.isExpired(record, at: Self.now))
        #expect(record.transcribedAt == nil)
        #expect(record.isRetryable)
    }

    @Test func theDefaultIsSevenDays() {
        #expect(AudioRetention.standard == .sevenDays)
        #expect(DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).audioRetention == .sevenDays)
    }

    /// An update never deletes audio the owner did not choose to lose: a history from an earlier build keeps all.
    @Test(arguments: [(false, AudioRetention.sevenDays), (true, .forever)])
    func theFirstChoiceKeepsAnEarlierHistory(hasEarlierHistory: Bool, expected: AudioRetention) {
        #expect(AudioRetention.firstChoice(hasEarlierHistory: hasEarlierHistory) == expected)
    }

    /// Settings asks before a shorter period deletes audio.
    @Test func forEverKeepsMoreThanAnyPeriod() {
        #expect(AudioRetention.oneDay.keepsLess(than: .sevenDays))
        #expect(AudioRetention.thirtyDays.keepsLess(than: .forever))
        #expect(!AudioRetention.forever.keepsLess(than: .oneDay))
        #expect(!AudioRetention.sevenDays.keepsLess(than: .sevenDays))
    }

    // MARK: When it runs

    /// A delivered dictation is the event: the audio older than the period goes, the rest stays.
    @Test func aPastedDictationDeletesTheExpiredAudio() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        let old = Self.record(.pasted, transcribed: 0)
        let failed = Self.record(.failed, transcribed: 0)
        try await world.store.save(old)
        try await world.store.save(failed)
        world.clock.advance(by: .seconds(8 * Self.day))

        await pipeline.dictate(world)

        let records = await world.store.records
        #expect(records.count == 3)
        #expect(records.first { $0.id == old.id }?.isAudioDeleted == true)
        #expect(records.first { $0.id == failed.id }?.isAudioDeleted == false)
        #expect(records.last?.isAudioDeleted == false)
    }

    /// A retry that recovers a dictation delivers it too.
    @Test func aRecoveredDictationDeletesTheExpiredAudio() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        let old = Self.record(.pasted, transcribed: 0)
        try await world.store.save(old)
        try await world.store.save(Self.record(.failed, transcribed: 0))
        world.clock.advance(by: .seconds(8 * Self.day))

        await pipeline.retryPending()
        await pipeline.settle()

        #expect(await world.store.records.first { $0.id == old.id }?.isAudioDeleted == true)
    }

    @Test func aFailedDictationDeletesNothing() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record(.pasted, transcribed: 0))
        world.clock.advance(by: .seconds(8 * Self.day))
        await world.provider.fail(with: FakeError())

        await pipeline.dictate(world)

        #expect(await world.store.records.allSatisfy { !$0.isAudioDeleted })
    }

    @Test func aShorterPeriodAppliesAtOnce() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record(.pasted, transcribed: 0))
        world.clock.advance(by: .seconds(2 * Self.day))

        await pipeline.deleteExpiredAudio()
        #expect(await world.store.records.allSatisfy { !$0.isAudioDeleted })
        await pipeline.updateAudioRetention(.oneDay)

        #expect(await world.store.records.allSatisfy(\.isAudioDeleted))
    }

    @Test func foreverDeletesNothing() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record(.pasted, transcribed: 0))
        world.clock.advance(by: .seconds(400 * Self.day))

        await pipeline.updateAudioRetention(.forever)
        await pipeline.dictate(world)

        #expect(await world.store.records.allSatisfy { !$0.isAudioDeleted })
    }

    /// "Delete Audio Now…" takes every transcribed dictation's audio, new ones too, and never audio that waits.
    @Test func deleteAudioNowKeepsTheAudioOfDictationsWithoutText() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        await pipeline.dictate(world)
        let cancelled = Self.record(.cancelled, transcribed: 0)
        try await world.store.save(cancelled)

        await pipeline.deleteTranscribedAudio()

        let records = await world.store.records
        #expect(records.filter(\.isAudioDeleted).map(\.status) == [.pasted])
        #expect(records.first { $0.id == cancelled.id }?.isAudioDeleted == false)
    }

    /// Three expired dictations, deleted one per batch; the first batch waits for `gate`.
    func runInProgress(_ world: FakeWorld, _ pipeline: DictationPipeline, gate: Gate) async throws -> Task<Void, Never>
    {
        for _ in 0..<3 {
            try await world.store.save(Self.record(.pasted, transcribed: 0))
        }
        world.clock.advance(by: .seconds(8 * Self.day))
        await world.store.holdAudioDeletion(at: gate, batchSize: 1)
        let run = Task { await pipeline.deleteExpiredAudio() }
        #expect(await eventually { await gate.hasWaiters })
        return run
    }

    /// Each batch takes its cutoff from the setting as it is then: "Forever" during a run stops it after the batch in
    /// progress, and a 1 Day asked for before it deletes nothing more.
    @Test func foreverDuringARunStopsFurtherDeletes() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        let gate = Gate()
        let run = try await runInProgress(world, pipeline, gate: gate)

        await pipeline.updateAudioRetention(.oneDay)
        await pipeline.updateAudioRetention(.forever)
        await gate.open()
        await run.value

        #expect(await world.store.records.count(where: \.isAudioDeleted) == 1)
        #expect(await world.store.audioCutoffs == [world.clock.date - 7 * Self.day])
    }

    /// Launch, a dictation and "Delete Audio Now…" can ask at once: one run at a time, then one more for what was
    /// asked during it.
    @Test func requestsDuringARunWaitForIt() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        let gate = Gate()
        let run = try await runInProgress(world, pipeline, gate: gate)
        // Copied just now (the clock moved 8 days): only "Delete Audio Now…" takes it.
        try await world.store.save(Self.record(.copied, transcribed: -8 * Self.day))

        await pipeline.deleteExpiredAudio()
        await pipeline.deleteTranscribedAudio()
        #expect(await world.store.audioCutoffs.count == 1)
        await gate.open()
        await run.value

        #expect(await world.store.records.allSatisfy(\.isAudioDeleted))
        #expect(await world.store.audioCutoffs.last == .distantFuture)
    }

    /// The History window reads its rows again only when audio went, not after every dictation.
    @Test func onlyARunThatDeletedAudioIsAnnounced() async throws {
        let world = FakeWorld(transcript: "ship it")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record(.pasted, transcribed: 0))
        var changes = pipeline.historyChanges.makeAsyncIterator()
        let marker = DictationID()

        await pipeline.deleteExpiredAudio()
        await pipeline.deleteTranscribedAudio()
        await pipeline.deleteTranscribedAudio()
        _ = await pipeline.delete([marker])

        let deleted = Set(await world.store.records.map(\.id))
        #expect(await changes.next() == .audioDeleted(deleted))
        #expect(await changes.next() == .deleted([marker]))
    }
}
