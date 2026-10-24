import Foundation
import KotobaCore

/// The history's tables and indexes, and the steps that bring a database from any shipped build to them
/// (AGENTS.md "Migrations"; `HistoryMigrationTests` opens each shipped shape).
extension HistoryStore {
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
            cleanup_mode TEXT,
            polished_text TEXT,
            attempts INTEGER NOT NULL DEFAULT 0
        );
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
        ("cleanup_mode", "TEXT"), ("polished_text", "TEXT"), ("attempts", "INTEGER NOT NULL DEFAULT 0"),
    ]

    /// The retry queue's and the menu's recovered dictations' indexes: partial, so each holds only the rows its read
    /// wants, and the planner takes it with or without statistics (a new install has none until a later launch's
    /// `PRAGMA optimize`). `dictations_status` (to 0.4.6) held every row by status; with no statistics the planner
    /// took it to be selective and sorted every delivered row for Fix Last Dictation and every kept row for retention.
    static let readIndexes = """
        DROP INDEX IF EXISTS dictations_status;
        CREATE INDEX IF NOT EXISTS dictations_retry ON dictations (created_at) WHERE status IN \(retryable);
        CREATE INDEX IF NOT EXISTS dictations_recovered ON dictations (recovered_at) WHERE \(isRecovered);
        """

    /// Creates what a new database lacks, then migrates an older one.
    static func prepare(_ database: SQLiteDatabase) throws(SQLiteError) {
        try database.execute(schema)
        try migrate(database)
    }

    /// One transaction that also reads the columns, so a quit halfway leaves the old schema for the next launch, and
    /// a second process that opens the file at the same time waits and then finds the work done.
    private static func migrate(_ database: SQLiteDatabase) throws(SQLiteError) {
        try database.transaction { () throws(SQLiteError) in
            let existing = Set(
                try database.query("PRAGMA table_info(dictations);").compactMap { $0[1].string })
            for (name, type) in addedColumns where !existing.contains(name) {
                try database.execute("ALTER TABLE dictations ADD COLUMN \(name) \(type);")
            }
            try fillLedger(database)
            // After the columns: an older database gets `audio_deleted` and `recovered_at` above.
            try database.execute(keptAudioIndex)
            try database.execute(keptSizeIndexes)
            try database.execute(readIndexes)
            // A phase 2 build kept "waits for a key" as needs_key = 1.
            if existing.contains("needs_key") {
                try database.execute(
                    "UPDATE dictations SET needs_setup = 'key' WHERE needs_key = 1 AND needs_setup IS NULL;")
            }
        }
    }
}
