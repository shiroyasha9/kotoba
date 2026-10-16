import Foundation
import KotobaCore
import os

/// The disk space of the audio still kept, for Settings: what "Delete Audio Now…" can delete (dictations with text),
/// and what waits for a retry (dictations without text, kept until sent).
public struct KeptAudioSize: Sendable, Equatable {
    public var deletable: Int64
    public var waiting: Int64

    public init(deletable: Int64 = 0, waiting: Int64 = 0) {
        self.deletable = deletable
        self.waiting = waiting
    }
}

extension Log {
    static let storage = Logger(subsystem: subsystem, category: "storage")
}

/// Audio retention's store side (story 31): deletes the audio files `AudioRetention` finds expired and marks their
/// rows; the rows, their text and the usage ledger stay.
extension HistoryStore {
    /// Rows per batch: a batch holds the actor for two short statements, and a quit loses at most one batch's marks.
    static let audioBatchSize = 500

    private static let transcribed = sqlList(DictationRecord.Status.allCases.filter(\.isTranscribed))
    /// `DictationRecord.isAudioExpired(before:)` in SQL: the rows whose audio is kept, and when they got their text.
    private static let keptAudio = "audio_deleted = 0 AND status IN \(transcribed)"
    private static let transcribedAt = "coalesce(recovered_at, created_at)"

    /// A partial index that holds only the audio still kept (about one period of dictations), in batch order. A change
    /// to `keptAudio` or its columns needs a new index name and the old one dropped here: `IF NOT EXISTS` keeps an
    /// index of the same name as it was.
    static let keptAudioIndex = """
        CREATE INDEX IF NOT EXISTS dictations_kept_audio ON dictations (\(transcribedAt), id) WHERE \(keptAudio);
        """

    /// One batch, oldest text first; `after` adds the cursor's condition as ?3 and ?4.
    static func expiredAudioQuery(after: Bool) -> String {
        """
        SELECT id, audio_path, \(transcribedAt) FROM dictations
        WHERE \(keptAudio) AND \(transcribedAt) < ?1\(after ? " AND (\(transcribedAt), id) > (?3, ?4)" : "")
        ORDER BY \(transcribedAt), id LIMIT ?2;
        """
    }

    /// Reads a batch, removes its files off this actor (a first run can find 10,000; a save must not wait for them),
    /// then marks the rows whose file is gone. A crash between the two leaves rows that the next run finds again.
    @concurrent
    public nonisolated func deleteAudio(transcribedBefore cutoff: Date, after cursor: AudioCursor?) async throws
        -> AudioBatch
    {
        let batch = try await expiredAudio(before: cutoff, after: cursor)
        let gone = batch.filter { Self.removeAudio(at: audioFile(at: $0.path)) }.map(\.cursor.id)
        let deleted = gone.isEmpty ? [] : try await markAudioDeleted(gone)
        return AudioBatch(deleted: deleted, next: batch.count == Self.audioBatchSize ? batch.last?.cursor : nil)
    }

    private func expiredAudio(before cutoff: Date, after cursor: AudioCursor?) throws
        -> [(cursor: AudioCursor, path: String)]
    {
        var values: [Value] = [.real(cutoff.timeIntervalSince1970), .integer(Int64(Self.audioBatchSize))]
        if let cursor {
            values += [.real(cursor.transcribedAt.timeIntervalSince1970), .text(cursor.id.rawValue.uuidString)]
        }
        return try database.query(Self.expiredAudioQuery(after: cursor != nil), values).compactMap { row in
            guard let id = Self.id(row[0]), let path = row[1].string, case .real(let time) = row[2] else { return nil }
            return (AudioCursor(transcribedAt: Date(timeIntervalSince1970: time), id: id), path)
        }
    }

    /// One statement for the batch. Returns the rows it marked; a row the owner deleted meanwhile is not among them.
    private func markAudioDeleted(_ ids: [DictationID]) throws -> Set<DictationID> {
        let marked = try database.query(
            """
            UPDATE dictations SET audio_deleted = 1
            WHERE audio_deleted = 0 AND \(Self.inIDList)
            RETURNING id;
            """,
            [Self.idList(ids)])
        return Self.ids(in: marked)
    }

