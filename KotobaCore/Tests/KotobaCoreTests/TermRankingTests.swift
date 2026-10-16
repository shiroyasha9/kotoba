import Foundation
import Testing

@testable import KotobaCore

/// Which keyterms a request sends when the dictionary has more than the route takes (phase3-plan.md section 3).
struct TermRankingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 60 * 60
    /// 120 terms, `term0` to `term119`, over the cap of 100.
    let terms = (0..<120).map { "term\($0)" }

    func ranked(_ use: [String: TermUse], terms: [String]? = nil, limit: Int = 100) -> [String] {
        TermRanking.keyterms(
            of: PersonalDictionary(terms: terms ?? self.terms), use: use, limit: limit, at: now)
    }

    @Test func underTheCapEveryKeytermGoesInListOrder() {
        let dictionary = PersonalDictionary(
            terms: ["PyTorch", "zshrc", " Vercel ", "vercel"],
            rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")])
        let use = ["claude code": TermUse(uses: 9, lastUsedAt: now, isPinned: true)]

        #expect(TermRanking.keyterms(of: dictionary, use: use, at: now) == dictionary.keyterms)
        #expect(dictionary.keyterms == ["PyTorch", "zshrc", "Vercel", "Claude Code"])
    }

    @Test func overTheCapWithNoUseTheListOrderDecides() {
        #expect(ranked([:]) == Array(terms.prefix(100)))
        #expect(PersonalDictionary.maxKeyterms == 100)
        #expect(PersonalDictionary.maxKeytermLength == 50)
    }

    @Test func aPinnedTermIsAlwaysSent() {
        let sent = ranked(["term119": TermUse(isPinned: true), "term110": TermUse(isPinned: true)])

        #expect(sent.prefix(2) == ["term110", "term119"])
        #expect(sent.count == 100)
        #expect(!sent.contains("term99"))
    }

    @Test func usedTermsComeBeforeUnusedOnesBestScoreFirst() {
        let sent = ranked([
            "term105": TermUse(uses: 2, lastUsedAt: now),
            "term115": TermUse(uses: 5, lastUsedAt: now),
        ])

        #expect(sent.prefix(2) == ["term115", "term105"])
        #expect(sent.count == 100)
    }

    @Test func anOldUseFallsBelowARecentOne() {
        // 8 uses 90 days ago score 8 × 0.5^3 = 1; 2 uses today score 2.
        let sent = ranked([
            "term101": TermUse(uses: 8, lastUsedAt: now - 90 * day),
            "term102": TermUse(uses: 2, lastUsedAt: now),
        ])

        #expect(sent.prefix(2) == ["term102", "term101"])
    }

    @Test func equalScoresKeepListOrder() {
        let use = TermUse(uses: 1, lastUsedAt: now)
        #expect(ranked(["term118": use, "term103": use]).prefix(2) == ["term103", "term118"])
    }

    @Test func pinnedTermsComeBeforeUsedOnes() {
        let sent = ranked([
            "term111": TermUse(uses: 50, lastUsedAt: now),
            "term112": TermUse(isPinned: true),
        ])

        #expect(sent.prefix(2) == ["term112", "term111"])
    }

    @Test func newTermsTakeAtMostTenSlotsNewestFirst() {
        // A bulk import of 20 terms yesterday and one term today, all unused.
        var use: [String: TermUse] = [:]
        for index in 100..<120 {
            use["term\(index)"] = TermUse(addedAt: now - day)
        }
        use["term119"] = TermUse(addedAt: now)

        let sent = ranked(use)

        #expect(Array(sent.prefix(10)) == ["term119"] + (100..<109).map { "term\($0)" })
        #expect(Array(sent.dropFirst(10)) == Array(terms.prefix(90)))
    }

    @Test func newTermsDoNotPushOutUsedOnes() {
        var use: [String: TermUse] = ["term0": TermUse(uses: 1, lastUsedAt: now)]
        for index in 100..<120 {
            use["term\(index)"] = TermUse(addedAt: now)
        }

        let sent = ranked(use, limit: 5)

        #expect(sent == ["term0", "term100", "term101", "term102", "term103"])
    }

    @Test func aTermAddedMoreThanTwoWeeksAgoIsNotNew() {
        let sent = ranked(["term119": TermUse(addedAt: now - 15 * day)])
        #expect(sent == Array(terms.prefix(100)))
    }

    @Test func morePinsThanTheLimitSendTheFirstPinsInListOrder() {
        let use = Dictionary(uniqueKeysWithValues: terms.map { (TermUse.key(for: $0), TermUse(isPinned: true)) })
        #expect(ranked(use, limit: 3) == ["term0", "term1", "term2"])
    }

    @Test func useMatchesATermInAnyCase() {
        let terms = ["Alpha", "Beta", "Gamma"]
        #expect(ranked(["gamma": TermUse(isPinned: true)], terms: terms, limit: 2) == ["Gamma", "Alpha"])
        #expect(TermUse.key(for: " Gamma ") == "gamma")
    }

    @Test func caseInsensitiveDuplicatesCountOnce() {
        let terms = ["Alpha", "alpha", "Beta", "BETA", "Gamma"]
        #expect(ranked([:], terms: terms, limit: 2) == ["Alpha", "Beta"])
    }

    @Test func aRuleReplacementCountsAsATerm() {
        let dictionary = PersonalDictionary(
            terms: ["Alpha", "Beta"], rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")])
        let use = ["claude code": TermUse(uses: 1, lastUsedAt: now)]

        #expect(TermRanking.keyterms(of: dictionary, use: use, limit: 2, at: now) == ["Claude Code", "Alpha"])
    }

    @Test func aUseLaterThanNowCountsAsToday() {
        let use = TermUse(uses: 3, lastUsedAt: now + day)
        #expect(TermRanking.score(use, at: now) == 3)
    }
}
