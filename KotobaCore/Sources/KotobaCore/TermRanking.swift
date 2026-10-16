import Foundation

/// How the owner uses one keyterm, by `TermUse.key(for:)`. The App keeps it in the dictionary file (`term_use`), apart
/// from the dictionary rows that each save rewrites.
public struct TermUse: Sendable, Equatable {
    /// Delivered dictations whose text has the term (`TermHits`).
    public var uses: Int
    public var lastUsedAt: Date?
    /// Nil for a term from before kotoba kept the date (0.1.0).
    public var addedAt: Date?
    /// The owner starred the term in the Dictionary pane: it is always sent.
    public var isPinned: Bool

    public init(uses: Int = 0, lastUsedAt: Date? = nil, addedAt: Date? = nil, isPinned: Bool = false) {
        self.uses = uses
        self.lastUsedAt = lastUsedAt
        self.addedAt = addedAt
        self.isPinned = isPinned
    }

    /// Trimmed and lowercased, the key `PersonalDictionary.keyterms` drops duplicates by: "Vercel" and "vercel" share
    /// one use.
    public static func key(for term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Picks the keyterms one request sends. At or under the limit every keyterm goes, in list order. Over it: pinned
/// terms, then terms by use score, then terms added in the last 14 days (at most 10, newest first, so a bulk import
/// cannot push out the terms in use), then list order. Ties keep list order. The termcap bench (2026-10-16) measured
/// this rule against stored order and a random pick on kotoba-bench-v1.
enum TermRanking {
    static let day: TimeInterval = 24 * 60 * 60
    static let halfLifeDays = 30.0
    static let recentDays = 14.0
    static let maxRecent = 10

    /// `uses × 0.5^(days since the last use / 30)`: a term used often a year ago falls below one used last week.
    static func score(_ use: TermUse, at now: Date) -> Double {
        guard use.uses > 0, let lastUsedAt = use.lastUsedAt else { return 0 }
        let days = max(0, now.timeIntervalSince(lastUsedAt)) / day
        return Double(use.uses) * pow(0.5, days / halfLifeDays)
    }

    static func keyterms(
        of dictionary: PersonalDictionary, use: [String: TermUse], limit: Int = PersonalDictionary.maxKeyterms,
        at now: Date
    ) -> [String] {
        let candidates = dictionary.keyterms
        guard candidates.count > limit else { return candidates }
        let entries = candidates.map { use[TermUse.key(for: $0)] ?? TermUse() }

        var picked: [Int] = []
        var isPicked = [Bool](repeating: false, count: candidates.count)
        func take(_ indices: some Sequence<Int>, upTo count: Int = .max) {
            var taken = 0
            for index in indices where !isPicked[index] {
                guard picked.count < limit, taken < count else { return }
                isPicked[index] = true
                picked.append(index)
                taken += 1
            }
        }

        take(candidates.indices.filter { entries[$0].isPinned })
        let scores = entries.map { score($0, at: now) }
        take(candidates.indices.filter { scores[$0] > 0 }.sorted { (scores[$0], $1) > (scores[$1], $0) })
        let recentSince = now - recentDays * day
        let recent = candidates.indices.compactMap { index in
            entries[index].addedAt.flatMap { $0 >= recentSince ? (index, $0) : nil }
        }
        take(recent.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.map(\.0), upTo: maxRecent)
        take(candidates.indices)
        return picked.map { candidates[$0] }
    }
}
