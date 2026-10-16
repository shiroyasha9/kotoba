import Foundation
import KotobaCore
import SQLite3

/// Dictation history in system SQLite: kept audio, the retry queue, latency marks, and the usage ledger (one row per
/// billed answer, `UsageLedger.swift`), which deleting history never touches.
/// `scripts/latency.sh` reads `latency_marks` (offsets in ms after key-down) for the latency gate
/// report; keep the schema and file path in step with it.
public actor HistoryStore: Store {
    typealias Value = SQLiteDatabase.Value

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
            reject_reason TEXT,
            app_bundle_id TEXT,
            app_name TEXT,
            audio_deleted INTEGER NOT NULL DEFAULT 0,
            audio_bytes INTEGER,
            cleanup_mode TEXT
        );
        CREATE INDEX IF NOT EXISTS dictations_status ON dictations (status);
        -- The History window's order, newest first.
        CREATE INDEX IF NOT EXISTS dictations_created ON dictations (created_at, id);
        CREATE TABLE IF NOT EXISTS latency_marks (
            dictation_id TEXT NOT NULL REFERENCES dictations (id) ON DELETE CASCADE,
            mark TEXT NOT NULL,
            offset_ms REAL NOT NULL,
            PRIMARY KEY (dictation_id, mark)
        );
        \(ledgerSchema)
        \(discardedSchema)
        """

    /// Columns added after the first build the owner ran; an older database gets them on open.
    private static let addedColumns = [
        ("model", "TEXT"), ("recovered_at", "REAL"), ("cleaned_text", "TEXT"), ("needs_setup", "TEXT"),
        ("mode", "TEXT NOT NULL DEFAULT 'transcript'"), ("reject_reason", "TEXT"), ("app_bundle_id", "TEXT"),
        ("app_name", "TEXT"), ("audio_deleted", "INTEGER NOT NULL DEFAULT 0"), ("audio_bytes", "INTEGER"),
        ("cleanup_mode", "TEXT"),
    ]

    private static let columns = """
        id, created_at, audio_path, audio_duration_ms, transcript, model, status, recovered_at, cleaned_text,
        needs_setup, mode, reject_reason, app_bundle_id, app_name, cleanup_mode
        """
    /// What a read returns: the written columns, then the ones only `deleteAudio` writes.
    private static let readColumns = columns + ", audio_deleted"

    /// SQL lists of statuses, from `DictationRecord.Status`: the retry queue, and the rows whose text reached the
    /// owner.
    private static let retryable = sqlList([.pending, .failed])
    private static let delivered = sqlList([.pasted, .copied])
    /// The kept rows the History pane's Retry puts back in the queue.
    private static let requeued = sqlList([.cancelled, .rejected])
    let database: SQLiteDatabase
    /// Where the audio files are (`DictationPipeline.Settings.audioDirectory`). Every use of a row's audio finds the
    /// file by its name here (`audioFile(at:)`), never by the stored absolute path.
    nonisolated let audioFolder: URL
    /// The history had dictations when it opened: an install from before audio retention, when no period is stored
    /// (`AudioRetention.firstChoice`).
    public nonisolated let hadDictationsAtOpen: Bool

    /// `url` and `audio` have no default: only the app knows where the owner's files are (`AppFiles`), so a test or a
    /// snapshot run cannot open them by leaving an argument out.
    public init(url: URL, audio: URL) throws {
        audioFolder = audio
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: url)
        try database.execute(Self.schema)
        try Self.migrate(database)
        try database.execute("PRAGMA foreign_keys = ON;")
        // Statistics for the planner, so retention reads its partial index (SQLite's advice for each open; a no-op
        // when they are current).
        try database.execute("PRAGMA optimize = 0x10002;")
        hadDictationsAtOpen =
            try database.query("SELECT EXISTS (SELECT 1 FROM dictations);").first?.first
            == .integer(1)
    }

    /// One transaction that also reads the columns, so a quit halfway leaves the old schema for the next launch, and
    /// a second process that opens the file at the same time waits and then finds the work done.
    private static func migrate(_ database: SQLiteDatabase) throws(SQLiteError) {
        try database.transaction { () throws(SQLiteError) in
            let existing = Set(
                try database.query("PRAGMA table_info(dictations);").compactMap { string($0[1]) })
            for (name, type) in addedColumns where !existing.contains(name) {
                try database.execute("ALTER TABLE dictations ADD COLUMN \(name) \(type);")
            }
            try fillLedger(database)
            // After the columns: an older database gets `audio_deleted` above.
            try database.execute(keptAudioIndex)
            // A phase 2 build kept "waits for a key" as needs_key = 1.
            if existing.contains("needs_key") {
                try database.execute(
                    "UPDATE dictations SET needs_setup = 'key' WHERE needs_key = 1 AND needs_setup IS NULL;")
            }
        }
    }

    public func save(_ record: DictationRecord) throws {
        _ = try write(
            record,
            sql: """
                INSERT INTO dictations (\(Self.columns), audio_bytes)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
                ON CONFLICT (id) DO UPDATE SET
                    audio_path = excluded.audio_path, audio_duration_ms = excluded.audio_duration_ms,
                    transcript = excluded.transcript, model = excluded.model, status = excluded.status,
                    recovered_at = excluded.recovered_at, cleaned_text = excluded.cleaned_text,
                    needs_setup = excluded.needs_setup, mode = excluded.mode, reject_reason = excluded.reject_reason,
                    app_bundle_id = excluded.app_bundle_id, app_name = excluded.app_name,
                    cleanup_mode = excluded.cleanup_mode, audio_bytes = excluded.audio_bytes
                RETURNING id;
                """)
    }

    /// The same columns as `save`, in one statement that finds no row once the History pane deleted it.
    public func update(_ record: DictationRecord) throws -> Bool {
        try write(
            record,
            sql: """
                UPDATE dictations SET (
                    audio_path, audio_duration_ms, transcript, model, status, recovered_at, cleaned_text, needs_setup,
                    mode, reject_reason, app_bundle_id, app_name, cleanup_mode, audio_bytes
                ) = (?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
                WHERE id = ?1
                RETURNING id;
                """)
    }

    /// Runs `sql` with the record's columns as ?1-?15 (`columns` order) and the audio file's size as ?16 (one `stat`,
    /// about 10 µs, for the Settings size), then replaces its latency marks, in one
    /// transaction; the record's usage entries go to the ledger even when `sql` wrote no row (the dictation was
    /// deleted during a retry, and the answer was still billed). False when `sql` wrote no row.
    private func write(_ record: DictationRecord, sql: String) throws -> Bool {
        let id = Value.text(record.id.rawValue.uuidString)
        let bytes = Self.allocatedSize(of: record.audio.file).map { Value.integer($0) } ?? .null
        var isWritten = false
        try database.transaction { () throws(SQLiteError) in
            try Self.addToLedger(record.usage, in: database)
            isWritten = try !database.query(
                sql,
                [
                    id, .real(record.createdAt.timeIntervalSince1970), .text(record.audio.file.path),
                    .integer(Int64(record.audio.duration / .milliseconds(1))), Self.text(record.transcript),
                    Self.text(record.model), .text(record.status.rawValue),
                    record.recoveredAt.map { .real($0.timeIntervalSince1970) } ?? .null, Self.text(record.cleanedText),
                    Self.text(record.needsSetup?.rawValue), .text(Self.modeColumn(of: record.output)),
                    Self.text(record.rejectReason?.rawValue), Self.text(record.app?.bundleID),
                    Self.text(record.app?.name), Self.text(record.output.cleanupMode?.rawValue), bytes,
                ]
            ).isEmpty
            guard isWritten else { return }
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
        return isWritten
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

    public func queuedRecord(_ id: DictationID) throws -> DictationRecord? {
        try records(where: "id = ?1 AND status IN \(Self.retryable)", [.text(id.rawValue.uuidString)]).first
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

    public func queueForRetry(_ id: DictationID) throws {
        try database.run(
            "UPDATE dictations SET status = ?2, reject_reason = NULL WHERE id = ?1 AND status IN \(Self.requeued);",
            [.text(id.rawValue.uuidString), .text(DictationRecord.Status.failed.rawValue)])
    }

    /// Number of dictations waiting for a retry, for the menu.
    public func pendingCount() throws -> Int {
        let rows = try database.query("SELECT count(*) FROM dictations WHERE status IN \(Self.retryable);")
        guard case .integer(let count) = rows.first?.first else { return 0 }
        return Int(count)
    }

    func records(
        where condition: String,
        _ values: [Value] = [],
        withLatency: Bool = true
    ) throws -> [DictationRecord] {
        let rows = try database.query("SELECT \(Self.readColumns) FROM dictations WHERE \(condition);", values)
        return try rows.compactMap { row in
            guard var record = Self.record(from: row, audioFolder: audioFolder) else { return nil }
            if withLatency {
                record.latency = try latency(of: record.id)
            }
            return record
        }
    }

    private static func record(from row: [Value], audioFolder: URL) -> DictationRecord? {
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
            audio: RecordedAudio(file: audioFile(at: path, in: audioFolder), duration: .milliseconds(durationMs)),
            transcript: string(row[4]),
            model: string(row[5]),
            status: status,
            recoveredAt: recoveredAt,
            latency: LatencyLog()
        )
        record.cleanedText = string(row[8])
        record.needsSetup = string(row[9]).flatMap(SetupItem.init(rawValue:))
        record.output = output(modeColumn: string(row[10]), cleanupMode: string(row[14]))
        record.rejectReason = string(row[11]).flatMap(RejectReason.init(rawValue:))
        record.app = string(row[12]).map { DictationApp(bundleID: $0, name: string(row[13])) }
        record.isAudioDeleted = row[15] == .integer(1)
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

    static func sqlList(_ statuses: [DictationRecord.Status]) -> String {
        "(" + statuses.map { "'\($0.rawValue)'" }.joined(separator: ", ") + ")"
    }

    private static func text(_ value: String?) -> Value {
        value.map { .text($0) } ?? .null
    }

    private static func string(_ value: Value) -> String? {
        if case .text(let text) = value { text } else { nil }
    }
}

extension HistoryStore {
    /// The `mode` column keeps the values it had before per-app modes, "transcript" or "cleanup"; the mode a cleanup
    /// wrote in is `cleanup_mode`.
    static func modeColumn(of output: DictationOutput) -> String {
        output.cleanupMode == nil ? "transcript" : "cleanup"
    }

    /// A cleanup row from before per-app modes has no `cleanup_mode`: it was cleaned with the Code prompt.
    static func output(modeColumn: String?, cleanupMode: String?) -> DictationOutput {
        modeColumn == "cleanup" ? .cleanup(cleanupMode.flatMap(AppMode.init(rawValue:)) ?? .code) : .transcript
    }
}
