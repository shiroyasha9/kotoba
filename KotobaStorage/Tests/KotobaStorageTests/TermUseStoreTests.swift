import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Use counts, add dates and pins in `term_use`, which a dictionary save does not rewrite.
struct TermUseStoreTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "dictionary.sqlite") }
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// `DictionaryStore.schema` at v0.1.0.
    static let v010 = """
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

    @Test func a010DictionaryKeepsItsWordsAndTheyAreNotNew() async throws {
        do {
            let database = try SQLiteDatabase(url: url)
            try database.execute(Self.v010)
            try database.execute(
                """
                INSERT INTO dictionary_terms (position, term) VALUES (0, 'PyTorch'), (1, 'zshrc');
                INSERT INTO replacement_rules (position, find, replacement, is_whole_word, is_case_sensitive)
                VALUES (0, 'cloud code', 'Claude Code', 1, 0);
                """)
        }
        let store = try DictionaryStore(url: url)
        let dictionary = try await store.load()

        #expect(dictionary.terms == ["PyTorch", "zshrc", "kotoba"])
        var use = try await store.termUse()
        #expect(use.removeValue(forKey: "kotoba")?.isPinned == true)
        #expect(use == ["pytorch": TermUse(), "zshrc": TermUse(), "claude code": TermUse()])
        // The first save after the update adds only the new word.
        var updated = dictionary
        updated.terms.append("Vercel")
        try await store.save(updated, at: now)
        #expect(try await store.termUse()["pytorch"] == TermUse())
        #expect(try await store.termUse()["vercel"] == TermUse(addedAt: now))
    }

    @Test func theMigrationRunsOnce() async throws {
        let store = try DictionaryStore(url: url)
        try await store.save(PersonalDictionary(terms: ["uv"]), at: now)
        try await store.setPinned("uv", true)

        let reopened = try DictionaryStore(url: url)

        #expect(try await reopened.termUse() == ["uv": TermUse(addedAt: now, isPinned: true)])
    }

    @Test func aSaveKeepsCountsAndPinsAndDropsRemovedWords() async throws {
        let store = try DictionaryStore(url: url)
        try await store.save(PersonalDictionary(terms: ["Mastra", "Codex", "PTE"]), at: now)
        try await store.recordUse(of: ["Mastra", "mastra", "Codex"], at: now + 60)
        try await store.setPinned("PTE", true)

        try await store.save(PersonalDictionary(terms: ["mastra", "PTE"]), at: now + 120)

        #expect(
            try await store.termUse() == [
                "mastra": TermUse(uses: 1, lastUsedAt: now + 60, addedAt: now),
                "pte": TermUse(addedAt: now, isPinned: true),
            ])
    }

    @Test func aWordAddedAgainStartsNew() async throws {
        let store = try DictionaryStore(url: url)
        try await store.save(PersonalDictionary(terms: ["Codex"]), at: now)
        try await store.recordUse(of: ["Codex"], at: now)
        try await store.save(PersonalDictionary(), at: now)

        try await store.save(PersonalDictionary(terms: ["Codex"]), at: now + 60)

        #expect(try await store.termUse() == ["codex": TermUse(addedAt: now + 60)])
    }

    @Test func aRuleReplacementHasItsOwnRow() async throws {
        let store = try DictionaryStore(url: url)
        try await store.save(
            PersonalDictionary(rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")]), at: now)

        try await store.recordUse(of: ["Claude Code"], at: now)

        #expect(try await store.termUse() == ["claude code": TermUse(uses: 1, lastUsedAt: now, addedAt: now)])
    }

    @Test func aHitOnAWordNotInTheDictionaryCountsNothing() async throws {
        let store = try DictionaryStore(url: url)
        let before = try await store.termUse()

        try await store.recordUse(of: ["Gone"], at: now)

        #expect(try await store.termUse() == before)
    }

    @Test func unpinningKeepsTheCount() async throws {
        let store = try DictionaryStore(url: url)
        try await store.save(PersonalDictionary(terms: ["Codex"]), at: now)
        try await store.setPinned("Codex", true)
        try await store.recordUse(of: ["codex"], at: now)

        try await store.setPinned("codex", false)

        #expect(try await store.termUse() == ["codex": TermUse(uses: 1, lastUsedAt: now, addedAt: now)])
    }
}
