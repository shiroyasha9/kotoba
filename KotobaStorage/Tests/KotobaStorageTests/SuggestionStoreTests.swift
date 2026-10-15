import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The `dictionary_suggestions` table (docs/research/auto-learning.md 4.3-4.4): suggest, then the owner confirms.
struct SuggestionStoreTests {
    let folder = TemporaryFolder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let vercel = SuggestionCandidate(
        heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .fix, appBundleID: "com.cmux.app")
    let embra = SuggestionCandidate(heard: "ember", corrected: "embra", proposes: .term, origin: .fix)

    func makeStore() throws -> DictionaryStore {
        try DictionaryStore(url: folder.url.appending(path: "dictionary.sqlite"))
    }

    func days(_ count: Double) -> Date {
        start + count * 24 * 60 * 60
    }

    @Test func aNewCorrectionIsPendingAndSurvivesARestart() async throws {
        let store = try makeStore()

        let recorded = try #require(try await store.record(vercel, at: start))

        #expect(recorded.evidence == 1)
        #expect(recorded.status == .pending)
        #expect(try await makeStore().pendingSuggestions(at: start) == [recorded])
    }

    @Test func seeingTheSamePairAgainCountsUp() async throws {
        let store = try makeStore()
        _ = try await store.record(vercel, at: start)
        var again = vercel
        again.heard = "Versel"

        let recorded = try #require(try await store.record(again, at: days(1)))

        #expect(recorded.evidence == 2)
        #expect(recorded.firstSeenAt == start)
        #expect(recorded.lastSeenAt == days(1))
        #expect(try await store.pendingSuggestions(at: days(1)).count == 1)
    }

    @Test func aDismissedPairNeverReturns() async throws {
        let store = try makeStore()
        let recorded = try #require(try await store.record(vercel, at: start))

        try await store.dismiss([recorded.id])

        #expect(try await store.record(vercel, at: days(1)) == nil)
        #expect(try await store.pendingSuggestions(at: days(1)).isEmpty)
        #expect(try await store.dismissedPairs() == [vercel.pair])
    }

    @Test func addingSavesTheDictionaryAndMarksTheSuggestionAdded() async throws {
        let store = try makeStore()
        let recorded = try #require(try await store.record(vercel, at: start))
        let dictionary = PersonalDictionary(terms: ["uv"]).adding(vercel)

        try await store.save(dictionary, markingAdded: [recorded.id])

        #expect(try await store.load() == dictionary)
        #expect(try await store.pendingSuggestions(at: start).isEmpty)
        #expect(try await store.record(vercel, at: days(1)) == nil)
    }

    @Test func deletingAWordThatCameFromASuggestionDismissesIt() async throws {
        let store = try makeStore()
        let recorded = try #require(try await store.record(vercel, at: start))
        try await store.save(PersonalDictionary().adding(vercel), markingAdded: [recorded.id])

        try await store.save(PersonalDictionary(rules: [ReplacementRule(find: "versel", replacement: "Vercel")]))

        #expect(try await store.dismissedPairs() == [vercel.pair])
    }

    @Test func keepingTheWordKeepsTheSuggestionAdded() async throws {
        let store = try makeStore()
        let recorded = try #require(try await store.record(embra, at: start))
        try await store.save(PersonalDictionary().adding(embra), markingAdded: [recorded.id])

        try await store.save(PersonalDictionary(terms: ["uv", "embra"]))

        #expect(try await store.dismissedPairs().isEmpty)
    }

    @Test func aWordTheOwnerFixedAndCheckedIsAddedAtOnce() async throws {
        let store = try makeStore()
        _ = try await store.record(embra, at: start)
        let dismissed = try #require(try await store.record(vercel, at: start))
        try await store.dismiss([dismissed.id])
        let dictionary = PersonalDictionary().adding(embra).adding(vercel)

        try await store.save(dictionary, recordingAdded: [embra, vercel], at: days(1))

        #expect(try await store.pendingSuggestions(at: days(1)).isEmpty)
        #expect(try await store.dismissedPairs().isEmpty)
        #expect(try await store.record(vercel, at: days(2)) == nil)
        #expect(try await store.load() == dictionary)
    }

    @Test func aLearnedWordTheOwnerUndoesIsNeverLearnedAgain() async throws {
        let store = try makeStore()
        var learned = vercel
        learned.origin = .edit
        let before = PersonalDictionary(terms: ["uv"])
        try await store.save(before.adding(learned), recordingAdded: [learned], at: start)

        try await store.save(before, at: start)

        #expect(try await store.dismissedPairs() == [learned.pair])
        #expect(try await store.record(learned, at: days(1)) == nil)
        #expect(try await store.load() == before)
    }

    @Test func aWeakCorrectionWaitsUntilItIsSeenTwice() async throws {
        let store = try makeStore()
        _ = try await store.record(embra, isStrong: false, at: start)

        #expect(try await store.pendingSuggestions(at: start).isEmpty)

        _ = try await store.record(embra, isStrong: false, at: days(1))

        #expect(try await store.pendingSuggestions(at: days(1)).map(\.evidence) == [2])
    }

