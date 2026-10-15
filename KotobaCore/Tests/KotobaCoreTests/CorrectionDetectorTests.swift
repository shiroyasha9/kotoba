import Foundation
import Testing

@testable import KotobaCore

/// What the owner's edit of a pasted transcript teaches (story 32, docs/research/auto-learning.md 4.3 and 4.5).
struct CorrectionDetectorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var pasted: String
        var observed: String
        /// heard, corrected, proposes, strong.
        var expected: [Expected] = []
        var dictionary = PersonalDictionary()
        var dismissed: Set<SuggestionPair> = []

        var testDescription: String { name }
    }

    struct Expected: Sendable, Equatable {
        var heard: String
        var corrected: String
        var proposes: SuggestionCandidate.Proposal
        var isStrong = true
    }

    static let english: Set<String> = [
        "a", "about", "and", "at", "change", "add", "audit", "config", "renamed", "deploy", "field", "file", "for",
        "i", "in", "is", "it", "ember", "meeting", "editing", "ten", "now", "package", "people", "please", "post",
        "push", "rename", "column", "ship", "should", "so", "the", "to", "today", "removed", "use", "was", "we",
        "drafting", "great", "docs", "slash", "open", "plan", "before", "shipping", "anything", "whole", "reconsider",
        "call", "mellow", "hello", "dinner", "with", "tonight", "calendar", "ready", "an", "access", "based",
        "check", "ask", "tar", "vee", "no", "team", "talk", "sea", "dex", "or", "codex", "website", "template",
    ]
    /// Names the spell checker knows only with their capital.
    static let names: Set<String> = ["Orlena"]

    static func isKnownWord(_ word: String) -> Bool {
        english.contains(word.lowercased()) || names.contains(word)
    }

    static let cases: [Case] = [
        Case(
            name: "unknown heard word gives a term and a rule",
            pasted: "deploy it to versel today", observed: "deploy it to Vercel today",
            expected: [Expected(heard: "versel", corrected: "Vercel", proposes: .termAndRule)]),
        Case(
            name: "spoken identifier gives a rule",
            pasted: "rename the order ID column", observed: "rename the order_id column",
            expected: [Expected(heard: "order ID", corrected: "order_id", proposes: .termAndRule)]),
        Case(
            name: "Markdown backticks are ignored",
            pasted: "use the order ID field", observed: "use the `order_id` field",
            expected: [Expected(heard: "order ID", corrected: "order_id", proposes: .termAndRule)]),
        Case(
            name: "common heard word gives the term only",
            pasted: "the ember package is great", observed: "the embra package is great",
            expected: [Expected(heard: "ember", corrected: "embra", proposes: .term)]),
        Case(
            name: "punctuation around the words is kept out",
            pasted: "call me at Mellow.", observed: "call me at Marlow.",
            expected: [Expected(heard: "Mellow", corrected: "Marlow", proposes: .term)]),
        Case(
            name: "spoken hashtag joins into one identifier",
            pasted: "post in hashtag team ops now", observed: "post in #team-ops now",
            expected: [Expected(heard: "hashtag team ops", corrected: "#team-ops", proposes: .termAndRule)]),
        Case(
            name: "case change to code shape gives the term",
            pasted: "push to github now", observed: "push to GitHub now",
            expected: [Expected(heard: "github", corrected: "GitHub", proposes: .term)]),
        Case(
            name: "known words on both sides are weak",
            pasted: "add it the change", observed: "audit the change",
            expected: [Expected(heard: "add it", corrected: "audit", proposes: .term, isStrong: false)]),
        Case(
            name: "non-word fixed into a name",
            pasted: "dinner with Orlina tonight", observed: "dinner with Orlena tonight",
            expected: [Expected(heard: "Orlina", corrected: "Orlena", proposes: .termAndRule)]),
        Case(
            name: "a capital on a known word is not a name",
            pasted: "is the calender ready", observed: "is the Calendar ready",
            expected: [Expected(heard: "calender", corrected: "Calendar", proposes: .termAndRule, isStrong: false)]),
        Case(
            name: "spoken words join into one rare word",
            pasted: "ask the tar vee no team", observed: "ask the Tarvino team",
            expected: [Expected(heard: "tar vee no", corrected: "Tarvino", proposes: .term)]),
        Case(
            name: "two words for two words are fixed one by one",
            pasted: "open the ZenTail website", observed: "open the Zentyl template",
            expected: [Expected(heard: "ZenTail", corrected: "Zentyl", proposes: .termAndRule)]),
        Case(name: "many words into one known word", pasted: "talk to sea dex or so", observed: "talk to Codex"),
        Case(name: "hyphenated English words", pasted: "an ssl-based check", observed: "an access-based check"),
        Case(name: "markup", pasted: "done</li> <li>next", observed: "done - next"),
        Case(name: "domain", pasted: "deploy to vercel dot com", observed: "deploy to vercel.com"),
        Case(name: "email address", pasted: "ping bob at acme dot dev", observed: "ping bob@acme.dev"),
        Case(name: "URL", pasted: "open www dot vercel dot com", observed: "open www.vercel.com"),
        // A lowercase name with a web TLD reads as a host, so a library such as socket.io is added by hand (lead,
        // 2026-10-16: learning hosts costs more than missing a rare library name).
        Case(name: "library name that looks like a host", pasted: "use socket io here", observed: "use socket.io here"),
        Case(
            name: "dotted framework name",
            pasted: "run it on node js today", observed: "run it on Node.js today",
            expected: [Expected(heard: "node js", corrected: "Node.js", proposes: .termAndRule)]),
        Case(
            name: "dotted capitals",
            pasted: "build it in asp dot net", observed: "build it in ASP.NET",
            expected: [Expected(heard: "asp dot net", corrected: "ASP.NET", proposes: .termAndRule)]),
        Case(name: "rewrite of a known word", pasted: "I was drafting the file", observed: "I was editing the file"),
        Case(name: "rewrite of a similar known word", pasted: "I renamed the file", observed: "I removed the file"),
        Case(
            name: "long rewrite", pasted: "we should ship it",
            observed: "please reconsider the whole plan before shipping anything"),
        Case(name: "pure deletion", pasted: "so um we ship it", observed: "so we ship it"),
        Case(name: "pure insertion", pasted: "we ship it", observed: "so we ship it today"),
        Case(name: "whitespace only", pasted: "we  ship\nit", observed: "we ship it"),
        Case(name: "number change", pasted: "about 2.5 people", observed: "about 25 people"),
        Case(name: "punctuation change", pasted: "is it ten.", observed: "is it ten?"),
        Case(name: "case change to a plain word", pasted: "hello there", observed: "Hello there"),
        Case(name: "one word into a sentence", pasted: "Tavia.", observed: "Orlena for the meeting."),
        Case(name: "path", pasted: "open the docs slash api", observed: "open the docs/api"),
        Case(
            name: "entry already in the dictionary",
            pasted: "deploy it to versel today", observed: "deploy it to Vercel today",
            dictionary: PersonalDictionary(
                terms: ["Vercel"], rules: [ReplacementRule(find: "versel", replacement: "Vercel")])),
        Case(
            name: "dismissed pair", pasted: "deploy it to versel today", observed: "deploy it to Vercel today",
            dismissed: [SuggestionPair(heard: "Versel", corrected: "vercel")]),
        Case(
            name: "one valid hunk among rewrites",
            pasted: "I was drafting the versel config now", observed: "I was editing the Vercel config now",
            expected: [Expected(heard: "versel", corrected: "Vercel", proposes: .termAndRule)]),
        Case(
            name: "the same correction twice is one candidate",
            pasted: "versel and versel", observed: "Vercel and Vercel",
            expected: [Expected(heard: "versel", corrected: "Vercel", proposes: .termAndRule)]),
    ]

    @Test(arguments: cases)
    func detects(_ testCase: Case) {
        let found = CorrectionDetector.corrections(
            pasted: testCase.pasted, observed: testCase.observed, dictionary: testCase.dictionary,
            dismissed: testCase.dismissed, origin: .fix, isKnownWord: Self.isKnownWord)

        let actual = found.map {
            Expected(
                heard: $0.candidate.heard, corrected: $0.candidate.corrected, proposes: $0.candidate.proposes,
                isStrong: $0.isStrong)
        }
        #expect(actual == testCase.expected)
        #expect(found.allSatisfy { $0.candidate.origin == .fix })
    }

    @Test func aLargeEditOfTheWholeTextIsARewrite() {
        let found = CorrectionDetector.corrections(
            pasted: "versel and ships and runs and rests and eats",
            observed: "Vercel and sails and walks and sleeps and drinks",
            origin: .edit, isKnownWord: Self.isKnownWord)
        #expect(found.isEmpty)
    }
}

/// The Fix window's checkboxes (lead decision 1, phase 2.5 review).
struct FixChoiceTests {
    @Test func checkedAreAddedUncheckedWeakAreSuggestedUncheckedStrongAreDismissed() {
        let vercel = DetectedCorrection(
            candidate: SuggestionCandidate(heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .fix),
            isStrong: true)
        let embra = DetectedCorrection(
            candidate: SuggestionCandidate(heard: "ember", corrected: "embra", proposes: .term, origin: .fix),
            isStrong: true)
        let commit = DetectedCorrection(
            candidate: SuggestionCandidate(heard: "add it", corrected: "audit", proposes: .term, origin: .fix),
            isStrong: false)
        let checkedWeak = DetectedCorrection(
            candidate: SuggestionCandidate(heard: "calender", corrected: "Calendar", proposes: .term, origin: .fix),
            isStrong: false)

        let choice = FixChoice(
            corrections: [vercel, embra, commit, checkedWeak],
            checked: [vercel.candidate.pair, checkedWeak.candidate.pair])

        #expect(choice.add == [vercel.candidate, checkedWeak.candidate])
        #expect(choice.suggest == [commit])
        #expect(choice.dismiss == [embra.candidate])
    }
}
