import Foundation

/// One correction worth a suggestion. A strong one (the corrected side has code shape or a word the spell checker
/// does not know) is suggested at once; a weak one (known words on both sides, `add it` -> `audit`) needs more
/// evidence.
public struct DetectedCorrection: Sendable, Hashable {
    public var candidate: SuggestionCandidate
    public var isStrong: Bool

    public init(candidate: SuggestionCandidate, isStrong: Bool) {
        self.candidate = candidate
        self.isStrong = isStrong
    }
}

/// Finds dictionary material in the owner's edit of a pasted transcript (story 32,
/// docs/research/auto-learning.md 4.3). A word diff gives the changed spans; a span counts only when it is small, its
/// two sides sound alike, and the corrected side is a name or identifier, not a rewrite, a number or a path.
public enum CorrectionDetector {
    /// At most this many words on each side of one change.
    static let maxSpanWords = 4
    /// More changed words than this share of the transcript (or than `maxSpanWords`) is a rewrite, not a fix.
    static let maxChangedShare = 0.4
    /// Letter edit distance over the longer side: how far apart the heard and corrected spellings may be.
    static let maxStrongDistance = 0.5
    /// Known words on both sides must sound closer, or every word choice (`renamed` -> `removed`) passes.
    static let maxWeakDistance = 1.0 / 3.0

    /// `isKnownWord` is the spell checker's answer for one word; the App passes NSSpellChecker.
    public static func corrections(
        pasted: String,
        observed: String,
        dictionary: PersonalDictionary = PersonalDictionary(),
        dismissed: Set<SuggestionPair> = [],
        origin: SuggestionCandidate.Origin,
        isKnownWord: (String) -> Bool
    ) -> [DetectedCorrection] {
        let before = words(pasted)
        let after = words(observed)
        let spans = changedSpans(from: before, to: after)
        let changed = spans.reduce(0) { $0 + max($1.heard.count, $1.corrected.count) }
        guard Double(changed) <= max(Double(maxSpanWords), maxChangedShare * Double(before.count)) else { return [] }

        var seen: Set<SuggestionPair> = []
        return spans.flatMap { span in
            // Two words for two words are often two fixes side by side (`ZenTail website` -> `Zentyl template`).
            if span.heard.count > 1, span.heard.count == span.corrected.count {
                let pairs = zip(span.heard, span.corrected).compactMap { heard, corrected in
                    correction(Span(heard: [heard], corrected: [corrected]), origin: origin, isKnownWord: isKnownWord)
                }
                if !pairs.isEmpty { return pairs }
            }
            return correction(span, origin: origin, isKnownWord: isKnownWord).map { [$0] } ?? []
        }
        .filter { correction in
            !dismissed.contains(correction.candidate.pair) && !dictionary.contains(correction.candidate)
                && seen.insert(correction.candidate.pair).inserted
        }
    }

    /// "Add Selected Word" in the Fix window: the owner's selection, widened to whole words, as a word to add with no
    /// edit. Nil for an empty selection, more than `maxSpanWords` words, an address or markup, or no letters.
    public static func selectedWord(in text: String, range: Range<String.Index>) -> SuggestionCandidate? {
        // The editor's selection can lag its text by one update: a range past the text's end selects nothing.
        guard !range.isEmpty, range.upperBound <= text.endIndex else { return nil }
        var start = range.lowerBound
        while start > text.startIndex, !text[text.index(before: start)].isWhitespace {
            start = text.index(before: start)
        }
        var end = range.upperBound
        while end < text.endIndex, !text[end].isWhitespace {
            end = text.index(after: end)
        }
        let selected = words(String(text[start..<end]))
        guard selected.count <= maxSpanWords else { return nil }
        let word = trimmingPunctuation(selected.joined(separator: " "))
        guard hasLetters(word), !isAddressOrMarkup(word) else { return nil }
        return SuggestionCandidate(heard: word, corrected: word, proposes: .term, origin: .fix)
    }

    private struct Span {
        var heard: [String]
        var corrected: [String]
    }

