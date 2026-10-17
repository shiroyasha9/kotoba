import Foundation
import Testing

@testable import KotobaCore

/// Spoken "new line" and "new paragraph" as line breaks, over the shapes speech models write them in.
struct LineBreakPhraseTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var heard: String
        /// What is pasted.
        var text: String

        var testDescription: String { name }
    }

    static let breaks: [Case] = [
        Case(name: "own sentence", heard: "First point. New line. Second point.", text: "First point.\nSecond point."),
        Case(
            name: "mid sentence", heard: "Dear Bob, new line thanks for the update.",
            text: "Dear Bob,\nThanks for the update."),
        Case(name: "between commas", heard: "Buy milk, new line, buy eggs.", text: "Buy milk,\nBuy eggs."),
        Case(name: "lower-case transcript", heard: "buy milk new line buy eggs", text: "buy milk\nbuy eggs"),
        Case(name: "one word", heard: "Step one. Newline. Step two.", text: "Step one.\nStep two."),
        Case(name: "hyphenated", heard: "Step one. New-line. Step two.", text: "Step one.\nStep two."),
        Case(name: "upper case", heard: "Done. NEW LINE. Next.", text: "Done.\nNext."),
        Case(name: "after a question", heard: "Is it done? New line? Yes.", text: "Is it done?\nYes."),
        Case(
            name: "paragraph", heard: "Hi Ravi. New paragraph. The report is late.",
            text: "Hi Ravi.\n\nThe report is late."),
        Case(name: "two in a row", heard: "Item one new line new line item two", text: "Item one\n\nItem two"),
        Case(name: "mixed-case word", heard: "Buy it. New line. iPhone case.", text: "Buy it.\niPhone case."),
        Case(name: "at the end", heard: "Fix the bug. New line.", text: "Fix the bug."),
        Case(name: "at the start", heard: "New paragraph. Hello there.", text: "Hello there."),
    ]

    static let text: [Case] = [
        Case(name: "alone", heard: "New line.", text: "New line."),
        Case(name: "paragraph alone", heard: "New paragraph!", text: "New paragraph!"),
        Case(
            name: "after an article", heard: "Add a new line after the header.",
            text: "Add a new line after the header."),
        Case(
            name: "paragraph after an article", heard: "Start a new paragraph here.",
            text: "Start a new paragraph here."),
        Case(name: "after the", heard: "Strip the newline character.", text: "Strip the newline character."),
        Case(name: "before of", heard: "We launched new line of products.", text: "We launched new line of products."),
        Case(name: "plural", heard: "Count new lines today. New lines.", text: "Count new lines today. New lines."),
        Case(name: "part of a word", heard: "Renew line items today.", text: "Renew line items today."),
        Case(name: "quoted", heard: "Say “new line” to break.", text: "Say “new line” to break."),
        Case(name: "possessive", heard: "Check new line's color.", text: "Check new line's color."),
        Case(name: "empty", heard: "", text: ""),
    ]

    @Test(arguments: breaks)
    func turnsTheCommandIntoBreaks(_ testCase: Case) {
        #expect(LineBreakPhrase.apply(to: testCase.heard) == testCase.text)
    }

    @Test(arguments: text)
    func leavesOtherUsesAsText(_ testCase: Case) {
        #expect(LineBreakPhrase.apply(to: testCase.heard) == testCase.text)
    }
}
