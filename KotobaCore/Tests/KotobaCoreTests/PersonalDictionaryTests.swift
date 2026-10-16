import Foundation
import Testing

@testable import KotobaCore

/// Find-and-replace after transcription (story 25).
struct ReplacementTests {
    @Test func aRuleMatchesWholeWordsInAnyCase() {
        let rules = [ReplacementRule(find: "cloud code", replacement: "Claude Code")]
        let text = PersonalDictionary(rules: rules).applyReplacements(to: "Cloud Code and cloud code, not cloud coder.")
        #expect(text == "Claude Code and Claude Code, not cloud coder.")
    }

    @Test func aWholeWordRuleSkipsPartsOfWords() {
        let rules = [ReplacementRule(find: "uv", replacement: "uv")]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "UV and uvicorn") == "uv and uvicorn")
    }

    @Test func aRuleThatIsNotWholeWordMatchesInsideWords() {
        let rules = [ReplacementRule(find: "colour", replacement: "color", isWholeWord: false)]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "Colourful colours") == "colorful colors")
    }

    @Test func aCaseSensitiveRuleMatchesOnlyItsOwnCase() {
        let rules = [ReplacementRule(find: "Go", replacement: "Golang", isCaseSensitive: true)]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "Go go Go") == "Golang go Golang")
    }

    @Test func findTextWithSymbolsMatchesLiterally() {
        let rules = [
            ReplacementRule(find: "c++", replacement: "C++"),
            ReplacementRule(find: "$home", replacement: "$HOME"),
            ReplacementRule(find: "a.b", replacement: "x"),
        ]
        let text = PersonalDictionary(rules: rules).applyReplacements(to: "c++ in $home, not aXb but a.b")
        #expect(text == "C++ in $HOME, not aXb but x")
    }

    @Test func theReplacementIsInsertedLiterally() {
        let rules = [ReplacementRule(find: "dollar one", replacement: #"$1 \n"#)]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "say dollar one") == #"say $1 \n"#)
    }

    @Test func theLongestFindWinsWhereTwoRulesOverlap() {
        let rules = [
            ReplacementRule(find: "router", replacement: "Router"),
            ReplacementRule(find: "open router", replacement: "OpenRouter"),
        ]
        let text = PersonalDictionary(rules: rules).applyReplacements(to: "open router and the router")
        #expect(text == "OpenRouter and the Router")
    }

    @Test func aReplacementIsNotReplacedAgain() {
        let rules = [
            ReplacementRule(find: "a", replacement: "b"),
            ReplacementRule(find: "b", replacement: "c"),
        ]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "a b") == "b c")
    }

    @Test func textWithoutMatchesAndEmptyRulesStayTheSame() {
        let text = "Nothing to fix here. 日本語 too."
        #expect(PersonalDictionary(rules: []).applyReplacements(to: text) == text)
        let rules = [ReplacementRule(find: "kotoba", replacement: "Kotoba")]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: text) == text)
    }

    @Test func wordEdgesWorkNextToEmojiAndNonLatinText() {
        let rules = [ReplacementRule(find: "wispr", replacement: "Wispr")]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "🎤wispr、日本") == "🎤Wispr、日本")
    }

    @Test func findTextThatStartsOrEndsWithASymbolMatchesNextToWords() {
        let rules = [ReplacementRule(find: "->", replacement: "→"), ReplacementRule(find: ".js", replacement: ".ts")]
        let text = PersonalDictionary(rules: rules).applyReplacements(to: "a->b and app.js but not app.json")
        #expect(text == "a→b and app.ts but not app.json")
    }

    @Test func wholeWordAndInWordRulesKeepLongestFirstPrecedence() {
        let rules = [
            ReplacementRule(find: "ab", replacement: "X", isWholeWord: false),
            ReplacementRule(find: "abc", replacement: "Y"),
        ]
        #expect(PersonalDictionary(rules: rules).applyReplacements(to: "abc abcd") == "Y Xcd")
    }

    @Test func manyRulesOnALongTranscriptStayFast() {
        let rules = (0..<200).map { ReplacementRule(find: "phrase number \($0)", replacement: "P\($0)") }
        let words = ["so", "I", "opened", "the", "router", "and", "phrase", "number", "7", "again"]
        let text = (0..<2_000).map { words[$0 % words.count] }.joined(separator: " ")
        let dictionary = PersonalDictionary(rules: rules)
        let clock = ContinuousClock()

        var replaced = ""
        let elapsed = clock.measure { replaced = dictionary.applyReplacements(to: text) }

        #expect(replaced.contains("P7"))
        // Measured 2026-10-15 (debug build): see the dictionary report; the limit leaves wide room for a busy machine.
        #expect(elapsed < .milliseconds(250))
    }

    @Test func theDictionaryAppliesItsOwnRules() {
        let dictionary = PersonalDictionary(rules: [ReplacementRule(find: "kotoba", replacement: "kotoba.app")])
        #expect(dictionary.applyReplacements(to: "open kotoba") == "open kotoba.app")
    }
}

