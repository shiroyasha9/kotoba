import Foundation

/// The owner's words: terms sent to the model as keyterms or phrase list, and find-and-replace rules applied to the
/// transcript before the paste.
public struct PersonalDictionary: Sendable, Equatable {
    /// xAI caps `keyterm` at 100 terms of up to 50 characters. MAI's `phraseList` limits are not published
    /// (docs/spec.md, Unresolved Questions), so it gets the same list.
    public static let maxKeyterms = 100
    public static let maxKeytermLength = 50

    public var terms: [String]
    public var rules: [ReplacementRule]

    public init(terms: [String] = [], rules: [ReplacementRule] = []) {
        self.terms = terms
        self.rules = rules
    }

    /// The terms, then the spelling each rule writes, trimmed, without case-insensitive duplicates, at most
    /// `maxKeytermLength` characters each and `maxKeyterms` in all. kotoba-bench-v1 measured MAI and Grok with
    /// a list built the same way from Wispr's dictionary.
    public var keyterms: [String] {
        var seen: Set<String> = []
        var keyterms: [String] = []
        for term in terms + rules.map(\.replacement) {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed.count <= Self.maxKeytermLength,
                seen.insert(trimmed.lowercased()).inserted
            else { continue }
            keyterms.append(trimmed)
            if keyterms.count == Self.maxKeyterms { break }
        }
        return keyterms
    }

    /// Replaces every match of every rule in one pass over `text`, so a replacement is never matched again.
    /// Where two rules match at the same place, the longer find text wins.
    public func applyReplacements(to text: String) -> String {
        let active = rules.enumerated()
            .filter { !$0.element.find.isEmpty }
            .sorted { ($0.element.find.count, $1.offset) > ($1.element.find.count, $0.offset) }
            .map(\.element)
        guard !active.isEmpty else { return text }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: Self.pattern(for: active))
        } catch {
            Log.pipeline.error("Replacement rules did not compile, transcript left as is: \(error)")
            return text
        }
        var result = ""
        var cursor = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text),
                let rule = active.indices.first(where: { match.range(at: $0 + 1).location != NSNotFound })
            else { continue }
            result += text[cursor..<range.lowerBound]
            result += active[rule].replacement
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// One capture group per rule, in order. Neighbouring rules that need the same word-edge checks share one
    /// `(?<!\w)(?:…)(?!\w)` group, so ICU runs each check once per position, not once per rule: 200 rules on a
    /// 2,000-word transcript went from about 140 ms to 14 ms (release build, phase 2 review). Sharing keeps the
    /// longest-first order.
    private static func pattern(for rules: [ReplacementRule]) -> String {
        var groups: [(edges: ReplacementRule.WordEdges, alternatives: [String])] = []
        for rule in rules {
            let alternative = "(\(rule.literalPattern))"
            if let last = groups.last, last.edges == rule.wordEdges {
                groups[groups.count - 1].alternatives.append(alternative)
            } else {
                groups.append((rule.wordEdges, [alternative]))
            }
        }
        return groups.map { group in
            let alternatives = "(?:" + group.alternatives.joined(separator: "|") + ")"
            return (group.edges.before ? #"(?<!\w)"# : "") + alternatives + (group.edges.after ? #"(?!\w)"# : "")
        }.joined(separator: "|")
    }
}

/// Replaces `find` with `replacement` in every transcript. By default it matches whole words in any case, like
/// Wispr Flow's replacements: "cloud code" -> "Claude Code" fixes "Cloud Code" too, but not "cloud coder".
public struct ReplacementRule: Sendable, Hashable {
    public var find: String
    /// Inserted as is; may be empty to delete the match.
    public var replacement: String
    /// Matches only where the find text is not part of a longer word (letters, digits and `_`).
    public var isWholeWord: Bool
    public var isCaseSensitive: Bool

    public init(find: String, replacement: String, isWholeWord: Bool = true, isCaseSensitive: Bool = false) {
        self.find = find
        self.replacement = replacement
        self.isWholeWord = isWholeWord
        self.isCaseSensitive = isCaseSensitive
    }

    /// Which sides need a word-edge check: a whole-word rule checks only a side whose find text has a word character
    /// there, so `->` still matches in `a->b`.
    struct WordEdges: Equatable {
        var before: Bool
        var after: Bool
    }

