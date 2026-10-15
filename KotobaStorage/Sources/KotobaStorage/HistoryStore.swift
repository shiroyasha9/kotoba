import Foundation
import KotobaCore
import SQLite3

/// Dictation history in system SQLite: kept audio, the retry queue and latency marks.
/// `scripts/latency.sh` reads `latency_marks` (offsets in ms after key-down) for the latency gate
/// report; keep the schema and file path in step with it.
public actor HistoryStore: Store {
    private typealias Value = SQLiteDatabase.Value

    private static let schema = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA busy_timeout = 2000;
        CREATE TABLE IF NOT EXISTS dictations (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            audio_path TEXT NOT NULL,
            audio_duration_ms INTEGER NOT NULL,
            transcript TEXT,
            model TEXT,
            status TEXT NOT NULL,
            recovered_at REAL,
            cleaned_text TEXT,
            needs_setup TEXT,
            mode TEXT NOT NULL DEFAULT 'transcript',
            reject_reason TEXT
        );
        CREATE INDEX IF NOT EXISTS dictations_status ON dictations (status);
        CREATE TABLE IF NOT EXISTS latency_marks (
            dictation_id TEXT NOT NULL REFERENCES dictations (id) ON DELETE CASCADE,
            mark TEXT NOT NULL,
            offset_ms REAL NOT NULL,
            PRIMARY KEY (dictation_id, mark)
        );
        """

    /// Columns added after the first build the owner ran; an older database gets them on open.
    private static let addedColumns = [
        ("model", "TEXT"), ("recovered_at", "REAL"), ("cleaned_text", "TEXT"), ("needs_setup", "TEXT"),
        ("mode", "TEXT NOT NULL DEFAULT 'transcript'"), ("reject_reason", "TEXT"),
    ]

    private static let columns = """
        id, created_at, audio_path, audio_duration_ms, transcript, model, status, recovered_at, cleaned_text,
        needs_setup, mode, reject_reason
        """

    /// SQL lists of statuses, from `DictationRecord.Status`: the retry queue, the rows prune keeps, and the rows whose
    /// text reached the owner.
    private static let retryable = sqlList([.pending, .failed])
    private static let kept = sqlList([.pending, .failed, .rejected])
    private static let delivered = sqlList([.pasted, .copied])

    /// ~/Library/Application Support/kotoba/
    public static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "kotoba", directoryHint: .isDirectory)
    }

    private let database: SQLiteDatabase

    public init(url: URL = directory.appending(path: "kotoba.sqlite")) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: url)
        try database.execute(Self.schema)
        try Self.migrate(database)
        try database.execute("PRAGMA foreign_keys = ON;")
    }

    private static func migrate(_ database: SQLiteDatabase) throws(SQLiteError) {
        let existing = Set(
            try database.query("PRAGMA table_info(dictations);").compactMap { string($0[1]) })
        for (name, type) in addedColumns where !existing.contains(name) {
            try database.execute("ALTER TABLE dictations ADD COLUMN \(name) \(type);")
        }
        // A phase 2 build kept "waits for a key" as needs_key = 1.
        if existing.contains("needs_key") {
            try database.execute(
                "UPDATE dictations SET needs_setup = 'key' WHERE needs_key = 1 AND needs_setup IS NULL;")
        }
    }

    public func save(_ record: DictationRecord) throws {
        let id = Value.text(record.id.rawValue.uuidString)
        try database.transaction { () throws(SQLiteError) in
            try database.run(
                """
                INSERT INTO dictations (\(Self.columns))
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
                ON CONFLICT (id) DO UPDATE SET
                    audio_path = excluded.audio_path, audio_duration_ms = excluded.audio_duration_ms,
                    transcript = excluded.transcript, model = excluded.model, status = excluded.status,
                    recovered_at = excluded.recovered_at, cleaned_text = excluded.cleaned_text,
                    needs_setup = excluded.needs_setup, mode = excluded.mode, reject_reason = excluded.reject_reason;
                """,
                [
                    id, .real(record.createdAt.timeIntervalSince1970), .text(record.audio.file.path),
                    .integer(Int64(record.audio.duration / .milliseconds(1))), Self.text(record.transcript),
                    Self.text(record.model), .text(record.status.rawValue),
                    record.recoveredAt.map { .real($0.timeIntervalSince1970) } ?? .null, Self.text(record.cleanedText),
                    Self.text(record.needsSetup?.rawValue), .text(record.mode.rawValue),
                    Self.text(record.rejectReason?.rawValue),
                ]
            )
            try database.run("DELETE FROM latency_marks WHERE dictation_id = ?1;", [id])
            let marks = record.latency.offsets.sorted { $0.key.rawValue < $1.key.rawValue }
            guard !marks.isEmpty else { return }
            // One statement for all marks of the dictation.
            let rows = Array(repeating: "(?, ?, ?)", count: marks.count).joined(separator: ", ")
            try database.run(
                "INSERT INTO latency_marks (dictation_id, mark, offset_ms) VALUES \(rows);",
                marks.flatMap { mark, offset in [id, .text(mark.rawValue), .real(offset / .milliseconds(1))] }
            )
        }
    }

    public func pendingRetries() throws -> [DictationRecord] {
        try records(where: "status IN \(Self.retryable) ORDER BY created_at")
    }

    /// The newest dictation whose text reached the owner, pasted or left on the clipboard, for "Fix Last Dictation…".
    /// Its `deliveredText` is the string the pipeline pasted. "Last" is the last one spoken
    /// (`created_at`): a recovered dictation copied later does not count as newer.
    public func lastDelivered() throws -> DictationRecord? {
        try records(
            where: "status IN \(Self.delivered) ORDER BY created_at DESC LIMIT 1", withLatency: false
        ).first
    }

    public func status(of id: DictationID) throws -> DictationRecord.Status? {
        let rows = try database.query("SELECT status FROM dictations WHERE id = ?1;", [.text(id.rawValue.uuidString)])
        guard case .text(let status) = rows.first?.first else { return nil }
        return DictationRecord.Status(rawValue: status)
    }

    public func recovered(since cutoff: Date) throws -> [DictationRecord] {
        try records(
            where: "status = ?2 AND recovered_at >= ?1 ORDER BY recovered_at DESC",
            [.real(cutoff.timeIntervalSince1970), .text(DictationRecord.Status.recovered.rawValue)],
            withLatency: false
        )
    }

    public func markCopied(_ id: DictationID) throws {
        try database.run(
            "UPDATE dictations SET status = ?2 WHERE id = ?1;",
            [.text(id.rawValue.uuidString), .text(DictationRecord.Status.copied.rawValue)]
        )
    }

    public func prune(olderThan cutoff: Date) throws {
        let deleted = try database.query(
            "DELETE FROM dictations WHERE created_at < ?1 AND status NOT IN \(Self.kept) RETURNING audio_path;",
            [.real(cutoff.timeIntervalSince1970)]
        )
        for case .text(let path) in deleted.map({ $0[0] }) {
            try? FileManager.default.removeItem(atPath: path)  // A file already gone is fine.
        }
    }

    /// Number of dictations waiting for a retry, for the menu.
    public func pendingCount() throws -> Int {
        let rows = try database.query("SELECT count(*) FROM dictations WHERE status IN \(Self.retryable);")
        guard case .integer(let count) = rows.first?.first else { return 0 }
        return Int(count)
    }

    private func records(
        where condition: String,
        _ values: [Value] = [],
        withLatency: Bool = true
    ) throws -> [DictationRecord] {
        let rows = try database.query("SELECT \(Self.columns) FROM dictations WHERE \(condition);", values)
        return try rows.compactMap { row in
            guard var record = Self.record(from: row) else { return nil }
            if withLatency {
                record.latency = try latency(of: record.id)
            }
            return record
        }
    }

    private static func record(from row: [Value]) -> DictationRecord? {
        guard
            case .text(let idText) = row[0], let uuid = UUID(uuidString: idText),
            case .real(let createdAt) = row[1],
            case .text(let path) = row[2],
            case .integer(let durationMs) = row[3],
            case .text(let statusText) = row[6], let status = DictationRecord.Status(rawValue: statusText)
        else { return nil }
        let recoveredAt: Date? = if case .real(let time) = row[7] { Date(timeIntervalSince1970: time) } else { nil }
        var record = DictationRecord(
            id: DictationID(rawValue: uuid),
            createdAt: Date(timeIntervalSince1970: createdAt),
            audio: RecordedAudio(file: URL(filePath: path), duration: .milliseconds(durationMs)),
            transcript: string(row[4]),
            model: string(row[5]),
            status: status,
            recoveredAt: recoveredAt,
            latency: LatencyLog()
        )
        record.cleanedText = string(row[8])
        record.needsSetup = string(row[9]).flatMap(SetupItem.init(rawValue:))
        record.mode = string(row[10]).flatMap(DictationMode.init(rawValue:)) ?? .transcript
        record.rejectReason = string(row[11]).flatMap(RejectReason.init(rawValue:))
        return record
    }

    private func latency(of id: DictationID) throws -> LatencyLog {
        var log = LatencyLog()
        let rows = try database.query(
            "SELECT mark, offset_ms FROM latency_marks WHERE dictation_id = ?1;", [.text(id.rawValue.uuidString)])
        for row in rows {
            guard case .text(let name) = row[0], let mark = LatencyMark(rawValue: name),
                case .real(let milliseconds) = row[1]
            else { continue }
            log.record(mark, offset: .milliseconds(milliseconds))
        }
        return log
    }

    private static func sqlList(_ statuses: [DictationRecord.Status]) -> String {
        "(" + statuses.map { "'\($0.rawValue)'" }.joined(separator: ", ") + ")"
    }

    private static func text(_ value: String?) -> Value {
        value.map { .text($0) } ?? .null
    }

    private static func string(_ value: Value) -> String? {
        if case .text(let text) = value { text } else { nil }
    }
}
