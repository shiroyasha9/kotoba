import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

struct DictionaryStoreTests {
    let folder = TemporaryFolder()

    @Test func aNewStoreHasAnEmptyDictionary() async throws {
        let store = try DictionaryStore(url: folder.url.appending(path: "dictionary.sqlite"))
        #expect(try await store.load() == PersonalDictionary())
    }

    @Test func aSavedDictionaryLoadsInTheSameOrderAfterARestart() async throws {
        let url = folder.url.appending(path: "dictionary.sqlite")
        let dictionary = PersonalDictionary(
            terms: ["zshrc", "PyTorch", "uv"],
            rules: [
                ReplacementRule(find: "cloud code", replacement: "Claude Code"),
                ReplacementRule(find: "Go", replacement: "Golang", isWholeWord: false, isCaseSensitive: true),
                ReplacementRule(find: "um", replacement: ""),
            ]
        )
        try await DictionaryStore(url: url).save(dictionary)

        #expect(try await DictionaryStore(url: url).load() == dictionary)
    }

    @Test func savingReplacesTheWholeDictionary() async throws {
        let store = try DictionaryStore(url: folder.url.appending(path: "dictionary.sqlite"))
        try await store.save(
            PersonalDictionary(terms: ["a", "b"], rules: [ReplacementRule(find: "x", replacement: "y")]))

        try await store.save(PersonalDictionary(terms: ["b"]))

        #expect(try await store.load() == PersonalDictionary(terms: ["b"]))
    }
}

/// A folder under the system temporary directory, deleted when the test ends.
final class TemporaryFolder: Sendable {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appending(
            path: "kotoba-storage-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Issue.record("Cannot create \(url.path): \(error)")
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: url)  // A leftover temp folder is harmless.
    }
}