    @Test func aStrongSightingShowsAWeakPairAtOnce() async throws {
        let store = try makeStore()
        _ = try await store.record(vercel, isStrong: false, at: start)
        _ = try await store.record(vercel, isStrong: true, at: days(1))

        #expect(try await store.pendingSuggestions(at: days(1)).map(\.candidate.corrected) == ["Vercel"])
    }

    @Test func aDismissedPairWithNonASCIICapitalsNeverReturns() async throws {
        let store = try makeStore()
        let lower = SuggestionCandidate(heard: "zoe", corrected: "zoë", proposes: .termAndRule, origin: .fix)
        let recorded = try #require(try await store.record(lower, at: start))
        try await store.dismiss([recorded.id])
        var upper = lower
        upper.corrected = "ZOË"

        #expect(try await store.record(upper, at: days(1)) == nil)
    }

    @Test func aCorrectionTheOwnerUncheckedIsDismissedAtOnce() async throws {
        let store = try makeStore()

        try await store.dismiss([vercel], at: start)

        #expect(try await store.dismissedPairs() == [vercel.pair])
        #expect(try await store.record(vercel, at: days(1)) == nil)
    }

    @Test func aSuggestionTableFromAnEarlierBuildIsMigrated() async throws {
        let url = folder.url.appending(path: "dictionary.sqlite")
        let old = try SQLiteDatabase(url: url)
        try old.execute(
            """
            CREATE TABLE dictionary_suggestions (
                id TEXT PRIMARY KEY, heard TEXT NOT NULL, corrected TEXT NOT NULL, proposes TEXT NOT NULL,
                origin TEXT NOT NULL, app_bundle_id TEXT, evidence INTEGER NOT NULL, first_seen_at REAL NOT NULL,
                last_seen_at REAL NOT NULL, status TEXT NOT NULL
            );
            CREATE UNIQUE INDEX dictionary_suggestions_pair ON dictionary_suggestions (lower(heard), lower(corrected));
            INSERT INTO dictionary_suggestions VALUES ('6F8F57C5-7D3B-4B0E-9A3B-1C2D3E4F5A6B', 'Versel', 'Vercel',
                'termAndRule', 'fix', NULL, 1, 1800000000, 1800000000, 'dismissed');
            """)

        let store = try DictionaryStore(url: url)

        #expect(try await store.dismissedPairs() == [vercel.pair])
        #expect(try await store.record(vercel, at: days(1)) == nil)
        #expect(try await store.record(embra, at: days(1))?.evidence == 1)
    }

    @Test func aPendingSuggestionExpiresAfter30Days() async throws {
        let store = try makeStore()
        _ = try await store.record(vercel, at: start)
        _ = try await store.record(embra, at: days(20))

        let pending = try await store.pendingSuggestions(at: days(31))

        #expect(pending.map(\.candidate.corrected) == ["embra"])
        // An expired pair is not dismissed: seen again, it comes back as new.
        #expect(try await store.record(vercel, at: days(32))?.evidence == 1)
    }

    @Test func atMost20SuggestionsWaitAndTheStalestGoes() async throws {
        let store = try makeStore()
        for index in 0..<21 {
            let candidate = SuggestionCandidate(
                heard: "heard\(index)", corrected: "Word\(index)", proposes: .termAndRule, origin: .fix)
            _ = try await store.record(candidate, at: start + Double(index))
        }

        let pending = try await store.pendingSuggestions(at: start + 30)

        #expect(pending.count == DictionaryStore.maxPendingSuggestions)
        #expect(!pending.contains { $0.candidate.corrected == "Word0" })
    }

    @Test func aWeakPairNotShownYetDoesNotPushOutAShownOne() async throws {
        let store = try makeStore()
        for index in 0..<20 {
            let candidate = SuggestionCandidate(
                heard: "heard\(index)", corrected: "Word\(index)", proposes: .termAndRule, origin: .fix)
            _ = try await store.record(candidate, at: start + Double(index))
        }

        _ = try await store.record(embra, isStrong: false, at: start + 30)

        let pending = try await store.pendingSuggestions(at: start + 30)
        #expect(pending.count == DictionaryStore.maxPendingSuggestions)
        #expect(pending.contains { $0.candidate.corrected == "Word0" })
    }

    @Test func pendingSuggestionsListTheMostSeenFirst() async throws {
        let store = try makeStore()
        _ = try await store.record(embra, at: start)
        _ = try await store.record(vercel, at: days(1))
        _ = try await store.record(vercel, at: days(2))

        let pending = try await store.pendingSuggestions(at: days(2))

        #expect(pending.map(\.candidate.corrected) == ["Vercel", "embra"])
        #expect(pending.first?.candidate.appBundleID == "com.cmux.app")
    }
}
