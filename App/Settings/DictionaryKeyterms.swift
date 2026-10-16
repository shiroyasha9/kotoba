import KotobaCore
import KotobaStorage

/// The keyterms the Dictionary pane shows per row: the star (always sent) and whether the last dictation sent it, and
/// the use counts each delivered dictation adds (`DictationPipeline.termReports`).
extension DictionaryModel {
    /// The keyterm a row sends: its word, or the spelling its rule writes. Nil when it sends none: too long, or a rule
    /// that deletes the word.
    func keyterm(for row: Row) -> String? {
        switch row {
        case .term(let index): PersonalDictionary.keyterm(dictionary.terms[index])
        case .rule(let index): PersonalDictionary.keyterm(dictionary.rules[index].replacement)
        }
    }

    func isPinned(_ row: Row) -> Bool {
        keyterm(for: row).map { termUse[TermUse.key(for: $0)]?.isPinned == true } ?? false
    }

    func isNotSent(_ row: Row) -> Bool {
        keyterm(for: row).map { notSent.contains(TermUse.key(for: $0)) } ?? false
    }

    /// The row's star: a pinned keyterm is always sent.
    func setPinned(_ row: Row, _ isPinned: Bool) {
        guard let term = keyterm(for: row) else { return }
        termUse[TermUse.key(for: term), default: TermUse()].isPinned = isPinned
        chain { [store] in
            do {
                try await store.setPinned(term, isPinned)
            } catch {
                Log.dictionary.error("Cannot save a pin: \(error)")
            }
            await self.refreshTermUse()
        }
    }

    /// A dictation got its text: its hits count, and the rows show what it did not send.
    func delivered(_ report: TermReport) {
        let notSent = dictionary.keytermKeys.subtracting(report.sent.map(TermUse.key(for:)))
        // Each set redraws the rows that read it, so an unchanged mark (every dictation under the cap) is not set.
        if notSent != self.notSent { self.notSent = notSent }
        guard !report.hits.isEmpty else { return }
        chain { [store] in
            do {
                try await store.recordUse(of: report.hits, at: report.at)
            } catch {
                Log.dictionary.error("Cannot count the dictionary words used: \(error)")
            }
            await self.refreshTermUse()
        }
    }

    func refreshTermUse() async {
        do {
            termUse = try await store.termUse()
            await onTermUse(termUse)
        } catch {
            Log.dictionary.error("Cannot read the dictionary word use: \(error)")
        }
    }
}
