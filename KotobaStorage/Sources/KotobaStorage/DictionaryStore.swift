import Foundation
import KotobaCore

/// The personal dictionary in its own SQLite file next to the history database. A separate file keeps a dictionary
/// write from holding the lock a dictation save needs. The dictionary is small, so a save rewrites it whole.
public actor DictionaryStore {
    private static let schema = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS dictionary_terms (
            position INTEGER PRIMARY KEY,
            term TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS replacement_rules (
            position INTEGER PRIMARY KEY,
            find TEXT NOT NULL,
            replacement TEXT NOT NULL,
            is_whole_word INTEGER NOT NULL,
            is_case_sensitive INTEGER NOT NULL
        );
        """

    private let database: SQLiteDatabase

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: url)
        try database.execute(Self.schema)
    }

    public func load() throws -> PersonalDictionary {
        let terms = try database.query("SELECT term FROM dictionary_terms ORDER BY position;").compactMap { row in
            if case .text(let term) = row[0] { term } else { nil }
        }
        let rules = try database.query(
            """
            SELECT find, replacement, is_whole_word, is_case_sensitive FROM replacement_rules ORDER BY position;
            """
        ).compactMap { row -> ReplacementRule? in
            guard case .text(let find) = row[0], case .text(let replacement) = row[1],
                case .integer(let isWholeWord) = row[2], case .integer(let isCaseSensitive) = row[3]
            else { return nil }
            return ReplacementRule(
                find: find, replacement: replacement, isWholeWord: isWholeWord != 0,
                isCaseSensitive: isCaseSensitive != 0)
        }
        return PersonalDictionary(terms: terms, rules: rules)
    }

    public func save(_ dictionary: PersonalDictionary) throws {
        try database.transaction { () throws(SQLiteError) in
            try database.execute("DELETE FROM dictionary_terms; DELETE FROM replacement_rules;")
            for (position, term) in dictionary.terms.enumerated() {
                try database.run(
                    "INSERT INTO dictionary_terms (position, term) VALUES (?1, ?2);",
                    [.integer(Int64(position)), .text(term)]
                )
            }
            for (position, rule) in dictionary.rules.enumerated() {
                try database.run(
                    """
                    INSERT INTO replacement_rules (position, find, replacement, is_whole_word, is_case_sensitive)
                    VALUES (?1, ?2, ?3, ?4, ?5);
                    """,
                    [
                        .integer(Int64(position)), .text(rule.find), .text(rule.replacement),
                        .integer(rule.isWholeWord ? 1 : 0), .integer(rule.isCaseSensitive ? 1 : 0),
                    ]
                )
            }
        }
    }
}