/// The dictionary sent to the model as keyterms or phrase list (story 24).
struct KeytermTests {
    @Test func aRuleFindTextIsNeverAKeyterm() {
        let dictionary = PersonalDictionary(
            terms: ["Xandor"],
            rules: [ReplacementRule(find: "Zandor", replacement: "Xandor")]
        )
        #expect(dictionary.keyterms == ["Xandor"])
    }

    @Test func keytermsAreTheTermsAndTheRuleReplacements() {
        let dictionary = PersonalDictionary(
            terms: ["PyTorch", "zshrc"],
            rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")]
        )
        #expect(dictionary.keyterms == ["PyTorch", "zshrc", "Claude Code"])
    }

    @Test func keytermsAreTrimmedAndDeDuplicatedIgnoringCase() {
        let dictionary = PersonalDictionary(
            terms: [" Vercel ", "vercel", ""],
            rules: [ReplacementRule(find: "versacell", replacement: "Vercel")]
        )
        #expect(dictionary.keyterms == ["Vercel"])
    }

    @Test func keytermsSkipTermsLongerThanTheLimit() {
        let long = String(repeating: "x", count: PersonalDictionary.maxKeytermLength + 1)
        let longest = String(repeating: "y", count: PersonalDictionary.maxKeytermLength)
        let dictionary = PersonalDictionary(terms: [long, longest])
        #expect(dictionary.keyterms == [longest])
    }

    /// `TermRanking` picks which keyterms a request sends; the dictionary lists them all.
    @Test func keytermsKeepEveryTermOverTheCap() {
        let terms = (0..<150).map { "term\($0)" }
        #expect(PersonalDictionary(terms: terms).keyterms == terms)
    }
}

/// Editing keeps the dictionary free of duplicates.
struct DictionaryEditTests {
    @Test func addingATermTrimsIt() throws {
        var dictionary = PersonalDictionary()
        try dictionary.addTerm("  Supabase ")
        #expect(dictionary.terms == ["Supabase"])
    }

    @Test func anEmptyTermIsRefused() {
        var dictionary = PersonalDictionary()
        #expect(throws: DictionaryError.empty) { try dictionary.addTerm("  ") }
    }

    @Test func aTermThatDiffersOnlyInCaseIsADuplicate() throws {
        var dictionary = PersonalDictionary(terms: ["PyTorch"])
        #expect(throws: DictionaryError.duplicate) { try dictionary.addTerm("pytorch") }
        #expect(dictionary.terms == ["PyTorch"])
    }

    @Test func editingATermCanChangeItsCase() throws {
        var dictionary = PersonalDictionary(terms: ["pytorch", "uv"])
        try dictionary.updateTerm(at: 0, to: "PyTorch")
        #expect(dictionary.terms == ["PyTorch", "uv"])
        #expect(throws: DictionaryError.duplicate) { try dictionary.updateTerm(at: 0, to: "UV") }
    }

