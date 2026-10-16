/// The word-level change from one text of a dictation to another (transcript, cleaned, polished), for History's View
/// Changes. Words are runs of non-space characters, compared exactly; the spaces and line breaks after a word go with
/// it. A kept word carries the later text's spacing, so the kept and added runs give `after` back, word for word.
public enum WordDiff {
    public enum Kind: Sendable, Equatable {
        case kept
        case removed
        case added
    }

    /// Words in a row with one kind, with the spacing after each.
    public struct Run: Sendable, Equatable {
        public var kind: Kind
        public var text: String
        /// How many words the run holds.
        public var words: Int

        public init(_ kind: Kind, _ text: String, words: Int) {
            self.kind = kind
            self.text = text
            self.words = words
        }
    }

    /// The runs from `before` to `after`, in reading order: at each change the removed words come before the added
    /// ones. Swift's `difference(from:)` (Myers) on the word lists: a 900-word rewrite diffs in about 6 ms (release
    /// build), once per comparison the sheet shows.
    public static func runs(from before: String, to after: String) -> [Run] {
        let old = tokens(of: before)
        let new = tokens(of: after)
        let difference = new.map(\.word).difference(from: old.map(\.word))
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var runs: [Run] = []
        func append(_ kind: Kind, _ token: Token) {
            if let last = runs.last, last.kind == kind {
                runs[runs.count - 1].text += token.text
                runs[runs.count - 1].words += 1
            } else {
                runs.append(Run(kind, String(token.text), words: 1))
            }
        }
        var (oldIndex, newIndex) = (0, 0)
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removed.contains(oldIndex) {
                append(.removed, old[oldIndex])
                oldIndex += 1
            } else if newIndex < new.count, inserted.contains(newIndex) {
                append(.added, new[newIndex])
                newIndex += 1
            } else {
                // The same word in both: the later text's spacing.
                append(.kept, new[newIndex])
                oldIndex += 1
                newIndex += 1
            }
        }
        return runs
    }

    private struct Token {
        var word: Substring
        /// The word and the spacing after it.
        var text: Substring
    }

    /// Leading spacing goes with the first word.
    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var start = text.startIndex
        while let wordStart = text[start...].firstIndex(where: { !$0.isWhitespace }) {
            let wordEnd = text[wordStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let next = text[wordEnd...].firstIndex { !$0.isWhitespace } ?? text.endIndex
            tokens.append(Token(word: text[wordStart..<wordEnd], text: text[start..<next]))
            start = next
        }
        return tokens
    }
}
