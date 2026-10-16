import Foundation

/// The keyterms of one dictation that got its text, after the paste: which went with the request, and which the text
/// has. The App counts the hits in `term_use` (`TermRanking` ranks by them) and the Dictionary pane marks the terms that
/// were not sent.
public struct TermReport: Sendable, Equatable {
    public var sent: [String]
    /// Each term once, however often the text has it.
    public var hits: [String]
    public var at: Date

    public init(sent: [String], hits: [String], at: Date) {
        self.sent = sent
        self.hits = hits
        self.at = at
    }
}

/// Finds which keyterms a delivered text has: whole words in any case, so `zod` does not match `zodiac`, and a term
/// with punctuation (`order_id`, `auth.ts`) matches as written. A side of a term that ends in punctuation needs no word
/// edge, as in `ReplacementRule.wordEdges`. The terms come from `PersonalDictionary.keyterms`: trimmed, none empty.
///
/// One `memmem` per term over the lowercased UTF-8 text: 300 terms on a 2,000-word text take about 3 ms, against
/// 0.6 s with `String.range(of:options: .caseInsensitive)` (release build).
enum TermHits {
    static func find(_ terms: [String], in text: String) -> [String] {
        let haystack = Array(text.lowercased().utf8)
        guard !haystack.isEmpty else { return [] }
        return haystack.withUnsafeBufferPointer { haystack in
            terms.filter { term in
                contains(
                    Array(term.lowercased().utf8), edges: ReplacementRule.wordEdges(of: term), in: haystack)
            }
        }
    }

    private static func contains(
        _ needle: [UInt8], edges: ReplacementRule.WordEdges, in haystack: UnsafeBufferPointer<UInt8>
    ) -> Bool {
        guard let base = haystack.baseAddress, !needle.isEmpty else { return false }
        var start = 0
        while start + needle.count <= haystack.count {
            guard let found = memmem(base + start, haystack.count - start, needle, needle.count) else { return false }
            let lower = base.distance(to: found.assumingMemoryBound(to: UInt8.self))
            let upper = lower + needle.count
            let isEdgeBefore = !edges.before || !isWordScalar(endingAt: lower, in: haystack)
            let isEdgeAfter = !edges.after || !isWordScalar(startingAt: upper, in: haystack)
            if isEdgeBefore, isEdgeAfter { return true }
            start = lower + 1
        }
        return false
    }

    /// The scalar whose UTF-8 ends just before `index` is a word character; false at the start.
    private static func isWordScalar(endingAt index: Int, in text: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index > 0 else { return false }
        var first = index - 1
        while first > 0, text[first] & 0b1100_0000 == 0b1000_0000 { first -= 1 }
        return isWordScalar(in: text[first..<index])
    }

    /// The scalar whose UTF-8 starts at `index` is a word character; false at the end.
    private static func isWordScalar(startingAt index: Int, in text: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index < text.count else { return false }
        var end = index + 1
        while end < text.count, text[end] & 0b1100_0000 == 0b1000_0000 { end += 1 }
        return isWordScalar(in: text[index..<end])
    }

    private static func isWordScalar(in bytes: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        guard case .scalarValue(let scalar) = decoder.decode(&iterator) else { return false }
        return ReplacementRule.isWordScalar(scalar)
    }
}