    var wordEdges: WordEdges {
        guard isWholeWord, let first = find.first, let last = find.last else {
            return WordEdges(before: false, after: false)
        }
        return WordEdges(before: Self.isWordCharacter(first), after: Self.isWordCharacter(last))
    }

    /// The find text matched literally, in any case unless the rule is case-sensitive.
    var literalPattern: String {
        let escaped = NSRegularExpression.escapedPattern(for: find)
        return isCaseSensitive ? escaped : "(?i:\(escaped))"
    }

    /// What ICU's `\w` matches: letters, marks, digits and connector punctuation such as `_`.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            let properties = scalar.properties
            return properties.isAlphabetic || properties.generalCategory == .decimalNumber
                || properties.generalCategory == .connectorPunctuation || properties.isGraphemeExtend
        }
    }

    /// True when both rules can match the same text, so keeping both makes the result depend on their order.
    func overlaps(_ other: Self) -> Bool {
        guard find.caseInsensitiveCompare(other.find) == .orderedSame else { return false }
        return !isCaseSensitive || !other.isCaseSensitive || find == other.find
    }
}

public enum DictionaryError: Error, Sendable, Equatable {
    /// The term or find text is blank.
    case empty
    /// The dictionary already has this term (in any case) or a rule for this find text.
    case duplicate
}

/// What an import adds: the entries that are new, and how many were already in the dictionary.
public struct DictionaryImport: Sendable, Equatable {
    public var terms: [String] = []
    public var rules: [ReplacementRule] = []
    public var duplicateCount = 0

    public var isEmpty: Bool { terms.isEmpty && rules.isEmpty }
}

// MARK: - Editing

extension PersonalDictionary {
    public mutating func addTerm(_ term: String) throws(DictionaryError) {
        terms.append(try checkedTerm(term, replacing: nil))
    }

    public mutating func updateTerm(at index: Int, to term: String) throws(DictionaryError) {
        terms[index] = try checkedTerm(term, replacing: index)
    }

    public mutating func addRule(_ rule: ReplacementRule) throws(DictionaryError) {
        rules.append(try checkedRule(rule, replacing: nil))
    }

    public mutating func updateRule(at index: Int, to rule: ReplacementRule) throws(DictionaryError) {
        rules[index] = try checkedRule(rule, replacing: index)
    }

    /// The entries of `other` that this dictionary does not have yet. Nothing changes until `apply(_:)`.
    public func importPreview(of other: Self) -> DictionaryImport {
        merging(terms: other.terms, rules: other.rules).added
    }

    /// Adds the preview's entries that are still new. An entry added since the preview was made wins, so a stale
    /// preview never adds a duplicate.
    public mutating func apply(_ preview: DictionaryImport) {
        self = merging(terms: preview.terms, rules: preview.rules).merged
    }

    private func merging(terms: [String], rules: [ReplacementRule]) -> (merged: Self, added: DictionaryImport) {
        var merged = self
        var added = DictionaryImport()
        for term in terms {
            do {
                try merged.addTerm(term)
                added.terms.append(merged.terms[merged.terms.count - 1])
            } catch .duplicate {
                added.duplicateCount += 1
            } catch {
                continue  // A blank entry has nothing to import.
            }
        }
        for rule in rules {
            do {
                try merged.addRule(rule)
                added.rules.append(merged.rules[merged.rules.count - 1])
            } catch .duplicate {
                added.duplicateCount += 1
            } catch {
                continue  // A blank entry has nothing to import.
            }
        }
        return (merged, added)
    }

    private func checkedTerm(_ term: String, replacing index: Int?) throws(DictionaryError) -> String {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        let isDuplicate = terms.indices.contains { other in
            other != index && terms[other].caseInsensitiveCompare(trimmed) == .orderedSame
        }
        guard !isDuplicate else { throw .duplicate }
        return trimmed
    }

    private func checkedRule(_ rule: ReplacementRule, replacing index: Int?) throws(DictionaryError) -> ReplacementRule
    {
        var checked = rule
        checked.find = rule.find.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !checked.find.isEmpty else { throw .empty }
        let isDuplicate = rules.indices.contains { other in other != index && rules[other].overlaps(checked) }
        guard !isDuplicate else { throw .duplicate }
        return checked
    }
}
