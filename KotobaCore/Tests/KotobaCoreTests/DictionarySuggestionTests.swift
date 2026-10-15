import Foundation
import Testing

@testable import KotobaCore

/// Suggestions learned from corrections (story 32): what one adds to the dictionary.
struct DictionarySuggestionTests {
    let english: Set<String> = ["ember", "add", "it", "mellow", "drafting", "don't"]

    func isKnownWord(_ word: String) -> Bool {
        english.contains(word.lowercased())
    }

    @Test func aRareHeardWordProposesARule() {
        #expect(SuggestionCandidate.proposal(heard: "versel", isKnownWord: isKnownWord) == .termAndRule)
        #expect(SuggestionCandidate.proposal(heard: "order ID", isKnownWord: isKnownWord) == .termAndRule)
    }

    @Test func aCommonHeardWordOrPhraseProposesTheWordOnly() {
        #expect(SuggestionCandidate.proposal(heard: "ember", isKnownWord: isKnownWord) == .term)
        #expect(SuggestionCandidate.proposal(heard: "Add it", isKnownWord: isKnownWord) == .term)
        #expect(SuggestionCandidate.proposal(heard: "Mellow", isKnownWord: isKnownWord) == .term)
        #expect(SuggestionCandidate.proposal(heard: "don't", isKnownWord: isKnownWord) == .term)
    }

    @Test func aHeardTextWithoutLettersProposesARule() {
        #expect(SuggestionCandidate.proposal(heard: "2.5", isKnownWord: isKnownWord) == .termAndRule)
    }

    @Test func addingATermAndRuleSuggestionWritesBoth() {
        let candidate = SuggestionCandidate(heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .fix)

        let dictionary = PersonalDictionary(terms: ["uv"]).adding(candidate)

        #expect(dictionary.terms == ["uv", "Vercel"])
        #expect(dictionary.rules == [ReplacementRule(find: "versel", replacement: "Vercel")])
        #expect(dictionary.contains(candidate))
    }

    @Test func addingATermSuggestionWritesTheWordOnly() {
        let candidate = SuggestionCandidate(heard: "ember", corrected: "embra", proposes: .term, origin: .fix)

        let dictionary = PersonalDictionary().adding(candidate)

        #expect(dictionary == PersonalDictionary(terms: ["embra"]))
    }

    @Test func aSuggestionAlreadyInTheDictionaryAddsNothing() {
        let candidate = SuggestionCandidate(heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .fix)
        let dictionary = PersonalDictionary(
            terms: ["vercel"], rules: [ReplacementRule(find: "Versel", replacement: "Vercel")])

        #expect(dictionary.contains(candidate))
        #expect(dictionary.adding(candidate) == dictionary)
        #expect(!PersonalDictionary(terms: ["vercel"]).contains(candidate))
    }

    @Test func thePairIgnoresCase() {
        let lower = SuggestionCandidate(heard: "versel", corrected: "vercel", proposes: .term, origin: .fix)
        let upper = SuggestionCandidate(heard: "Versel", corrected: "Vercel", proposes: .termAndRule, origin: .wispr)
        #expect(lower.pair == upper.pair)
    }
}
