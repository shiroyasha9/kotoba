import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The Wispr Flow import (story 26) against fixture databases with Wispr's `Dictionary` schema.
struct WisprFlowImportTests {
    let folder = TemporaryFolder()

    // MARK: Finding the database

    @Test func theDatabaseIsFoundInApplicationSupport() throws {
        let support = folder.url.appending(path: "Application Support")
        let database = try makeFile(support.appending(path: "Wispr Flow/flow.sqlite"))
        try makeFile(support.appending(path: "Wispr Flow/backups/.backup-2026-10-14.sqlite"))

        let found = WisprFlowImport.locate(
            applicationSupport: support, containers: folder.url.appending(path: "Containers"))

        #expect(found == database)
    }

    @Test func theDatabaseIsFoundInASandboxContainer() throws {
        let containers = folder.url.appending(path: "Containers")
        let database = try makeFile(
            containers.appending(
                path: "com.electron.wispr-flow/Data/Library/Application Support/Wispr Flow/flow.sqlite"))

        let found = WisprFlowImport.locate(
            applicationSupport: folder.url.appending(path: "Application Support"), containers: containers)

        #expect(found == database)
    }

    @Test func noWisprFolderFindsNothing() throws {
        let support = folder.url.appending(path: "Application Support")
        try makeFile(support.appending(path: "Other App/flow.sqlite"))

        #expect(WisprFlowImport.locate(applicationSupport: support, containers: support) == nil)
    }

    // MARK: Reading the dictionary

    @Test func liveWordsBecomeTermsAndReplacementsBecomeRules() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "PyTorch")
        try fixture.insert(phrase: "cloud code", replacement: "Claude Code")
        try fixture.insert(phrase: "deleted word", isDeleted: .integer(1))
        try fixture.insert(phrase: "deleted rule", replacement: "x", isDeleted: .integer(1))
        try fixture.insert(phrase: "  ")
        fixture.close()

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary.terms == ["PyTorch"])
        #expect(imported.dictionary.rules == [ReplacementRule(find: "cloud code", replacement: "Claude Code")])
    }

    @Test(arguments: [SQLiteDatabase.Value.text("0"), .text("false")])
    func otherSpellingsOfNotDeletedAreLive(isDeleted: SQLiteDatabase.Value) async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "live", isDeleted: isDeleted)
        try fixture.insert(phrase: "gone", isDeleted: .text("true"))
        fixture.close()

        #expect(try await WisprFlowImport.read(from: url).dictionary.terms == ["live"])
    }

    @Test func personalAndTeamCopiesOfAWordImportOnce() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "zod")
        try fixture.insert(phrase: "zod", team: "11111111-1111-1111-1111-111111111111")
        try fixture.insert(phrase: "Vercel")
        try fixture.insert(phrase: "vercel", team: "11111111-1111-1111-1111-111111111111")
        fixture.close()

        #expect(try await WisprFlowImport.read(from: url).dictionary.terms == ["zod", "Vercel"])
    }

    @Test func aLearnedCorrectionBecomesATermAndARule() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "Kotoba", source: "user_edits", observedSource: "Zandor")
        try fixture.insert(phrase: "same", source: "user_edits", observedSource: "Same")
        try fixture.insert(phrase: "typed", source: "manual", observedSource: "tiped")
        fixture.close()

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary.terms == ["Kotoba", "same", "typed"])
        #expect(imported.dictionary.rules == [ReplacementRule(find: "Zandor", replacement: "Kotoba")])
        #expect(imported.learnedCorrections == 1)
        // What Wispr heard is the misheard form: sending it as a keyterm would bias the model toward it.
        #expect(!imported.dictionary.keyterms.contains("Zandor"))
        #expect(imported.dictionary.keyterms.contains("Kotoba"))
    }

    @Test func aLearnedCorrectionInPersonalAndTeamDictionariesCountsOnce() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "Xandor", source: "user_edits", observedSource: "Zandor")
        try fixture.insert(
            phrase: "Xandor", team: "11111111-1111-1111-1111-111111111111", source: "user_edits",
            observedSource: "Zandor")
        fixture.close()

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary.rules == [ReplacementRule(find: "Zandor", replacement: "Xandor")])
        #expect(imported.learnedCorrections == 1)
    }

    @Test(arguments: [SQLiteDatabase.Value.text("1"), .text("true"), .real(1)])
    func otherSpellingsOfASnippetAreCounted(isSnippet: SQLiteDatabase.Value) async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "my email", replacement: "me@example.com", isSnippet: isSnippet)
        fixture.close()

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary.rules.isEmpty)
        #expect(imported.snippets == 1)
    }

    @Test func snippetsAreCountedButNotImported() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "my email", replacement: "me@example.com", isSnippet: .integer(1))
        try fixture.insert(phrase: "uv")
        fixture.close()

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary == PersonalDictionary(terms: ["uv"]))
        #expect(imported.snippets == 1)
    }

    @Test func wordsWisprHasNotCheckpointedYetAreImported() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "checkpointed")
        try fixture.checkpoint()
        // Wispr is running: its connection stays open, so this row lives only in flow.sqlite-wal.
        try fixture.insert(phrase: "still in the WAL")

        let imported = try await WisprFlowImport.read(from: url)

        #expect(imported.dictionary.terms == ["checkpointed", "still in the WAL"])
        fixture.close()
    }

    @Test func readingLeavesWisprsFilesUnchangedAndDeletesTheClone() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let fixture = try WisprFixture(url: url)
        try fixture.insert(phrase: "PyTorch")
        let before = try snapshot(of: folder.url)
        let clones = folder.url.appending(path: "clones", directoryHint: .isDirectory)

        _ = try await WisprFlowImport.read(from: url, cloningInto: clones)

        #expect(try snapshot(of: folder.url) == before)
        fixture.close()
    }

    @Test func aDatabaseWithoutADictionaryTableIsAnError() async throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let database = try SQLiteDatabase(url: url)
        try database.execute("CREATE TABLE Other (x TEXT);")

        await #expect(throws: SQLiteError.self) { try await WisprFlowImport.read(from: url) }
    }

    // MARK: Cloning while Wispr writes

    @Test func aFileThatChangesDuringTheCloneIsClonedAgain() throws {
        let url = folder.url.appending(path: "flow.sqlite")
        try Data("one".utf8).write(to: url)
        var copies = 0

        let clone = try WisprFlowImport.clone(url, into: folder.url.appending(path: "clone")) { from, to in
            copies += 1
            try FileManager.default.copyItem(at: from, to: to)
            if copies == 1 {
                try Data("one, then Wispr wrote".utf8).write(to: url)
            }
        }

        #expect(copies == 2)
        #expect(try Data(contentsOf: clone) == Data("one, then Wispr wrote".utf8))
    }

    @Test func aWALThatDisappearsDuringTheCloneIsClonedAgain() throws {
        let url = folder.url.appending(path: "flow.sqlite")
        let wal = folder.url.appending(path: "flow.sqlite-wal")
        try Data("main".utf8).write(to: url)
        try Data("wal".utf8).write(to: wal)
        var copies: [String] = []

        let clone = try WisprFlowImport.clone(url, into: folder.url.appending(path: "clone")) { from, to in
            copies.append(from.lastPathComponent)
            if from == wal, copies.count == 2 {
                // Wispr quit between the stamp and the copy: SQLite deleted the WAL on its last close.
                try FileManager.default.removeItem(at: wal)
                throw CocoaError(.fileNoSuchFile)
            }
            try FileManager.default.copyItem(at: from, to: to)
        }

        #expect(copies == ["flow.sqlite", "flow.sqlite-wal", "flow.sqlite"])
        #expect(try Data(contentsOf: clone) == Data("main".utf8))
        #expect(!FileManager.default.fileExists(atPath: clone.path + "-wal"))
    }

    @Test func aFileThatKeepsChangingFailsAfterThreeTries() throws {
        let url = folder.url.appending(path: "flow.sqlite")
        try Data("0".utf8).write(to: url)
        var copies = 0

        #expect(throws: WisprFlowImport.ImportError.changedWhileCloning) {
            try WisprFlowImport.clone(url, into: folder.url.appending(path: "clone")) { from, to in
                copies += 1
                try FileManager.default.copyItem(at: from, to: to)
                try Data(String(repeating: "x", count: copies + 1).utf8).write(to: url)
            }
        }
        #expect(copies == 3)
    }

    // MARK: Helpers

    @discardableResult
    private func makeFile(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: url)
        return url
    }

    /// Each file's name, size, modification date and bytes.
    private func snapshot(of directory: URL) throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var files: [String: Data] = [:]
        for name in names {
            let url = directory.appending(path: name)
            let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            files[name + "@\(date?.timeIntervalSince1970 ?? 0)"] = try Data(contentsOf: url)
        }
        return files
    }
}

