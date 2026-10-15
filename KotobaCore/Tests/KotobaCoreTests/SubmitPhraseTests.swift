import Foundation
import Testing

@testable import KotobaCore

/// The spoken submit phrase at the end of a transcript (docs/research/beyond-wispr.md, idea 3).
struct SubmitPhraseTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var heard: String
        /// What is pasted.
        var text: String
        var submits: Bool

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(name: "own sentence", heard: "Fix the login bug. Press enter.", text: "Fix the login bug.", submits: true),
        Case(name: "no punctuation", heard: "fix the login bug press enter", text: "fix the login bug", submits: true),
        Case(name: "after a comma", heard: "Fix the login bug, press Enter!", text: "Fix the login bug", submits: true),
        Case(name: "upper case", heard: "Fix the login bug. PRESS ENTER", text: "Fix the login bug.", submits: true),
        Case(name: "return", heard: "Run the tests. Press return.", text: "Run the tests.", submits: true),
        Case(name: "hyphenated", heard: "Run the tests. Press-enter.", text: "Run the tests.", submits: true),
        Case(name: "after a dash", heard: "Run the tests - press enter", text: "Run the tests", submits: true),
        Case(name: "trailing ellipsis", heard: "Run the tests. Press enter… ", text: "Run the tests.", submits: true),
        Case(
            name: "only the last phrase", heard: "Fix it. Press enter. Press enter.", text: "Fix it. Press enter.",
            submits: true),
        Case(
            name: "in the middle", heard: "Press enter to submit the form.", text: "Press enter to submit the form.",
            submits: false),
        Case(name: "part of a word", heard: "Book express return.", text: "Book express return.", submits: false),
        Case(name: "new line", heard: "Run the tests.\nPress enter", text: "Run the tests.", submits: true),
        Case(name: "phrase alone", heard: "Press enter.", text: "Press enter.", submits: false),
        Case(name: "phrase alone, return", heard: "Press return!", text: "Press return!", submits: false),
        Case(name: "send it is text", heard: "Looks good, send it.", text: "Looks good, send it.", submits: false),
        Case(name: "empty", heard: "", text: "", submits: false),
    ]

    @Test(arguments: cases)
    func splitsTheTrailingPhrase(_ testCase: Case) {
        let split = SubmitPhrase.split(testCase.heard)
        #expect(split.text == testCase.text)
        #expect(split.submits == testCase.submits)
    }
}
