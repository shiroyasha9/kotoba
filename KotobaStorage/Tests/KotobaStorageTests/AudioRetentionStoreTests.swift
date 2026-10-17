import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Story 31 in SQLite: `deleteAudio` deletes the files `AudioRetention` finds expired and keeps every row.
struct AudioRetentionStoreTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }
    /// Where the audio files are, as `DictationPipeline.Settings.audioDirectory`.
    var audio: URL { folder.url.appending(path: "audio", directoryHint: .isDirectory) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    /// A dictation with its audio file on disk.
    func dictation(
        _ status: DictationRecord.Status, daysAgo: Double, recoveredDaysAgo: Double? = nil, bytes: Int = 4
    ) throws -> DictationRecord {
        let file = audio.appending(path: "\(UUID().uuidString).flac")
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        try Data(count: bytes).write(to: file)
        return DictationRecord(
            id: DictationID(), createdAt: now - daysAgo * Self.day,
            audio: RecordedAudio(file: file, duration: .seconds(10)), transcript: status.isTranscribed ? "text" : nil,
            status: status, recoveredAt: recoveredDaysAgo.map { now - $0 * Self.day }, latency: LatencyLog())
    }

    /// Every batch, as the pipeline runs them with one cutoff.
    func deleteAudio(_ store: HistoryStore, before cutoff: Date) async throws -> Set<DictationID> {
        var deleted: Set<DictationID> = []
        var cursor: AudioCursor?
        repeat {
            let batch = try await store.deleteAudio(transcribedBefore: cutoff, after: cursor)
            deleted.formUnion(batch.deleted)
            cursor = batch.next
        } while cursor != nil
        return deleted
    }

    /// The store agrees with the policy on every status, both sides of the cutoff, and a retry's later text.
    @Test func theStoreDeletesWhatThePolicyFindsExpired() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var rows: [DictationRecord] = []
        for status in DictationRecord.Status.allCases {
            rows.append(try dictation(status, daysAgo: 8))
            rows.append(try dictation(status, daysAgo: 6))
        }
        rows.append(try dictation(.recovered, daysAgo: 30, recoveredDaysAgo: 2))
        rows.append(try dictation(.copied, daysAgo: 30, recoveredDaysAgo: 8))
        for row in rows {
            try await store.save(row)
        }
        let retention = AudioRetention.sevenDays

        let deleted = try await deleteAudio(store, before: try #require(retention.cutoff(at: now)))

        let expired = rows.filter { retention.isExpired($0, at: now) }
        #expect(deleted == Set(expired.map(\.id)))
        #expect(Set(expired.map(\.status)) == [.pasted, .copied, .notPasted, .recovered])
        for row in rows {
            let isExpired = expired.contains { $0.id == row.id }
            #expect(FileManager.default.fileExists(atPath: row.audio.file.path) == !isExpired)
            let stored = try #require(try await store.record(row.id))
            #expect(stored.isAudioDeleted == isExpired)
            #expect(stored.transcript == row.transcript)
        }
        #expect(try await store.page(limit: 100).count == rows.count)
        let rest = Set(rows.filter(\.status.isTranscribed).map(\.id)).subtracting(deleted)
        #expect(try await deleteAudio(store, before: .distantFuture) == rest)
    }

    /// Oldest text first, a batch at a time; the cursor moves past every row read, so the batches cover all once.
    @Test func batchesGoOldestFirstAndCoverEveryRowOnce() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let count = HistoryStore.audioBatchSize + 20
        var newest: Set<DictationID> = []
        for index in 0..<count {
            let row = try dictation(.pasted, daysAgo: Double(10 + index % 7))
            if index % 7 == 0 { newest.insert(row.id) }
            try await store.save(row)
        }

        let first = try await store.deleteAudio(transcribedBefore: now, after: nil)
        let next = try #require(first.next)
        let second = try await store.deleteAudio(transcribedBefore: now, after: next)

        #expect(first.deleted.count == HistoryStore.audioBatchSize)
        #expect(second.deleted.count == 20 && second.next == nil)
        #expect(first.deleted.isDisjoint(with: second.deleted))
        #expect(second.deleted.isSubset(of: newest))
        #expect(next.transcribedAt == now - 10 * Self.day)
    }

    @Test func aFileAlreadyGoneIsStillMarked() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let row = try dictation(.pasted, daysAgo: 10)
        try await store.save(row)
        try FileManager.default.removeItem(at: row.audio.file)

        #expect(try await deleteAudio(store, before: now) == [row.id])
        #expect(try #require(try await store.record(row.id)).isAudioDeleted)
        #expect(try await deleteAudio(store, before: now).isEmpty)
    }

    /// Review 3: a file that cannot be removed keeps its row unmarked, so the next run tries again.
    @Test func aFileThatCannotBeRemovedKeepsItsRow() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let row = try dictation(.pasted, daysAgo: 10)
        try await store.save(row)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: audio.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path) }

        #expect(try await deleteAudio(store, before: now).isEmpty)
        #expect(FileManager.default.fileExists(atPath: row.audio.file.path))
        #expect(try #require(try await store.record(row.id)).isAudioDeleted == false)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path)
        #expect(try await deleteAudio(store, before: now) == [row.id])
    }

    /// Review 5: only the file of that name in the audio folder goes. A path elsewhere is never removed, and a path
    /// from another Mac or home folder finds its file here.
    @Test func onlyFilesInTheAudioFolderAreRemoved() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let elsewhere = folder.url.appending(path: "Documents/notes.flac")
        try FileManager.default.createDirectory(
            at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: elsewhere)
        var foreign = try dictation(.pasted, daysAgo: 10)
        foreign.audio.file = elsewhere
        var moved = try dictation(.pasted, daysAgo: 10)
        let file = moved.audio.file
        moved.audio.file = URL(filePath: "/Volumes/Old Mac/Library/kotoba/audio").appending(
            path: file.lastPathComponent)
        try await store.save(foreign)
        try await store.save(moved)

        #expect(try await deleteAudio(store, before: now) == [foreign.id, moved.id])
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// Review 5: Delete and Retry find a row's audio by its name in the audio folder, as retention does: Delete never
    /// removes a file elsewhere, and a path from another Mac finds its file here.
    @Test func deleteAndRetryFindTheAudioInTheAudioFolder() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let elsewhere = folder.url.appending(path: "Documents/notes.flac")
        try FileManager.default.createDirectory(
            at: elsewhere.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: elsewhere)
        var foreign = try dictation(.failed, daysAgo: 1)
        foreign.audio.file = elsewhere
        var moved = try dictation(.failed, daysAgo: 1)
        let file = moved.audio.file
        moved.audio.file = URL(filePath: "/Volumes/Old Mac/Library/kotoba/audio").appending(
            path: file.lastPathComponent)
        try await store.save(foreign)
        try await store.save(moved)

        let queued = try await store.pendingRetries()
        #expect(try await store.delete([foreign.id, moved.id]).isEmpty)

        #expect(Set(queued.map(\.audio.file)) == [audio.appending(path: "notes.flac"), file])
        #expect(FileManager.default.fileExists(atPath: elsewhere.path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// Review V3: a file that is there but cannot be measured makes the size unknown, so Settings still asks before a
    /// shorter period (without a size) and shows no size; a missing file counts as nothing.
    @Test func aFileThatCannotBeMeasuredMakesTheSizeUnknown() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let row = try dictation(.pasted, daysAgo: 10)
        let gone = try dictation(.copied, daysAgo: 10)
        try await store.save(row)
        try await store.save(gone)
        try FileManager.default.removeItem(at: gone.audio.file)
        try SQLiteDatabase(url: url).run("UPDATE dictations SET audio_bytes = NULL;")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: audio.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path) }

        #expect(try await store.expiringAudioBytes(transcribedBefore: now) == nil)
        #expect(try await store.keptAudioSize() == nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path)
        #expect(try await store.expiringAudioBytes(transcribedBefore: now) ?? 0 > 0)
    }

    /// A save after the deletion keeps the mark: only `deleteAudio` writes the column.
    @Test func aLaterSaveKeepsTheAudioDeleted() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let row = try dictation(.recovered, daysAgo: 10, recoveredDaysAgo: 10)
        try await store.save(row)
        _ = try await deleteAudio(store, before: now)

        try await store.markCopied(row.id)
        try await store.save(try #require(try await store.record(row.id)))

        #expect(try #require(try await store.record(row.id)).isAudioDeleted)
    }

    /// Settings asks before a shorter period deletes audio, with the size it would delete; only transcribed audio
    /// still kept counts, and a row from before the size column gets its size from its file.
    @Test func theExpiringSizeCountsOnlyWhatTheCutoffDeletes() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let old = try dictation(.pasted, daysAgo: 10, bytes: 10_000)
        let older = try dictation(.copied, daysAgo: 20, bytes: 10_000)
        for row in [
            old, older, try dictation(.pasted, daysAgo: 1, bytes: 50_000),
            try dictation(.failed, daysAgo: 10, bytes: 50_000),
        ] {
            try await store.save(row)
        }
        try SQLiteDatabase(url: url).run(
            "UPDATE dictations SET audio_bytes = NULL WHERE id = ?1;", [.text(older.id.rawValue.uuidString)])
        let cutoff = now - 7 * Self.day

        let expiring = try #require(try await store.expiringAudioBytes(transcribedBefore: cutoff))
        _ = try await deleteAudio(store, before: cutoff)

        #expect(expiring >= 20_000 && expiring < 50_000)
        #expect(try await store.expiringAudioBytes(transcribedBefore: cutoff) == 0)
    }

    /// With the statistics each open keeps (`PRAGMA optimize`), the batch reads the partial index, which holds only
    /// the audio still kept, not every pasted row.
    @Test func batchesReadThePartialIndex() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        for index in 0..<2_000 {
            try await store.save(try dictation(index % 10 == 0 ? .failed : .pasted, daysAgo: Double(index) / 10))
        }
        _ = try await deleteAudio(store, before: now - 7 * Self.day)
        _ = try HistoryStore(url: url, audio: audio)

        let database = try SQLiteDatabase(url: url)
        for query in [HistoryStore.expiredAudioQuery(after: false), HistoryStore.expiredAudioQuery(after: true)] {
            let plan = try database.query(
                "EXPLAIN QUERY PLAN " + query, [.real(0), .integer(500), .real(0), .text("")])
            #expect(plan.contains { $0.last?.string?.contains("INDEX dictations_kept_audio_2 ") == true })
        }
    }

    /// Review 2: launch reads whether an older build left dictations, to keep their audio.
    @Test func theStoreSaysWhetherItOpenedWithDictations() async throws {
        #expect(try HistoryStore(url: url, audio: audio).hadDictationsAtOpen == false)
        try await HistoryStore(url: url, audio: audio).save(try dictation(.pasted, daysAgo: 1))
        #expect(try HistoryStore(url: url, audio: audio).hadDictationsAtOpen)
    }

    /// Settings shows what "Delete Audio Now…" can delete apart from the audio kept until sent, from the sizes `save`
    /// keeps; a row from before that column gets its size once from its file.
    @Test func theKeptSizeSplitsDeletableAudioFromAudioThatWaits() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let pasted = try dictation(.pasted, daysAgo: 1, bytes: 10_000)
        let failed = try dictation(.failed, daysAgo: 1, bytes: 100_000)
        let older = try dictation(.copied, daysAgo: 1, bytes: 10_000)
        for row in [pasted, failed, older] {
            try await store.save(row)
        }
        try SQLiteDatabase(url: url).run(
            "UPDATE dictations SET audio_bytes = NULL WHERE id = ?1;", [.text(older.id.rawValue.uuidString)])

        let before = try #require(try await store.keptAudioSize())
        _ = try await deleteAudio(store, before: .distantFuture)
        let after = try await store.keptAudioSize()

        #expect(before.deletable >= 20_000 && before.deletable < 100_000)
        #expect(before.waiting >= 100_000)
        #expect(after == KeptAudioSize(deletable: 0, waiting: before.waiting))
    }

    /// Cost on 10,000 files (debug build, 2026-10-16): the first run deletes them all in about 1.0 s, in batches of
    /// 500; the run after the next dictation finds none in about 0.6 ms; the size is one aggregate in about 3 ms. The
    /// bounds are loose, so a busy machine does not fail the run.
    @Test func tenThousandFilesAreDeletedAndTheNextRunIsOneProbe() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        for _ in 0..<10_000 {
            try await store.save(try dictation(.pasted, daysAgo: 10))
        }
        let clock = ContinuousClock()
        var deleted: Set<DictationID> = []
        let size = try await clock.measure { _ = try await store.keptAudioSize() }
        let first = try await clock.measure { deleted = try await deleteAudio(store, before: now) }
        let next = try await clock.measure { _ = try await deleteAudio(store, before: now) }

        #expect(deleted.count == 10_000)
        let files = try FileManager.default.contentsOfDirectory(atPath: audio.path)
        #expect(files.isEmpty)
        #expect(first < .seconds(10))
        #expect(next < .milliseconds(100))
        #expect(size < .milliseconds(500))
    }
}