/// A database with Wispr Flow's `Dictionary` table (schema from the owner's backup of 2026-10-14), in WAL mode like
/// Wispr's own file, with automatic checkpoints off so rows stay in the WAL until `checkpoint()`.
private final class WisprFixture {
    static let personal = "00000000-0000-0000-0000-000000000000"

    private var database: SQLiteDatabase?

    init(url: URL) throws {
        let database = try SQLiteDatabase(url: url)
        try database.execute(
            """
            PRAGMA journal_mode = WAL;
            PRAGMA wal_autocheckpoint = 0;
            CREATE TABLE Dictionary (
                id VARCHAR(36) PRIMARY KEY,
                phrase VARCHAR(255) NOT NULL,
                replacement VARCHAR(255),
                teamDictionaryId VARCHAR(36) NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
                lastUsed DATETIME,
                frequencyUsed INTEGER,
                remoteFrequencyUsed INTEGER,
                manualEntry TINYINT(1),
                createdAt DATETIME,
                modifiedAt DATETIME,
                isDeleted TINYINT(1) NOT NULL DEFAULT 0,
                source VARCHAR(255),
                isSnippet TINYINT(1),
                observedSource VARCHAR(255),
                isStarred TINYINT(1),
                replacementHtml TEXT,
                UNIQUE (phrase, teamDictionaryId)
            );
            """
        )
        self.database = database
    }

    func insert(
        phrase: String,
        replacement: String? = nil,
        team: String = personal,
        isDeleted: SQLiteDatabase.Value = .integer(0),
        source: String? = nil,
        observedSource: String? = nil,
        isSnippet: SQLiteDatabase.Value = .integer(0)
    ) throws {
        try database?.run(
            """
            INSERT INTO Dictionary
                (id, phrase, replacement, teamDictionaryId, isDeleted, source, observedSource, isSnippet, manualEntry)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1);
            """,
            [
                .text(UUID().uuidString), .text(phrase), replacement.map { .text($0) } ?? .null, .text(team),
                isDeleted, source.map { .text($0) } ?? .null, observedSource.map { .text($0) } ?? .null,
                isSnippet,
            ]
        )
    }

    func checkpoint() throws {
        try database?.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    /// Closing the last connection checkpoints the WAL into the main file.
    func close() {
        database = nil
    }
}
