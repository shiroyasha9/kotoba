import Foundation
import KotobaCore

/// The personal dictionary in its own SQLite file next to the history database. A separate file keeps a dictionary
/// write from holding the lock a dictation save needs. The dictionary is small, so a save rewrites it whole.
///
/// Suggestions learned from corrections live in `dictionary_suggestions`, which a dictionary save does not rewrite:
/// a pair the owner dismissed stays dismissed (docs/research/auto-learning.md 4.3-4.4). Use counts and pins live in
/// `term_use` for the same reason (`DictionaryTermUse.swift`).
public actor DictionaryStore {
    public static let maxPendingSuggestions = 20
    /// A pending suggestion not seen again for this long is dropped (not dismissed: seen later, it comes back).
    public static let suggestionLifetime: TimeInterval = 30 * 24 * 60 * 60
    /// The app's own name, pinned in every dictionary once: unlisted, MAI wrote "kotoba" as "Codex" (owner, 2026-10-25).
    private static let appTerms = ["kotoba"]

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
        CREATE TABLE IF NOT EXISTS dictionary_suggestions (
            id TEXT PRIMARY KEY,
            heard TEXT NOT NULL,
            corrected TEXT NOT NULL,
            proposes TEXT NOT NULL,
            origin TEXT NOT NULL,
            app_bundle_id TEXT,
            evidence INTEGER NOT NULL,
            first_seen_at REAL NOT NULL,
            last_seen_at REAL NOT NULL,
            status TEXT NOT NULL,
            pair_key TEXT,
            is_strong INTEGER NOT NULL DEFAULT 1
        );
        """

    /// After the migration, so a table from an earlier build has `pair_key` filled first.
    private static let pairIndex = """
        DROP INDEX IF EXISTS dictionary_suggestions_pair;
        CREATE UNIQUE INDEX IF NOT EXISTS dictionary_suggestions_pair_key ON dictionary_suggestions (pair_key);
        """

    private static let suggestionColumns =
        "id, heard, corrected, proposes, origin, app_bundle_id, evidence, first_seen_at, last_seen_at, status"

    /// Internal for the extensions in other files (`DictionaryTermUse.swift`); only this actor uses it.
    let database: SQLiteDatabase

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: url)
        try database.execute(Self.schema)
        try Self.migrateSuggestions(database)
        try database.execute(Self.pairIndex)
        try Self.migrateTermUse(database)
        try Self.addAppTerms(database)
    }

    /// Once per database (`user_version` 0 to 1): each of `appTerms` the dictionary does not send yet goes at its end,
    /// pinned. A term the owner removes later stays removed.
    private static func addAppTerms(_ database: SQLiteDatabase, at now: Date = .now) throws(SQLiteError) {
        guard try database.userVersion() == 0 else { return }
        try database.transaction { () throws(SQLiteError) in
            var dictionary = try load(database)
            let added = appTerms.filter { !dictionary.keytermKeys.contains(TermUse.key(for: $0)) }
            dictionary.terms += added
            try write(dictionary, to: database)
            try writeTermUse(of: dictionary, at: now, to: database)
            for term in added {
                try setPinned(term, true, in: database)
            }
            try database.setUserVersion(1)
        }
    }

    /// A suggestion table from an earlier build matched pairs with SQLite's `lower()`, which folds ASCII only; the
    /// key is now Swift's `lowercased()` (`SuggestionPair`), written by kotoba.
    private static func migrateSuggestions(_ database: SQLiteDatabase) throws(SQLiteError) {
        let columns = Set(try database.query("PRAGMA table_info(dictionary_suggestions);").compactMap { $0[1].string })
        if !columns.contains("is_strong") {
            try database.execute("ALTER TABLE dictionary_suggestions ADD COLUMN is_strong INTEGER NOT NULL DEFAULT 1;")
        }
        if !columns.contains("pair_key") {
            try database.execute("ALTER TABLE dictionary_suggestions ADD COLUMN pair_key TEXT;")
        }
        var seen: Set<String> = []
        for row in try database.query("SELECT id, heard, corrected FROM dictionary_suggestions WHERE pair_key IS NULL;")
        {
            guard let id = row[0].string, let heard = row[1].string, let corrected = row[2].string else { continue }
            let key = pairKey(SuggestionPair(heard: heard, corrected: corrected))
            if seen.insert(key).inserted {
                try database.run(
                    "UPDATE dictionary_suggestions SET pair_key = ?2 WHERE id = ?1;", [.text(id), .text(key)])
            } else {
                // Two rows that only Unicode case told apart: keep the first.
                try database.run("DELETE FROM dictionary_suggestions WHERE id = ?1;", [.text(id)])
            }
        }
    }

    private static func pairKey(_ pair: SuggestionPair) -> String {
        pair.heard + "\u{1F}" + pair.corrected
    }

    public func load() throws -> PersonalDictionary {
        try Self.load(database)
    }

    /// Static for the migration, which runs before the actor is set up.
    static func load(_ database: SQLiteDatabase) throws(SQLiteError) -> PersonalDictionary {
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

    /// Saves the whole dictionary. `ids` are suggestions the owner just added. `candidates` are corrections the owner
    /// checked and added directly ("Fix Last Dictation…"): they are stored as added, also over an earlier dismissal.
    /// An added suggestion whose entries are no longer in `dictionary` was deleted by the owner, so it becomes
    /// dismissed and never returns.
    public func save(
        _ dictionary: PersonalDictionary,
        markingAdded ids: [UUID] = [],
        recordingAdded candidates: [SuggestionCandidate] = [],
        at now: Date = .now
    ) throws {
        try database.transaction { () throws(SQLiteError) in
            try Self.write(dictionary, to: database)
            try Self.writeTermUse(of: dictionary, at: now, to: database)
            for id in ids {
                try setStatus(.added, of: id)
            }
            for candidate in candidates {
                try record(candidate, as: .added, at: now)
            }
            for suggestion in try suggestions(where: "status = ?1", [.text(DictionarySuggestion.Status.added.rawValue)])
            where !dictionary.contains(suggestion.candidate) {
                try setStatus(.dismissed, of: suggestion.id)
            }
        }
    }

    // MARK: Dictionary rows

    /// Static for the migration, which runs before the actor is set up.
    private static func write(_ dictionary: PersonalDictionary, to database: SQLiteDatabase) throws(SQLiteError) {
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

// MARK: - Suggestions

extension DictionaryStore {
    /// Counts a correction: a new pair is pending with evidence 1, a pending pair counts up. Nil when the owner already
    /// added or dismissed this pair. A weak correction (both sides common words) shows only once it was seen twice;
    /// one strong sighting shows it at once (lead decision 2026-10-16).
    public func record(_ candidate: SuggestionCandidate, isStrong: Bool = true, at now: Date) throws
        -> DictionarySuggestion?
    {
        var recorded: DictionarySuggestion?
        try database.transaction { () throws(SQLiteError) in
            try expireSuggestions(at: now)
            if let suggestion = try match(candidate) {
                guard suggestion.status == .pending else { return }
                recorded = try countUp(suggestion, seenAgainAs: candidate, isStrong: isStrong, at: now)
                return
            }
            let suggestion = DictionarySuggestion(candidate: candidate, firstSeenAt: now, lastSeenAt: now)
            try insert(suggestion, isStrong: isStrong)
            // Over the limit, the shown suggestion seen least recently goes. A weak pair not shown yet does not count;
            // it expires like the others.
            try database.run(
                """
                DELETE FROM dictionary_suggestions WHERE id IN (
                    SELECT id FROM dictionary_suggestions WHERE status = ?2 AND \(Self.isShown)
                    ORDER BY last_seen_at DESC LIMIT -1 OFFSET ?1);
                """,
                [.integer(Int64(Self.maxPendingSuggestions)), .text(DictionarySuggestion.Status.pending.rawValue)]
            )
            recorded = suggestion
        }
        return recorded
    }

    /// A pending pair shows when it is strong, or weak and seen twice (lead decision 2026-10-16).
    private static let isShown = "(is_strong = 1 OR evidence >= 2)"

    /// Pending suggestions ready to show, the most seen first: strong ones, and weak ones seen twice or more.
    public func pendingSuggestions(at now: Date) throws -> [DictionarySuggestion] {
        try expireSuggestions(at: now)
        return try suggestions(
            where: "status = ?1 AND \(Self.isShown) ORDER BY evidence DESC, last_seen_at DESC",
            [.text(DictionarySuggestion.Status.pending.rawValue)]
        )
    }

    /// Words learned from corrections that are still in the dictionary, by where the correction came from (the
    /// Activity page): an added word the owner deleted is dismissed, so it no longer counts.
    public func learnedWords() throws -> [SuggestionCandidate.Origin: Int] {
        let rows = try database.query(
            "SELECT origin, count(*) FROM dictionary_suggestions WHERE status = ?1 GROUP BY origin;",
            [.text(DictionarySuggestion.Status.added.rawValue)])
        return Dictionary(
            uniqueKeysWithValues: rows.compactMap { row in
                row[0].string.flatMap(SuggestionCandidate.Origin.init(rawValue:)).map { ($0, Int(row[1].integer ?? 0)) }
            })
    }

    /// Pairs the owner dismissed, which a detector must never suggest again.
    public func dismissedPairs() throws -> Set<SuggestionPair> {
        Set(
            try suggestions(where: "status = ?1", [.text(DictionarySuggestion.Status.dismissed.rawValue)])
                .map(\.candidate.pair))
    }

    public func dismiss(_ ids: [UUID]) throws {
        try database.transaction { () throws(SQLiteError) in
            for id in ids {
                try setStatus(.dismissed, of: id)
            }
        }
    }

    /// Corrections the owner saw and unchecked ("Fix Last Dictation…"): dismissed whether they were suggested or not.
    public func dismiss(_ candidates: [SuggestionCandidate], at now: Date) throws {
        try database.transaction { () throws(SQLiteError) in
            for candidate in candidates {
                try record(candidate, as: .dismissed, at: now)
            }
        }
    }

    /// Stores `candidate` with `status`, counting up a pair already here.
    private func record(_ candidate: SuggestionCandidate, as status: DictionarySuggestion.Status, at now: Date)
        throws(SQLiteError)
    {
        if let existing = try match(candidate) {
            _ = try countUp(existing, seenAgainAs: candidate, isStrong: true, at: now)
            try setStatus(status, of: existing.id)
        } else {
            let suggestion = DictionarySuggestion(
                candidate: candidate, firstSeenAt: now, lastSeenAt: now, status: status)
            try insert(suggestion, isStrong: true)
        }
    }

    private func match(_ candidate: SuggestionCandidate) throws(SQLiteError) -> DictionarySuggestion? {
        try suggestions(where: "pair_key = ?1", [.text(Self.pairKey(candidate.pair))]).first
    }

    private func insert(_ suggestion: DictionarySuggestion, isStrong: Bool) throws(SQLiteError) {
        let candidate = suggestion.candidate
        try database.run(
            """
            INSERT INTO dictionary_suggestions (\(Self.suggestionColumns), pair_key, is_strong)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12);
            """,
            [
                .text(suggestion.id.uuidString), .text(candidate.heard), .text(candidate.corrected),
                .text(candidate.proposes.rawValue), .text(candidate.origin.rawValue), .nullable(candidate.appBundleID),
                .integer(Int64(suggestion.evidence)), .real(suggestion.firstSeenAt.timeIntervalSince1970),
                .real(suggestion.lastSeenAt.timeIntervalSince1970), .text(suggestion.status.rawValue),
                .text(Self.pairKey(candidate.pair)), .integer(isStrong ? 1 : 0),
            ]
        )
    }

    private func countUp(
        _ suggestion: DictionarySuggestion, seenAgainAs candidate: SuggestionCandidate, isStrong: Bool, at now: Date
    ) throws(SQLiteError) -> DictionarySuggestion {
        var suggestion = suggestion
        suggestion.evidence += 1
        suggestion.lastSeenAt = now
        suggestion.candidate.proposes = candidate.proposes
        suggestion.candidate.appBundleID = candidate.appBundleID ?? suggestion.candidate.appBundleID
        try database.run(
            """
            UPDATE dictionary_suggestions
            SET evidence = ?2, last_seen_at = ?3, proposes = ?4, app_bundle_id = ?5, is_strong = is_strong OR ?6
            WHERE id = ?1;
            """,
            [
                .text(suggestion.id.uuidString), .integer(Int64(suggestion.evidence)),
                .real(now.timeIntervalSince1970), .text(suggestion.candidate.proposes.rawValue),
                .nullable(suggestion.candidate.appBundleID), .integer(isStrong ? 1 : 0),
            ]
        )
        return suggestion
    }

    private func expireSuggestions(at now: Date) throws(SQLiteError) {
        try database.run(
            "DELETE FROM dictionary_suggestions WHERE status = ?2 AND last_seen_at < ?1;",
            [
                .real(now.timeIntervalSince1970 - Self.suggestionLifetime),
                .text(DictionarySuggestion.Status.pending.rawValue),
            ]
        )
    }

    private func setStatus(_ status: DictionarySuggestion.Status, of id: UUID) throws(SQLiteError) {
        try database.run(
            "UPDATE dictionary_suggestions SET status = ?2 WHERE id = ?1;",
            [.text(id.uuidString), .text(status.rawValue)])
    }

    private func suggestions(where condition: String, _ values: [SQLiteDatabase.Value] = []) throws(SQLiteError)
        -> [DictionarySuggestion]
    {
        try database.query("SELECT \(Self.suggestionColumns) FROM dictionary_suggestions WHERE \(condition);", values)
            .compactMap { row in
                guard let id = row[0].string.flatMap(UUID.init(uuidString:)),
                    let heard = row[1].string, let corrected = row[2].string,
                    let proposes = row[3].string.flatMap(SuggestionCandidate.Proposal.init(rawValue:)),
                    let origin = row[4].string.flatMap(SuggestionCandidate.Origin.init(rawValue:)),
                    case .integer(let evidence) = row[6], case .real(let firstSeen) = row[7],
                    case .real(let lastSeen) = row[8],
                    let status = row[9].string.flatMap(DictionarySuggestion.Status.init(rawValue:))
                else { return nil }
                return DictionarySuggestion(
                    id: id,
                    candidate: SuggestionCandidate(
                        heard: heard, corrected: corrected, proposes: proposes, origin: origin,
                        appBundleID: row[5].string),
                    evidence: Int(evidence),
                    firstSeenAt: Date(timeIntervalSince1970: firstSeen),
                    lastSeenAt: Date(timeIntervalSince1970: lastSeen),
                    status: status
                )
            }
    }
}