    /// Whitespace-separated words; Markdown backticks do not count (`order_id` is order_id).
    private static func words(_ text: String) -> [String] {
        text.replacingOccurrences(of: "`", with: "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The runs of removed and inserted words between two matching words.
    private static func changedSpans(from before: [String], to after: [String]) -> [Span] {
        let difference = after.difference(from: before)
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var spans: [Span] = []
        var old = 0
        var new = 0
        while old < before.count || new < after.count {
            var span = Span(heard: [], corrected: [])
            while old < before.count, removed.contains(old) {
                span.heard.append(before[old])
                old += 1
            }
            while new < after.count, inserted.contains(new) {
                span.corrected.append(after[new])
                new += 1
            }
            if span.heard.isEmpty && span.corrected.isEmpty {
                old += 1
                new += 1
            } else {
                spans.append(span)
            }
        }
        return spans
    }

    private static func correction(
        _ span: Span, origin: SuggestionCandidate.Origin, isKnownWord: (String) -> Bool
    ) -> DetectedCorrection? {
        // A pure insertion or deletion (a false start, a list number) teaches no word.
        guard !span.heard.isEmpty, !span.corrected.isEmpty, span.heard.count <= maxSpanWords,
            span.corrected.count <= maxSpanWords, span.corrected.count <= 2 * span.heard.count
        else { return nil }
        let heard = trimmingPunctuation(span.heard.joined(separator: " "))
        let corrected = trimmingPunctuation(span.corrected.joined(separator: " "))
        guard heard != corrected, hasLetters(heard), hasLetters(corrected), !isAddressOrMarkup(heard),
            !isAddressOrMarkup(corrected)
        else { return nil }
        let heardWords = heard.split(separator: " ").map(String.init)
        let correctedWords = corrected.split(separator: " ").map(String.init)
        let hasCodeShape = correctedWords.contains(where: isCodeShaped)

        if heard.lowercased() == corrected.lowercased() {
            guard hasCodeShape else { return nil }
            return DetectedCorrection(
                candidate: SuggestionCandidate(heard: heard, corrected: corrected, proposes: .term, origin: origin),
                isStrong: true)
        }

        func isKnown(_ word: String) -> Bool { isKnownCompound(word, isKnownWord: isKnownWord) }
        let isRare = hasCodeShape || !correctedWords.allSatisfy(isKnown)
        // The model wrote a non-word where the owner meant a name the spell checker knows only with its capital
        // (`Orlina` -> `Orlena`, but not `Calender` -> `Calendar` at the start of a sentence).
        let isNameFix =
            !heardWords.allSatisfy(isKnown)
            && correctedWords.allSatisfy { $0.first?.isUppercase == true && !isKnown($0.lowercased()) }
        // Many spoken words may join into one rare word or identifier (`hashtag team ops` -> `#team-ops`), not into
        // a known word (`sea dex or so` -> `Codex`).
        guard span.heard.count <= 2 * span.corrected.count || isRare else { return nil }
        let isStrong = isRare || isNameFix
        guard letterDistance(heard, corrected) <= (isStrong ? maxStrongDistance : maxWeakDistance) else { return nil }
        let proposal = SuggestionCandidate.proposal(heard: heard, isKnownWord: isKnownWord)
        return DetectedCorrection(
            candidate: SuggestionCandidate(heard: heard, corrected: corrected, proposes: proposal, origin: origin),
            isStrong: isStrong)
    }

    /// A hyphenated word is known when each part is (`access-based`).
    private static func isKnownCompound(_ word: String, isKnownWord: (String) -> Bool) -> Bool {
        word.split(separator: "-").allSatisfy { part in
            let bare = part.trimmingCharacters(in: CharacterSet.letters.inverted)
            return bare.isEmpty || isKnownWord(bare)
        }
    }

    /// Sentence punctuation and quotes around a span are not part of the word (`Mellow.` -> `Mellow`); `#`, `_`
    /// and `-` are.
    private static func trimmingPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'()[]{}<>…“”‘’"))
    }

    private static func hasLetters(_ text: String) -> Bool {
        text.contains(where: \.isLetter)
    }

    /// Paths, URLs, web hosts, email addresses and markup are not words (docs/spec.md, Polish and learning). A dotted
    /// name is a host only when it is lowercase and ends in a common web TLD (`vercel.com`); framework names stay
    /// learnable (`Node.js`, `ASP.NET`).
    private static func isAddressOrMarkup(_ text: String) -> Bool {
        if text.contains(where: { "/\\<>@".contains($0) }) || text.hasPrefix("~") { return true }
        let lowercased = text.lowercased()
        if lowercased.contains("://") || lowercased.hasPrefix("www.") { return true }
        guard text == lowercased, text.contains(/^[\p{L}\d-]+(\.[\p{L}\d-]+)+$/),
            let tld = text.split(separator: ".").last
        else { return false }
        return webTLDs.contains(String(tld))
    }

    private static let webTLDs: Set<String> = ["com", "org", "net", "io", "ai", "dev", "app", "co", "in", "so"]

    /// An identifier shape the spell checker cannot judge: inner capitals (`GitHub`), `_`, `#`, a dot between
    /// letters (`Node.js`), letters with digits, or an acronym (`API`). A hyphen alone is not one: `access-based`
    /// is two English words.
    static func isCodeShaped(_ word: String) -> Bool {
        let letters = word.filter(\.isLetter)
        guard !letters.isEmpty else { return false }
        if word.contains("_") || word.contains("#") || word.contains(/\p{L}\.\p{L}/) { return true }
        if word.contains(where: \.isNumber) { return true }
        if letters.count >= 2 && letters.allSatisfy(\.isUppercase) { return true }
        return letters.dropFirst().contains(where: \.isUppercase) && letters.contains(where: \.isLowercase)
    }

    /// Edit distance between the letters and digits of both sides, over the longer one: spaces, `_` and `-` do not
    /// count (`order ID` and `order_id` are the same), and a spoken "hashtag" is `#`.
    static func letterDistance(_ heard: String, _ corrected: String) -> Double {
        let source = letterKey(heard)
        let target = letterKey(corrected)
        guard !source.isEmpty, !target.isEmpty else { return source.isEmpty && target.isEmpty ? 0 : 1 }
        var previous = Array(0...target.count)
        for row in source.indices {
            var current = [row + 1] + Array(repeating: 0, count: target.count)
            for column in target.indices {
                let cost = source[row] == target[column] ? 0 : 1
                current[column + 1] = min(previous[column + 1] + 1, current[column] + 1, previous[column] + cost)
            }
            previous = current
        }
        return Double(previous[target.count]) / Double(max(source.count, target.count))
    }

    /// The letters and digits `letterDistance` compares: lowercase, with a spoken "hashtag" for `#`.
    static func letterKey(_ text: String) -> [Character] {
        Array(text.lowercased().replacingOccurrences(of: "#", with: "hashtag").filter { $0.isLetter || $0.isNumber })
    }
}

/// What the owner's checkboxes in "Fix Last Dictation…" do (lead decision 1, phase 2.5 review): a checked
/// correction is added; an unchecked weak one becomes a pending suggestion, shown once it is seen again; an unchecked
/// strong one was a clear no, so it is dismissed and never suggested.
public struct FixChoice: Sendable, Equatable {
    public var add: [SuggestionCandidate] = []
    public var suggest: [DetectedCorrection] = []
    public var dismiss: [SuggestionCandidate] = []

    public init(corrections: [DetectedCorrection], checked: Set<SuggestionPair>) {
        for correction in corrections {
            if checked.contains(correction.candidate.pair) {
                add.append(correction.candidate)
            } else if correction.isStrong {
                dismiss.append(correction.candidate)
            } else {
                suggest.append(correction)
            }
        }
    }
}

/// What kotoba does with the corrections in an edit it read back after a paste (docs/spec.md, Owner round
/// 2026-10-16): a strong one is added at once, and the pill offers Undo; a weak one waits in Suggestions. Strong ones
/// wait in Suggestions too when the edit is not settled (the owner may have typed on after the last read, so a word
/// can be cut), or when a new dictation ended the session (no pill is free for the Undo).
public struct ReadbackChoice: Sendable, Equatable {
    public var add: [SuggestionCandidate] = []
    public var suggest: [DetectedCorrection] = []

    public init(corrections: [DetectedCorrection], of edit: EditReadback.Edit) {
        let addsAtOnce = edit.isSettled && edit.endedBy != .nextDictation
        for correction in corrections {
            if correction.isStrong, addsAtOnce {
                add.append(correction.candidate)
            } else {
                suggest.append(correction)
            }
        }
    }
}