    @Test func aRuleNeedsFindText() {
        var dictionary = PersonalDictionary()
        #expect(throws: DictionaryError.empty) {
            try dictionary.addRule(ReplacementRule(find: " ", replacement: "x"))
        }
    }

    @Test func aRuleMayReplaceWithNothing() throws {
        var dictionary = PersonalDictionary()
        try dictionary.addRule(ReplacementRule(find: "um", replacement: ""))
        #expect(dictionary.rules == [ReplacementRule(find: "um", replacement: "")])
    }

    @Test func twoRulesForTheSameFindTextAreDuplicates() throws {
        var dictionary = PersonalDictionary(rules: [ReplacementRule(find: "Cloud Code", replacement: "Claude Code")])
        #expect(throws: DictionaryError.duplicate) {
            try dictionary.addRule(ReplacementRule(find: "cloud code ", replacement: "claude-code"))
        }
        try dictionary.updateRule(at: 0, to: ReplacementRule(find: "cloud code", replacement: "claude-code"))
        #expect(dictionary.rules == [ReplacementRule(find: "cloud code", replacement: "claude-code")])
    }

    @Test func caseSensitiveRulesForDifferentCasesAreNotDuplicates() throws {
        var dictionary = PersonalDictionary(rules: [
            ReplacementRule(find: "Go", replacement: "Go", isCaseSensitive: true)
        ])
        try dictionary.addRule(ReplacementRule(find: "go", replacement: "go", isCaseSensitive: true))
        #expect(dictionary.rules.count == 2)
        #expect(throws: DictionaryError.duplicate) {
            try dictionary.addRule(ReplacementRule(find: "GO", replacement: "x"))
        }
    }
}

/// Importing another dictionary (story 26): preview counts first, then apply.
struct DictionaryImportTests {
    @Test func anImportAddsOnlyWhatIsNew() {
        let existing = PersonalDictionary(
            terms: ["PyTorch"],
            rules: [ReplacementRule(find: "cloud code", replacement: "Claude Code")]
        )
        let incoming = PersonalDictionary(
            terms: ["pytorch", "Vercel", "Vercel", " "],
            rules: [
                ReplacementRule(find: "Cloud Code", replacement: "claude code"),
                ReplacementRule(find: "open router", replacement: "OpenRouter"),
            ]
        )

        let preview = existing.importPreview(of: incoming)

        #expect(preview.terms == ["Vercel"])
        #expect(preview.rules == [ReplacementRule(find: "open router", replacement: "OpenRouter")])
        #expect(preview.duplicateCount == 3)
        #expect(preview.isEmpty == false)
    }

    @Test func applyingAPreviewAppendsItsEntries() {
        var dictionary = PersonalDictionary(terms: ["PyTorch"])
        let preview = dictionary.importPreview(of: PersonalDictionary(terms: ["Vercel"]))

        dictionary.apply(preview)

        #expect(dictionary.terms == ["PyTorch", "Vercel"])
    }

    @Test func aWordAddedAfterThePreviewIsNotAddedTwice() throws {
        var dictionary = PersonalDictionary()
        let preview = dictionary.importPreview(
            of: PersonalDictionary(terms: ["zod"], rules: [ReplacementRule(find: "a", replacement: "b")]))
        try dictionary.addTerm("Zod")
        try dictionary.addRule(ReplacementRule(find: "A", replacement: "c"))

        dictionary.apply(preview)

        #expect(dictionary.terms == ["Zod"])
        #expect(dictionary.rules == [ReplacementRule(find: "A", replacement: "c")])
    }

    @Test func importingTheSameDictionaryTwiceAddsNothing() {
        var dictionary = PersonalDictionary()
        let incoming = PersonalDictionary(terms: ["uv"], rules: [ReplacementRule(find: "a", replacement: "b")])
        dictionary.apply(dictionary.importPreview(of: incoming))

        let second = dictionary.importPreview(of: incoming)

        #expect(second.isEmpty)
        #expect(second.duplicateCount == 2)
    }
}