    /// Many ids as one statement value, ?1 in `inIDList`: the ids (UUID text, nothing to escape) go in as one JSON
    /// array.
    static func idList(_ ids: some Sequence<DictationID>) -> Value {
        .text("[" + ids.map { "\"\($0.rawValue.uuidString)\"" }.joined(separator: ",") + "]")
    }

    static let inIDList = "id IN (SELECT value FROM json_each(?1))"

    static func id(_ value: Value) -> DictationID? {
        value.string.flatMap(UUID.init(uuidString:)).map(DictationID.init)
    }

    /// The ids of rows whose first column is the id.
    static func ids(in rows: [[Value]]) -> Set<DictationID> {
        Set(rows.compactMap { id($0[0]) })
    }

    /// A row's audio file: its name in the audio folder. Retention, Delete and Retry never touch a file outside the
    /// folder, and a row written under another home folder (a restore, Migration Assistant) still finds its file.
    nonisolated func audioFile(at path: String) -> URL {
        Self.audioFile(at: path, in: audioFolder)
    }

    static func audioFile(at path: String, in folder: URL) -> URL {
        folder.appending(path: URL(filePath: path).lastPathComponent)
    }

    /// True when the file is gone: removed now, or not there. Any other failure is logged and the file stays, so its
    /// row stays unmarked and a later run tries again.
    public static func removeAudio(at file: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: file)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            Log.storage.error("Cannot delete audio \(file.lastPathComponent, privacy: .public): \(error)")
            return false
        }
    }

    /// The bytes the file takes on disk: 0 when it is not there, nil when it is there but cannot be measured (the row
    /// keeps no size, so the total is unknown and a later read measures again).
    static func allocatedSize(of file: URL) -> Int64? {
        do {
            return try file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize.map(Int64.init)
        } catch CocoaError.fileReadNoSuchFile {
            return 0
        } catch {
            Log.storage.error("Cannot measure audio \(file.lastPathComponent, privacy: .public): \(error)")
            return nil
        }
    }

    /// Sums the sizes kept with the rows (`save` writes them). Rows from before that column get theirs once, off this
    /// actor, from their files. One aggregate over the rows: about 3 ms for 10,000 (debug build). Nil when a kept file
    /// cannot be measured.
    @concurrent
    public nonisolated func keptAudioSize() async throws -> KeptAudioSize? {
        try await sizeUnsizedAudio()
        return try await summedAudioBytes()
    }

    /// The bytes a run with `cutoff` would delete, for the question Settings asks before a shorter period applies: one
    /// read of the partial index. Nil when one of those files cannot be measured: the question then has no size.
    @concurrent
    public nonisolated func expiringAudioBytes(transcribedBefore cutoff: Date) async throws -> Int64? {
        try await sizeUnsizedAudio()
        return try await summedAudioBytes(transcribedBefore: cutoff)
    }

    private nonisolated func sizeUnsizedAudio() async throws {
        let unsized = try await unsizedAudio()
        let sizes = unsized.compactMap { row in Self.allocatedSize(of: audioFile(at: row.path)).map { (row.id, $0) } }
        guard !sizes.isEmpty else { return }
        try await setAudioBytes(sizes)
    }

    private func unsizedAudio() throws -> [(id: String, path: String)] {
        try database.query("SELECT id, audio_path FROM dictations WHERE audio_deleted = 0 AND audio_bytes IS NULL;")
            .compactMap { row in
                guard let id = row[0].string, let path = row[1].string else { return nil }
                return (id, path)
            }
    }

    private func setAudioBytes(_ sizes: [(id: String, bytes: Int64)]) throws {
        try database.transaction { () throws(SQLiteError) in
            for (id, bytes) in sizes {
                try database.run("UPDATE dictations SET audio_bytes = ?2 WHERE id = ?1;", [.text(id), .integer(bytes)])
            }
        }
    }

    /// `count(*) - count(audio_bytes)`: the rows whose size is unknown.
    private func summedAudioBytes(transcribedBefore cutoff: Date) throws -> Int64? {
        let rows = try database.query(
            """
            SELECT sum(audio_bytes), count(*) - count(audio_bytes) FROM dictations
            WHERE \(Self.keptAudio) AND \(Self.transcribedAt) < ?1;
            """,
            [.real(cutoff.timeIntervalSince1970)])
        guard let row = rows.first, row[1] == .integer(0) else { return nil }
        return row[0].integer ?? 0
    }

    private func summedAudioBytes() throws -> KeptAudioSize? {
        var size = KeptAudioSize()
        let rows = try database.query(
            """
            SELECT status IN \(Self.transcribed), sum(audio_bytes), count(*) - count(audio_bytes) FROM dictations
            WHERE audio_deleted = 0 GROUP BY 1;
            """)
        for row in rows {
            guard row[2] == .integer(0) else { return nil }
            let bytes = row[1].integer ?? 0
            if row[0] == .integer(1) {
                size.deletable = bytes
            } else {
                size.waiting = bytes
            }
        }
        return size
    }
}

