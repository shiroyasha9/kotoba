import Foundation
import Testing

@testable import KotobaCore

/// Which keyterms a delivered text has: the use counts `TermRanking` ranks by.
struct TermHitsTests {
    @Test func aTermMatchesAsAWholeWordInAnyCase() {
        #expect(TermHits.find(["Mastra", "zod"], in: "we moved to mastra, not ZOD.") == ["Mastra", "zod"])
    }

    @Test func aTermInsideALongerWordIsNoHit() {
        #expect(TermHits.find(["zod", "PTE"], in: "my zodiac sign; PTEs") == [])
    }

    @Test func aLaterMatchCountsWhenTheFirstIsInsideAWord() {
        #expect(TermHits.find(["zod"], in: "zodiac then zod") == ["zod"])
    }

    @Test func termsWithPunctuationMatchAsWritten() {
        let terms = ["order_id", "auth.ts", "C++", "/grill-me"]
        let text = "rename order_id in auth.ts, then C++ and /grill-me"
        #expect(TermHits.find(terms, in: text) == terms)
        #expect(TermHits.find(["order_id"], in: "my_order_id") == [])
        #expect(TermHits.find(["auth.ts"], in: "oauth.ts") == [])
    }

    @Test func aMultiWordTermMatches() {
        #expect(TermHits.find(["Stacked PRs"], in: "use stacked PRs here") == ["Stacked PRs"])
    }

    @Test func eachTermCountsOnce() {
        #expect(TermHits.find(["Codex"], in: "Codex, codex and CODEX") == ["Codex"])
    }

    @Test func nonASCIIWordsMatchInAnyCaseAndKeepTheirEdges() {
        #expect(TermHits.find(["Ångström"], in: "one ÅNGSTRÖM unit") == ["Ångström"])
        #expect(TermHits.find(["zod"], in: "ézod and zodé") == [])
        #expect(TermHits.find(["zod"], in: "—zod—") == ["zod"])
        // As for a whole-word replacement: a script with no spaces has no word edge inside a run of letters.
        #expect(TermHits.find(["コトバ"], in: "これはコトバです") == [])
        #expect(TermHits.find(["コトバ"], in: "これは コトバ です") == ["コトバ"])
    }

    @Test func anEmptyTextHasNoHits() {
        #expect(TermHits.find(["Codex"], in: "") == [])
    }
}
