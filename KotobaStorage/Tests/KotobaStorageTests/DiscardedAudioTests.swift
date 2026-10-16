import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// Discarded recordings whose file stayed (`Store.markDiscarded`): the launch never takes them for orphans.
struct DiscardedAudioTests {
    let folder = TemporaryFolder()
    var url: URL { folder.url.appending(path: "kotoba.sqlite") }

    /// Kept over a reopen, with no row, until the launch forgets it.
    @Test func aDiscardIsRememberedWithNoRowUntilForgotten() async throws {
        let store = try HistoryStore(url: url, audio: folder.url)
        let stayed = DictationID()
        let other = DictationID()
        try await store.markDiscarded(stayed)
        try await store.markDiscarded(stayed)
        try await store.markDiscarded(other)

        let reopened = try HistoryStore(url: url, audio: folder.url)
        #expect(try await reopened.discardedIDs() == [stayed, other])
        #expect(try await reopened.knownIDs(among: [stayed, other]).isEmpty)
        #expect(try await reopened.page(limit: 10).isEmpty)
        try await reopened.forgetDiscarded([stayed])
        #expect(try await reopened.discardedIDs() == [other])
    }
}
