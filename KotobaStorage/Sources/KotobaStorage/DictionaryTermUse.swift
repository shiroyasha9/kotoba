import Foundation
import KotobaCore

/// How the owner uses each keyterm (`TermUse`): one row per `TermUse.key(for:)` in `term_use`. A dictionary save
/// rewrites `dictionary_terms`, so the counts, add dates and pins live here: a save adds a row for each new keyterm and
/// drops the rows of keyterms no longer in the dictionary, and keeps the rest as they are.
extension DictionaryStore {
    private static let termUseSchema = """
        CREATE TABLE term_use (
            term_key TEXT PRIMARY KEY,
            uses INTEGER NOT NULL DEFAULT 0,
            last_used_at REAL,
            added_at REAL,
            is_pinned INTEGER NOT NULL DEFAULT 0
        );
        """

    /// New in 0.2.0. A dictionary from 0.1.0 gets a row for each keyterm with no add date, so the first save after the
    /// update does not count its terms as new.
    static func migrateTermUse(_ database: SQLiteDatabase) throws(SQLiteError) {
        let tables = try database.query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'term_use';")
        guard tables.isEmpty else { return }
        try database.transaction { () throws(SQLiteError) in
            try database.execute(termUseSchema)
            for key in try load(database).keytermKeys {
                try database.run("INSERT INTO term_use (term_key) VALUES (?1);", [.text(key)])
            }
        }
    }

    /// Every keyterm's use, by key.
    public func termUse() throws -> [String: TermUse] {
        let rows = try database.query("SELECT term_key, uses, last_used_at, added_at, is_pinned FROM term_use;")
        return Dictionary(
            rows.compactMap { row -> (String, TermUse)? in
                guard let key = row[0].string else { return nil }
                return (
                    key,
                    TermUse(
                        uses: Int(row[1].integer ?? 0), lastUsedAt: row[2].date, addedAt: row[3].date,
                        isPinned: row[4].integer == 1)
                )
            },
            uniquingKeysWith: { first, _ in first })
    }

    /// Counts one delivered dictation for each term its text has (`TermReport.hits`). A term no longer in the
    /// dictionary has no row, so it counts nothing.
    public func recordUse(of terms: [String], at time: Date) throws {
        try database.transaction { () throws(SQLiteError) in
            for key in Set(terms.map(TermUse.key(for:))) {
                try database.run(
                    "UPDATE term_use SET uses = uses + 1, last_used_at = ?2 WHERE term_key = ?1;",
                    [.text(key), .real(time.timeIntervalSince1970)])
            }
        }
    }

    /// The owner's star in the Dictionary pane: a pinned term is always sent.
    public func setPinned(_ term: String, _ isPinned: Bool) throws {
        try database.run(
            """
            INSERT INTO term_use (term_key, is_pinned) VALUES (?1, ?2)
            ON CONFLICT (term_key) DO UPDATE SET is_pinned = excluded.is_pinned;
            """,
            [.text(TermUse.key(for: term)), .integer(isPinned ? 1 : 0)])
    }

    /// In the save's transaction: a new keyterm is added at `now`; a keyterm the owner removed takes its count and
    /// pin with it, so the word added again later starts new.
    func writeTermUse(of dictionary: PersonalDictionary, at now: Date) throws(SQLiteError) {
        let keys = dictionary.keytermKeys
        let stored = Set(try database.query("SELECT term_key FROM term_use;").compactMap { $0[0].string })
        for key in stored.subtracting(keys) {
            try database.run("DELETE FROM term_use WHERE term_key = ?1;", [.text(key)])
        }
        for key in keys.subtracting(stored) {
            try database.run(
                "INSERT INTO term_use (term_key, added_at) VALUES (?1, ?2);",
                [.text(key), .real(now.timeIntervalSince1970)])
        }
    }
}
