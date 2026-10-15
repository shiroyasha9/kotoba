import Foundation
import Testing

@testable import KotobaCore

/// Finding the owner's edit of the pasted text in the field, and what it teaches (docs/research/auto-learning.md,
/// Readback).
struct PastedSpanTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var pasted: String
        var field: String
        /// Nil: the pasted text is gone.
        var span: String?

        var testDescription: String { name }
    }

    static let cases: [Case] = [
        Case(
            name: "unchanged paste between other text", pasted: "deploy it to versel today",
            field: "Hi team,\ndeploy it to versel today\nThanks", span: "deploy it to versel today"),
        Case(
            name: "a fixed word in the middle", pasted: "deploy it to versel today",
            field: "Hi team,\ndeploy it to Vercel today\nThanks", span: "deploy it to Vercel today"),
        Case(
            name: "a respelled first word stays in", pasted: "Tavia said the plan is ready",
            field: "Re: notes Taviya said the plan is ready", span: "Taviya said the plan is ready"),
        Case(
            name: "a changed last word stays in", pasted: "send it to Mellow.",
            field: "send it to Marlow. Thanks", span: "send it to Marlow."),
        Case(
            name: "words joined into one", pasted: "rename the order ID column",
            field: "rename the order_id column", span: "rename the order_id column"),
        Case(
            name: "the same words elsewhere in the field are not the paste", pasted: "ship the ember package today",
            field: "ship the docs today. Later: ship the embra package today", span: "ship the embra package today"),
        Case(
            name: "words typed after the paste are not part of it", pasted: "call Orlina about dinner",
            field: "call Orlena about dinner and then ask Sam", span: "call Orlena about dinner"),
        Case(
            name: "two words joined at the end, then other text", pasted: "Rina made one called Sun Deck.",
            field: "Rina made one called Sundeck.\nAnd a line after it", span: "Rina made one called Sundeck."),
        Case(name: "an emptied field", pasted: "deploy it to versel today", field: "", span: nil),
        Case(
            name: "a rewritten text", pasted: "deploy it to versel today",
            field: "we will talk about this tomorrow", span: nil),
        Case(name: "a one-word paste respelled", pasted: "Tavia.", field: "Taviya.", span: "Taviya."),
        Case(
            name: "a two-word paste replaced by another text", pasted: "Okay, thanks.",
            field: "Something else entirely", span: nil),
    ]

    @Test(arguments: cases)
    func findsTheEditedSpan(_ testCase: Case) {
        #expect(PastedSpan.find(testCase.pasted, in: testCase.field) == testCase.span)
    }

    struct Learned: Sendable, CustomTestStringConvertible {
        var name: String
        var pasted: String
        var field: String
        /// heard, corrected, strong.
        var expected: [String]

        var testDescription: String { name }
    }

    static let learned: [Learned] = [
        Learned(
            name: "an unknown word fixed in a message", pasted: "deploy it to versel today",
            field: "Hi team,\ndeploy it to Vercel today\nThanks", expected: ["versel -> Vercel strong"]),
        Learned(
            name: "a name fixed at the start", pasted: "Tavia said the plan is ready",
            field: "Re: notes Taviya said the plan is ready", expected: ["Tavia -> Taviya strong"]),
        Learned(
            name: "a spoken identifier", pasted: "rename the order ID column", field: "rename the order_id column",
            expected: ["order ID -> order_id strong"]),
        Learned(
            name: "a common word gives a weak one", pasted: "please add it the change now",
            field: "please audit the change now", expected: ["add it -> audit weak"]),
        Learned(
            name: "a word choice teaches nothing", pasted: "I was drafting the docs",
            field: "I was editing the docs", expected: []),
        Learned(
            name: "text typed after the paste teaches nothing", pasted: "deploy it to versel today",
            field: "deploy it to versel today and Kubernetes later", expected: []),
    ]

    @Test(arguments: learned)
    func theEditTeachesItsCorrections(_ testCase: Learned) throws {
        let span = try #require(PastedSpan.find(testCase.pasted, in: testCase.field))
        let found = CorrectionDetector.corrections(
            pasted: testCase.pasted, observed: span, origin: .edit, isKnownWord: CorrectionDetectorTests.isKnownWord)

        let described = found.map {
            "\($0.candidate.heard) -> \($0.candidate.corrected) \($0.isStrong ? "strong" : "weak")"
        }
        #expect(described == testCase.expected)
    }

    /// The longest dictation followed, respelled in the middle of a field three times its size.
    @Test func theLongestFollowedDictationIsFound() {
        let vocabulary = CorrectionDetectorTests.english.sorted()
        var generator = SystemRandomNumberGenerator()
        let words = (0..<200).map { _ in vocabulary.randomElement(using: &generator) ?? "" }
        var edited = words
        edited[100] = "Taviya"
        let other = (0..<200).map { _ in vocabulary.randomElement(using: &generator) ?? "" }
        let field = (other + edited + other).joined(separator: " ")

        let span = PastedSpan.find(words.joined(separator: " "), in: field)

        #expect(span?.hasSuffix(edited.suffix(150).joined(separator: " ")) == true)
        #expect(span?.contains("Taviya") == true)
    }
}
