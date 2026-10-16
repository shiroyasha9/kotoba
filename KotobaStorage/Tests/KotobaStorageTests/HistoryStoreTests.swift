import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

struct HistoryStoreTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }
    var audio: URL { folder.url }

    func record(_ status: DictationRecord.Status, at time: TimeInterval = 1_800_000_000) -> DictationRecord {
        var latency = LatencyLog()
        latency.record(.stop, offset: .seconds(3))
        latency.record(.pasteSent, offset: .milliseconds(3_812))
        return DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: time),
            audio: RecordedAudio(file: folder.url.appending(path: "\(UUID().uuidString).flac"), duration: .seconds(12)),
            transcript: nil, status: status, latency: latency)
    }

    @Test func aSavedRecordComesBackWhole() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var saved = record(.failed)
        saved.needsSetup = .endpoint
        saved.output = .cleanup(.writing)
        saved.model = "x-ai/grok-stt-1.0"
        try await store.save(saved)

        let loaded = try #require(try await HistoryStore(url: url, audio: audio).pendingRetries().first)
        #expect(loaded == saved)
        #expect(try await store.status(of: saved.id) == .failed)
    }

    @Test func aRejectedRecordKeepsItsReason() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var saved = record(.rejected)
        saved.rejectReason = .emptyTranscript
        try await store.save(saved)

        // No query returns rejected rows yet, so read the column directly.
        let rows = try SQLiteDatabase(url: url).query("SELECT reject_reason FROM dictations;")
        #expect(rows.first?.first == .text("emptyTranscript"))
    }

    @Test func theLastDeliveredIsTheNewestPastedOrCopiedRow() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        #expect(try await store.lastDelivered() == nil)
        var pasted = record(.pasted, at: 1_800_000_000)
        pasted.transcript = "deploy it to versel"
        var copied = record(.copied, at: 1_800_000_100)
        copied.transcript = "raw words"
        copied.cleanedText = "Cleaned words."
        try await store.save(pasted)
        try await store.save(copied)
        try await store.save(record(.failed, at: 1_800_000_200))
        try await store.save(record(.cancelled, at: 1_800_000_300))

        let last = try #require(try await store.lastDelivered())
        #expect(last.id == copied.id)
        #expect(last.cleanedText == "Cleaned words.")
    }

    @Test func onlyPendingAndFailedAreQueued() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        for status in [DictationRecord.Status.pending, .failed, .pasted, .rejected, .cancelled] {
            try await store.save(record(status))
        }

        #expect(Set(try await store.pendingRetries().map(\.status)) == [.pending, .failed])
        #expect(try await store.pendingCount() == 2)
    }

    @Test func recoveredRowsAreListedNewestFirstUntilCopied() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var older = record(.recovered)
        older.recoveredAt = Date(timeIntervalSince1970: 1_800_000_100)
        var newer = record(.recovered)
        newer.recoveredAt = Date(timeIntervalSince1970: 1_800_000_200)
        try await store.save(older)
        try await store.save(newer)

        #expect(try await store.recovered(since: .distantPast).map(\.id) == [newer.id, older.id])
        try await store.markCopied(newer.id)
        #expect(try await store.recovered(since: .distantPast).map(\.id) == [older.id])
        #expect(try await store.status(of: newer.id) == .copied)
    }

    @Test func anOlderDatabaseGetsTheNewColumns() async throws {
        let old = try SQLiteDatabase(url: url)
        try old.execute(
            """
            CREATE TABLE dictations (
                id TEXT PRIMARY KEY, created_at REAL NOT NULL, audio_path TEXT NOT NULL,
                audio_duration_ms INTEGER NOT NULL, transcript TEXT, status TEXT NOT NULL,
                needs_key INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO dictations VALUES ('6F8F57C5-7D3B-4B0E-9A3B-1C2D3E4F5A6B', 1800000000, '/tmp/a.flac', 1000,
                NULL, 'failed', 1);
            """)

        let store = try HistoryStore(url: url, audio: audio)

        let migrated = try #require(try await store.pendingRetries().first)
        #expect(migrated.needsSetup == .key)
        #expect(migrated.output == .transcript)
        #expect(migrated.app == nil)
        #expect(!migrated.isAudioDeleted)
        #expect(
            try await store.deleteAudio(transcribedBefore: .distantFuture, after: nil).deleted.isEmpty)
    }

    // MARK: History pane

    func spoken(_ text: String, at time: TimeInterval, app: DictationApp? = nil) -> DictationRecord {
        var spoken = record(.pasted, at: time)
        spoken.transcript = text
        spoken.app = app
        return spoken
    }

    @Test func aRecordKeepsTheAppItWentTo() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var saved = spoken("ship it", at: 1_000, app: DictationApp(bundleID: "com.apple.Notes", name: "Notes"))
        saved.latency = LatencyLog()
        try await store.save(saved)

        #expect(try await HistoryStore(url: url, audio: audio).page(limit: 10) == [saved])
    }

    @Test func pagesAreNewestFirstAndEachStartsAfterTheLastRowOfThePreviousOne() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        // Two rows share a time, so the cursor must also order by id.
        let rows = [1_000, 2_000, 2_000, 3_000, 4_000].map { spoken("words", at: TimeInterval($0)) }
        for row in rows {
            try await store.save(row)
        }

        let first = try await store.page(limit: 2)
        let second = try await store.page(after: first.last, limit: 2)
        let third = try await store.page(after: second.last, limit: 2)

        #expect(first.map(\.createdAt.timeIntervalSince1970) == [4_000, 3_000])
        #expect(second.map(\.createdAt.timeIntervalSince1970) == [2_000, 2_000])
        #expect(third.map(\.createdAt.timeIntervalSince1970) == [1_000])
        #expect(Set((first + second + third).map(\.id)) == Set(rows.map(\.id)))
        // The page holds no latency marks: the window does not show them.
        #expect(first.allSatisfy { $0.latency == LatencyLog() })
    }

    @Test func searchMatchesTheTranscriptTheCleanedTextOrTheAppName() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let raw = spoken("deploy to Vercel", at: 1_000)
        var cleaned = spoken("um so the plan", at: 2_000)
        cleaned.cleanedText = "The Plan is ready."
        let mail = spoken("see you", at: 3_000, app: DictationApp(bundleID: "com.apple.mail", name: "Mail"))
        let percent = spoken("100% done", at: 4_000)
        for row in [raw, cleaned, mail, percent] {
            try await store.save(row)
        }

        #expect(try await store.page(matching: "vercel", limit: 10).map(\.id) == [raw.id])
        #expect(try await store.page(matching: "plan IS", limit: 10).map(\.id) == [cleaned.id])
        #expect(try await store.page(matching: "mail", limit: 10).map(\.id) == [mail.id])
        // LIKE wildcards in the search are plain characters.
        #expect(try await store.page(matching: "0%", limit: 10).map(\.id) == [percent.id])
        #expect(try await store.page(matching: "_", limit: 10).isEmpty)
        #expect(try await store.page(matching: "", limit: 10).count == 4)
    }

    @Test func deleteRemovesTheRowItsMarksAndItsAudio() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let deleted = record(.failed)
        let kept = record(.failed)
        for saved in [deleted, kept] {
            try Data("flac".utf8).write(to: saved.audio.file)
            try await store.save(saved)
        }

        #expect(try await store.delete([deleted.id]).isEmpty)

        #expect(try await store.status(of: deleted.id) == nil)
        #expect(try await store.status(of: kept.id) == .failed)
        #expect(!FileManager.default.fileExists(atPath: deleted.audio.file.path))
        #expect(FileManager.default.fileExists(atPath: kept.audio.file.path))
        let marks = try SQLiteDatabase(url: url).query("SELECT count(*) FROM latency_marks;")
        #expect(marks.first?.first == .integer(2))
    }

    /// The files go first, then only the rows whose file is gone. A row whose file cannot be removed stays
    /// with its file, so a deleted dictation never comes back as audio with no row.
    @Test func aDeleteWhoseFileCannotBeRemovedKeepsItsRow() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let stuck = record(.failed)
        let deleted = record(.cancelled)
        try Data("flac".utf8).write(to: stuck.audio.file)
        try await store.save(stuck)
        try await store.save(deleted)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: audio.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path) }

        #expect(try await store.delete([stuck.id, deleted.id]) == [stuck.id])
        #expect(try await store.status(of: stuck.id) == .failed)
        #expect(try await store.status(of: deleted.id) == nil)
        #expect(FileManager.default.fileExists(atPath: stuck.audio.file.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: audio.path)
        #expect(try await store.delete([stuck.id]).isEmpty)
        #expect(try await store.status(of: stuck.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: stuck.audio.file.path))
    }

    @Test func knownIDsAreTheOnesWithARow() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let saved = record(.pasted)
        try await store.save(saved)

        #expect(try await store.knownIDs(among: [saved.id, DictationID()]) == [saved.id])
        #expect(try await store.knownIDs(among: []).isEmpty)
    }

    /// The cost the History pane pays: a page, a deep page, a search and one changed row on 10,000 rows of about 30
    /// words, and the menu's reads. Measured 2026-10-16 (debug build): about 0.8 ms a page, 3.3 ms for a search that
    /// matches nothing, 0.06 ms for one row, 2.8 ms for the menu, 17.5 ms for the launch's id check of 10,001 files.
    /// The bound is loose for other agents' builds on the same machine.
    @Test func aPageAndASearchOn10000RowsStayFast() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let words = "please move the standup to thursday and ask the team to review the pull request before lunch"
            .split(separator: " ")
        var ids: [DictationID] = []
        for index in 0..<10_000 {
            let text = (0..<30).map { words[($0 * 7 + index) % words.count] }.joined(separator: " ")
            let saved = spoken(text + " row\(index)", at: TimeInterval(index))
            try await store.save(saved)
            ids.append(saved.id)
        }
        let clock = ContinuousClock()
        var first: [DictationRecord] = []
        let page = try await clock.measure { first = try await store.page(limit: 200) }
        let deep = try await clock.measure { _ = try await store.page(after: first.last, limit: 200) }
        let hit = try await clock.measure { _ = try await store.page(matching: "Thursday", limit: 200) }
        let miss = try await clock.measure { _ = try await store.page(matching: "kubernetes", limit: 200) }
        let row = try await clock.measure { _ = try await store.record(first[100].id, matching: "thursday") }
        // The menu's reads after each burst of history writes (`AppDelegate.scheduleQueueRefresh`).
        let menu = try await clock.measure {
            _ = try await store.recovered(since: .distantPast)
            _ = try await store.pendingCount()
            _ = try await store.lastDelivered()
        }
        // The launch's check for audio with no row (`OrphanAudio`), with every file in the folder named.
        let known = try await clock.measure { _ = try await store.knownIDs(among: ids + [DictationID()]) }

        #expect(first.count == 200)
        for time in [page, deep, hit, miss, row, menu, known] {
            #expect(time < .milliseconds(100))
        }
    }

    @Test func aCancelledOrRejectedDictationIsQueuedForRetry() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        let cancelled = record(.cancelled, at: 1_000)
        var rejected = record(.rejected, at: 2_000)
        rejected.rejectReason = .other
        let pasted = record(.pasted)
        for saved in [cancelled, rejected, pasted] {
            try await store.save(saved)
        }

        for saved in [cancelled, rejected, pasted] {
            try await store.queueForRetry(saved.id)
        }

        let queued = try await store.pendingRetries()
        #expect(queued.map(\.id) == [cancelled.id, rejected.id])
        #expect(queued.allSatisfy { $0.status == .failed && $0.rejectReason == nil })
        #expect(try await store.status(of: pasted.id) == .pasted)
    }

    @Test func anUpdateWritesOnlyARowThatStillExists() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var kept = spoken("first try", at: 1_000)
        let deleted = spoken("gone", at: 2_000)
        try await store.save(kept)
        try await store.save(deleted)
        #expect(try await store.delete([deleted.id]).isEmpty)

        kept.status = .recovered
        kept.latency = LatencyLog()
        #expect(try await store.update(kept))
        #expect(try await !store.update(deleted))

        #expect(try await store.page(limit: 10) == [kept])
    }

    @Test func oneRowIsReadOnlyWhenItMatchesTheSearch() async throws {
        let store = try HistoryStore(url: url, audio: audio)
        var saved = spoken("deploy to Vercel", at: 1_000)
        saved.latency = LatencyLog()
        try await store.save(saved)

        #expect(try await store.record(saved.id, matching: "vercel") == saved)
        #expect(try await store.record(saved.id) == saved)
        #expect(try await store.record(saved.id, matching: "netlify") == nil)
        #expect(try await store.record(DictationID()) == nil)
    }
}
