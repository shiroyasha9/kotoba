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

    /// An index of the history as `sqlite_master` keeps its SQL: `CREATE INDEX <name> <definition>`, with no
    /// `IF NOT EXISTS`.
    struct HistoryIndex {
        let name: String
        let sql: String

        init(_ name: String, _ definition: String) {
            self.name = name
            sql = "CREATE INDEX \(name) \(definition)"
        }
    }

    /// Every index of the history's tables. Each open makes the database match this list (`syncIndexes`), so a change
    /// to an index (its columns or its condition) is a change here and nothing more: SQLite keeps a changed index
    /// under its old name.
    static let indexes =
        [
            // The History window's order, newest first.
            HistoryIndex("dictations_created", "ON dictations (created_at, id)"),
            HistoryIndex("usage_ledger_time", "ON usage_ledger (time)"),
        ] + audioIndexes + readIndexes

    /// The tables whose indexes `indexes` lists in full: an index on them that is not in it is dropped.
    private static let indexedTables: Set = ["dictations", "latency_marks", "usage_ledger", "discarded_audio"]

    /// The retry queue's and the menu's recovered dictations' indexes: partial, so each holds only the rows its read
    /// wants, and the planner takes it with or without statistics (a new install has none until a later launch's
    /// `PRAGMA optimize`). `dictations_status` (to 0.4.6) held every row by status; with no statistics the planner
    /// took it to be selective and sorted every delivered row for Fix Last Dictation and every kept row for retention.
    static let readIndexes = [
        HistoryIndex("dictations_retry", "ON dictations (created_at) WHERE status IN \(retryable)"),
        HistoryIndex("dictations_recovered", "ON dictations (recovered_at) WHERE \(isRecovered)"),
    ]

    /// An index built in the database: its table and its SQL.
    struct BuiltIndex: Equatable {
        let table: String
        let sql: String
    }

    /// The named indexes in `database`, on any table, so a listed index is seen wherever it is.
    static func builtIndexes(in database: SQLiteDatabase) throws(SQLiteError) -> [String: BuiltIndex] {
        var built: [String: BuiltIndex] = [:]
        for row in try database.query(
            "SELECT name, tbl_name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL;")
        {
            if let name = row[0].string, let table = row[1].string, let sql = row[2].string {
                built[name] = BuiltIndex(table: table, sql: sql)
            }
        }
        return built
    }

    /// What an open does to the `built` indexes to match `indexes`. It drops an index on the history's tables whose
    /// SQL differs or that the list does not have (a changed condition under the same name, an older build's, or one
    /// a downgraded build made again, as 0.4.6 makes `dictations_status`), and builds each listed one that is missing
    /// or dropped. A unique index the list does not have stays: a later build's, whose rule a downgrade must keep.
    static func indexChanges(built: [String: BuiltIndex]) -> (drop: [String], create: [HistoryIndex]) {
        let wanted = Dictionary(uniqueKeysWithValues: indexes.map { ($0.name, $0.sql) })
        let drop = built.filter { name, index in
            guard let sql = wanted[name] else {
                return indexedTables.contains(index.table) && !index.sql.hasPrefix("CREATE UNIQUE INDEX")
            }
            return sql != index.sql
        }
        return (drop.keys.sorted(), indexes.filter { built[$0.name]?.sql != $0.sql })
    }

    /// An open that finds the indexes as listed reads `sqlite_master` and writes nothing.
    private static func syncIndexes(_ database: SQLiteDatabase) throws(SQLiteError) {
        let changes = indexChanges(built: try builtIndexes(in: database))
        for name in changes.drop {
            try database.execute("DROP INDEX \"\(name)\";")
        }
        for index in changes.create {
            try database.execute(index.sql + ";")
        }
    }

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
            try syncIndexes(database)
            // A phase 2 build kept "waits for a key" as needs_key = 1.
            if existing.contains("needs_key") {
                try database.execute(
                    "UPDATE dictations SET needs_setup = 'key' WHERE needs_key = 1 AND needs_setup IS NULL;")
            }
        }
    }
}
