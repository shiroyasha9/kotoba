import Foundation
import Testing

@testable import KotobaCore

/// History's View Changes: the word-level change from one text of a dictation to another.
struct WordDiffTests {
    @Test func keptRemovedAndAddedWordsInReadingOrder() {
        let runs = WordDiff.runs(from: "um so fix the login bug", to: "Fix the login bug.")
        #expect(
            runs == [
                .init(.removed, "um so fix ", words: 3), .init(.added, "Fix ", words: 1),
                .init(.kept, "the login ", words: 2), .init(.removed, "bug", words: 1), .init(.added, "bug.", words: 1),
            ])
    }

    @Test func keptAndAddedRunsGiveTheLaterTextBack() {
        let before = "Look at the webhook handler.\nI think it double counts refunds."
        let after = "Look at the webhook handler in src/billing/webhook.ts.\n\n- Find where refunds are counted."
        let runs = WordDiff.runs(from: before, to: after)
        #expect(runs.filter { $0.kind != .removed }.map(\.text).joined() == after)
    }

    @Test func theSameTextIsOneKeptRun() {
        let text = "Ship it on Friday."
        #expect(WordDiff.runs(from: text, to: text) == [.init(.kept, text, words: 4)])
    }

    @Test func emptyTexts() {
        #expect(WordDiff.runs(from: "", to: "") == [])
        #expect(WordDiff.runs(from: "", to: "Hi there") == [.init(.added, "Hi there", words: 2)])
        #expect(WordDiff.runs(from: "  Hi", to: "") == [.init(.removed, "  Hi", words: 1)])
    }

    /// The bench's longest Polish input is 924 words; its rewrite keeps about 0.78 of them.
    static func longPolish() -> (before: String, after: String) {
        let words = (0..<924).map { "word\($0 % 97)" }
        let after = words.enumerated().filter { $0.offset % 5 != 0 }.map(\.element)
        return (words.joined(separator: " "), after.joined(separator: " "))
    }

    /// `TimingTests` times it.
    @Test func aLongPolishDiffs() {
        let (before, after) = Self.longPolish()
        let runs = WordDiff.runs(from: before, to: after)
        #expect(runs.filter { $0.kind == .removed }.map(\.words).reduce(0, +) >= 185)
    }
}
