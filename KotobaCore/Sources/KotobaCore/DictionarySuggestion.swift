import Foundation

/// A word kotoba learned from the owner's corrections. It waits as a suggestion until the owner adds or dismisses it;
/// nothing is added on its own (docs/spec.md, Polish and learning).
public struct DictionarySuggestion: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable {
        case pending
        case added
        /// Dismissed by the owner, or added and later deleted from the dictionary. The pair never returns.
        case dismissed
    }

    public var id: UUID
    public var candidate: SuggestionCandidate
    /// How many times the correction was seen.
    public var evidence: Int
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var status: Status

    public init(
        id: UUID = UUID(),
        candidate: SuggestionCandidate,
        evidence: Int = 1,
        firstSeenAt: Date,
        lastSeenAt: Date,
        status: Status = .pending
    ) {
        self.id = id
        self.candidate = candidate
        self.evidence = evidence
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.status = status
    }
}

/// One correction a detector found: kotoba wrote `heard`, the owner meant `corrected`.
public struct SuggestionCandidate: Sendable, Hashable {
    public enum Proposal: String, Sendable {
        /// Add `corrected` as a word only.
        case term
        /// Add `corrected` as a word and replace `heard` with it.
        case termAndRule
    }

    public enum Origin: String, Sendable {
        /// "Fix Last Dictation…".
        case fix
        /// An edit kotoba read back after the paste.
        case edit
        case history
        case wispr
    }

    public var heard: String
    public var corrected: String
    public var proposes: Proposal
    public var origin: Origin
    public var appBundleID: String?

    public init(heard: String, corrected: String, proposes: Proposal, origin: Origin, appBundleID: String? = nil) {
        self.heard = heard
        self.corrected = corrected
        self.proposes = proposes
        self.origin = origin
        self.appBundleID = appBundleID
    }

    /// The suggestion's identity: the same words in any case are the same suggestion.
    public var pair: SuggestionPair {
        SuggestionPair(heard: heard, corrected: corrected)
    }

    /// A rule only when `heard` is not made of common words: replacing a real word everywhere would break other
    /// sentences (`ember` -> `embra` gives the word `embra` only). `isKnownWord` is the spell checker's answer
    /// for one word; the App passes NSSpellChecker.
    public static func proposal(heard: String, isKnownWord: (String) -> Bool) -> Proposal {
        let words = heard.split { !$0.isLetter && $0 != "'" }
        return !words.isEmpty && words.allSatisfy { isKnownWord(String($0)) } ? .term : .termAndRule
    }
}

public struct SuggestionPair: Sendable, Hashable {
    public var heard: String
    public var corrected: String

    public init(heard: String, corrected: String) {
        self.heard = heard.lowercased()
        self.corrected = corrected.lowercased()
    }
}

extension PersonalDictionary {
    /// The word, and the rule when the candidate proposes one: whole words, any case, like Wispr Flow's replacements.
    public func adding(_ candidate: SuggestionCandidate) -> Self {
        var entries = PersonalDictionary(terms: [candidate.corrected])
        if candidate.proposes == .termAndRule {
            entries.rules = [ReplacementRule(find: candidate.heard, replacement: candidate.corrected)]
        }
        var updated = self
        updated.apply(importPreview(of: entries))
        return updated
    }

    /// True when the candidate adds nothing: its word is here, and its rule is here or another rule already covers
    /// the heard text.
    public func contains(_ candidate: SuggestionCandidate) -> Bool {
        adding(candidate) == self
    }
}
