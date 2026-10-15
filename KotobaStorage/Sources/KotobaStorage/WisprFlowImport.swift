import Foundation
import KotobaCore
import SQLite3

/// Reads Wispr Flow's personal dictionary from its local SQLite database, so the owner switches with their words.
/// Wispr's files are only read: never opened by SQLite, never written.
public enum WisprFlowImport {
    public enum ImportError: Error, Sendable, Equatable {
        /// Wispr wrote to its database during every try of the clone.
        case changedWhileCloning
    }

    /// What Wispr's dictionary holds, de-duplicated.
    public struct Contents: Sendable, Equatable {
        public var dictionary = PersonalDictionary()
        /// Rules from words Wispr learned from the owner's edits (what Wispr heard -> the word the owner wrote); each
        /// learned word is also a term.
        public var learned: [ReplacementRule] = []
        /// Snippets are a later kotoba feature, so they are counted, not imported.
        public var snippets = 0

        public var learnedCorrections: Int { learned.count }

        public init(
            dictionary: PersonalDictionary = PersonalDictionary(), learned: [ReplacementRule] = [], snippets: Int = 0
        ) {
            self.dictionary = dictionary
            self.learned = learned
            self.snippets = snippets
        }

        /// Drops each learned rule whose heard text is made of common words, keeping its word: replacing a real word
        /// everywhere breaks other sentences (`Mellow` -> `Marlow`). Same check as the correction detector.
        public func keepingRules(isKnownWord: (String) -> Bool) -> Self {
            let common = learned.filter {
                SuggestionCandidate.proposal(heard: $0.find, isKnownWord: isKnownWord) == .term
            }
            var kept = self
            kept.learned.removeAll(where: common.contains)
            kept.dictionary.rules.removeAll(where: common.contains)
            return kept
        }
    }

    /// Found 2026-10-15: `~/Library/Application Support/Wispr Flow/flow.sqlite`, next to its `-wal` file.
    static let databaseName = "flow.sqlite"
    static let cloneTries = 3

    /// Wispr Flow's database in Application Support, or in a sandbox container if a later Wispr build moves there.
    /// Lists folders only; nothing is opened.
    public static func locate(
        applicationSupport: URL = .applicationSupportDirectory,
        containers: URL = .libraryDirectory.appending(path: "Containers", directoryHint: .isDirectory)
    ) -> URL? {
        var folders = wisprFolders(in: applicationSupport)
        for container in wisprFolders(in: containers) {
            folders += wisprFolders(in: container.appending(path: "Data/Library/Application Support"))
        }
        return
            folders
            .map { $0.appending(path: databaseName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Live `Dictionary` rows, personal and team: a phrase alone becomes a term, a phrase with a replacement becomes
    /// a find-and-replace rule, and a learned correction becomes both (what Wispr heard -> the phrase).
    ///
    /// Wispr keeps recent writes in `flow.sqlite-wal`, which SQLite's `immutable=1` mode would skip. So this clones
    /// the database and its WAL into `folder` (an APFS clone, no copy of the bytes), reads the clone and deletes
    /// `folder`.
    /// Whether Wispr Flow's database is on this Mac, found off the main actor (it lists folders only).
    @concurrent
    public static func isInstalled() async -> Bool {
        locate() != nil
    }

    /// Finds Wispr's database and reads it, off the main actor. Nil when Wispr Flow is not on this Mac.
    @concurrent
    public static func readInstalled() async throws -> Contents? {
        guard let database = locate() else { return nil }
        return try await read(from: database)
    }

    @concurrent
    public static func read(
        from database: URL,
        cloningInto folder: URL = FileManager.default.temporaryDirectory.appending(
            path: "kotoba-wispr-import-\(UUID().uuidString)", directoryHint: .isDirectory)
    ) async throws -> Contents {
        defer {
            try? FileManager.default.removeItem(at: folder)  // Already gone when the clone failed early.
        }
        let clone = try clone(database, into: folder)
        let rows = try SQLiteDatabase(url: clone, flags: SQLITE_OPEN_READWRITE).query(
            """
            SELECT phrase, replacement, source, observedSource, coalesce(isSnippet IN (1, '1', 'true'), 0)
            FROM Dictionary WHERE isDeleted IS NULL OR isDeleted IN (0, '0', 'false');
            """
        )
        var raw = PersonalDictionary()
        var learned: Set<ReplacementRule> = []
        var contents = Contents()
        for row in rows {
            guard case .text(let phrase) = row[0], !isBlank(phrase) else { continue }
            if row[4] == .integer(1) {
                contents.snippets += 1
            } else if case .text(let replacement) = row[1], !isBlank(replacement) {
                raw.rules.append(ReplacementRule(find: phrase, replacement: replacement))
            } else {
                raw.terms.append(phrase)
                if case .text("user_edits") = row[2], case .text(let heard) = row[3], !isBlank(heard),
                    heard.caseInsensitiveCompare(phrase) != .orderedSame
                {
                    let rule = ReplacementRule(
                        find: heard.trimmingCharacters(in: .whitespacesAndNewlines), replacement: phrase)
                    raw.rules.append(rule)
                    learned.insert(rule)
                }
            }
        }
        // De-duplicated first: a correction in both the personal and the team dictionary counts once.
        contents.dictionary.apply(contents.dictionary.importPreview(of: raw))
        contents.learned = contents.dictionary.rules.filter(learned.contains)
        return contents
    }

    /// Clones the database and its WAL into `folder`, again when Wispr changed either file meanwhile (size or
    /// modification date), at most `cloneTries` times. Returns the cloned database.
    static func clone(
        _ database: URL,
        into folder: URL,
        copy: (URL, URL) throws -> Void = FileManager.default.copyItem(at:to:)
    ) throws -> URL {
        let wal = URL(filePath: database.path + "-wal")
        let clone = folder.appending(path: databaseName)
        for _ in 0..<cloneTries {
            let before = try stamp(of: [database, wal])
            try? FileManager.default.removeItem(at: folder)  // Nothing to remove on the first try.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            do {
                try copy(database, clone)
                if before[1] != nil {
                    try copy(wal, URL(filePath: clone.path + "-wal"))
                }
            } catch {
                // Wispr deleted or replaced a file meanwhile (its WAL goes when it quits): clone again.
                guard try stamp(of: [database, wal]) != before else { throw error }
                continue
            }
            if try stamp(of: [database, wal]) == before {
                return clone
            }
        }
        throw ImportError.changedWhileCloning
    }

    private struct Stamp: Equatable {
        var size: Int
        var modified: Date
    }

    /// Size and modification date of each file, nil for a missing file.
    private static func stamp(of files: [URL]) throws -> [Stamp?] {
        try files.map { file in
            let attributes: [FileAttributeKey: Any]
            do {
                attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            } catch CocoaError.fileReadNoSuchFile {
                return nil
            }
            return Stamp(
                size: (attributes[.size] as? Int) ?? 0,
                modified: (attributes[.modificationDate] as? Date) ?? .distantPast
            )
        }
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func wisprFolders(in parent: URL) -> [URL] {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: parent.path)
        } catch {
            return []  // No such folder: Wispr is not there.
        }
        return names.sorted()
            .filter { $0.localizedCaseInsensitiveContains("wispr") }
            .map { parent.appending(path: $0, directoryHint: .isDirectory) }
    }
}