/// The History pane's Delete, and the launch's check for audio with no row (`OrphanAudio`).
extension HistoryStore {
    /// Removes the audio files first, off this actor as retention does, then deletes only the rows whose file is gone:
    /// a row whose file cannot be removed stays with its file, so no deleted dictation leaves audio with no row for a
    /// later launch to bring back. The latency marks go with the rows (`ON DELETE CASCADE`). Returns the ids that stay.
    @concurrent
    public nonisolated func delete(_ ids: Set<DictationID>) async throws -> Set<DictationID> {
        guard !ids.isEmpty else { return [] }
        var gone: [DictationID] = []
        var kept: Set<DictationID> = []
        for row in try await keptAudio(of: ids) {
            if let path = row.path, !Self.removeAudio(at: audioFile(at: path)) {
                kept.insert(row.id)
            } else {
                gone.append(row.id)
            }
        }
        if !gone.isEmpty { try await deleteRows(gone) }
        return kept
    }

    /// Each row with its audio path, nil when audio retention already deleted the file.
    private func keptAudio(of ids: Set<DictationID>) throws -> [(id: DictationID, path: String?)] {
        try database.query(
            "SELECT id, audio_path, audio_deleted FROM dictations WHERE \(Self.inIDList);", [Self.idList(ids)]
        ).compactMap { row in
            guard let id = Self.id(row[0]) else { return nil }
            return (id, row[2] == .integer(1) ? nil : row[1].string)
        }
    }

    private func deleteRows(_ ids: [DictationID]) throws {
        try database.run("DELETE FROM dictations WHERE \(Self.inIDList);", [Self.idList(ids)])
    }

    /// The ids among `ids` that have a row, in one statement on the primary key: the launch reads the audio of the
    /// other files only (`OrphanAudio.records`).
    public func knownIDs(among ids: [DictationID]) throws -> Set<DictationID> {
        guard !ids.isEmpty else { return [] }
        return Self.ids(
            in: try database.query(
                "SELECT id FROM dictations WHERE \(Self.inIDList);", [Self.idList(ids)]))
    }
}

/// Discarded recordings whose audio file stayed on disk (`Store.markDiscarded`): an id each, no row and no text, until
/// a launch removes the file (`OrphanAudio.discardedFiles`). The table is empty unless a removal failed.
extension HistoryStore {
    static let discardedSchema = """
        CREATE TABLE IF NOT EXISTS discarded_audio (id TEXT PRIMARY KEY) WITHOUT ROWID;
        """

    public func markDiscarded(_ id: DictationID) throws {
        try database.run(
            "INSERT INTO discarded_audio (id) VALUES (?1) ON CONFLICT DO NOTHING;", [.text(id.rawValue.uuidString)])
    }

    public func discardedIDs() throws -> Set<DictationID> {
        Self.ids(in: try database.query("SELECT id FROM discarded_audio;"))
    }

    /// The launch removed these files, or found them gone.
    public func forgetDiscarded(_ ids: Set<DictationID>) throws {
        guard !ids.isEmpty else { return }
        try database.run("DELETE FROM discarded_audio WHERE \(Self.inIDList);", [Self.idList(ids)])
    }
}
