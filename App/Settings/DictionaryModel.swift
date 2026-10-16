import AppKit
import KotobaCore
import KotobaStorage
import Observation

/// The owner's dictionary for the app's lifetime: edits save to the store and go to the pipeline for the next
/// dictation.
@MainActor
@Observable
final class DictionaryModel {
    /// One list row: a word, or a word with its replacement, by position in the dictionary.
    enum Row: Hashable {
        case term(Int)
        case rule(Int)
    }

    enum WisprImport {
        case reading
        /// What the import adds, and Wispr's own counts for the message.
        case preview(DictionaryImport, WisprFlowImport.Contents)
        case notFound
        case failed(String)
    }

    private(set) var dictionary: PersonalDictionary
    /// Pending suggestions learned from corrections, the most seen first. The menu shows their count.
    private(set) var suggestions: [DictionarySuggestion] = []
    /// Pairs the owner dismissed; a correction detector skips them.
    private(set) var dismissedPairs: Set<SuggestionPair> = []
    /// A save that failed, shown under the list until the next save works.
    private(set) var saveError: String?
    var wisprImport: WisprImport?
    /// False hides "Import from Wispr Flow…": Wispr Flow's folder is not on this Mac.
    var isWisprInstalled = false

    @ObservationIgnored private let store: DictionaryStore
    @ObservationIgnored private let onChange: @MainActor (PersonalDictionary) async -> Void
    /// After each write to the store, so a reader of its learned words (Insights) reads again only then.
    @ObservationIgnored private let onSaved: @MainActor () -> Void
    /// Each edit goes to the pipeline and then to disk, one edit after another, so both end with the last edit.
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?

    /// `suggestions` given (snapshots) skips reading them from the store.
    init(
        dictionary: PersonalDictionary, store: DictionaryStore, suggestions: [DictionarySuggestion]? = nil,
        onSaved: @escaping @MainActor () -> Void = {}, onChange: @escaping @MainActor (PersonalDictionary) async -> Void
    ) {
        self.dictionary = dictionary
        self.store = store
        self.onChange = onChange
        self.onSaved = onSaved
        if let suggestions {
            self.suggestions = suggestions
        } else {
            saving = Task { await refreshSuggestions() }
        }
    }

    /// The English spell checker's answer for one word, for "a common heard word gives a word only, never a
    /// replacement". A word the user taught the spell checker (Learned Words: "Vercel", "embra") is not a common
    /// word; counting it as known made real corrections weak (learning's evaluation on the Wispr pairs).
    static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        let misspelled = checker.checkSpelling(
            of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return misspelled.location == NSNotFound && !checker.hasLearnedWord(word)
    }

    var rows: [Row] {
        dictionary.terms.indices.map(Row.term) + dictionary.rules.indices.map(Row.rule)
    }

    func draft(for row: Row) -> EntryDraft {
        switch row {
        case .term(let index): EntryDraft(word: dictionary.terms[index])
        case .rule(let index): EntryDraft(rule: dictionary.rules[index])
        }
    }

    /// Adds `draft`, or puts it in place of `row`. A word that turns into a replacement moves to the end.
    func save(_ draft: EntryDraft, replacing row: Row?) throws(DictionaryError) {
        var updated = dictionary
        switch (row, draft.rule) {
        case (.term(let index)?, nil): try updated.updateTerm(at: index, to: draft.word)
        case (.rule(let index)?, let rule?): try updated.updateRule(at: index, to: rule)
        case (let row, let rule):
            if let row {
                Self.remove([row], from: &updated)
            }
            if let rule {
                try updated.addRule(rule)
            } else {
                try updated.addTerm(draft.word)
            }
        }
        commit(updated)
    }

    func delete(_ rows: Set<Row>) {
        var updated = dictionary
        Self.remove(rows, from: &updated)
        commit(updated)
    }

    private static func remove(_ rows: Set<Row>, from dictionary: inout PersonalDictionary) {
        var terms = RangeSet<Int>()
        var rules = RangeSet<Int>()
        for row in rows {
            switch row {
            case .term(let index): terms.insert(index, within: dictionary.terms)
            case .rule(let index): rules.insert(index, within: dictionary.rules)
            }
        }
        dictionary.terms.removeSubranges(terms)
        dictionary.rules.removeSubranges(rules)
    }

    /// Finds and reads Wispr Flow's dictionary, then shows what an import would add.
    func previewWisprImport() {
        wisprImport = .reading
        reading = Task {
            do {
                guard let read = try await WisprFlowImport.readInstalled() else {
                    wisprImport = .notFound
                    return
                }
                let contents = read.keepingRules(isKnownWord: Self.isKnownWord)
                wisprImport = .preview(dictionary.importPreview(of: contents.dictionary), contents)
            } catch WisprFlowImport.ImportError.changedWhileCloning {
                wisprImport = .failed("Wispr Flow kept writing to its dictionary. Try again in a moment.")
            } catch {
                Log.dictionary.error("Cannot read Wispr Flow's dictionary: \(error)")
                wisprImport = .failed("Couldn’t read Wispr Flow’s dictionary. Try again.")
            }
        }
    }

    /// Checks for Wispr Flow's folder when the pane opens.
    func checkWisprInstalled() async {
        isWisprInstalled = await WisprFlowImport.isInstalled()
    }

    // MARK: Suggestions

    /// Counts corrections a detector found and the owner left unchecked: a weak one shows as a suggestion once seen
    /// twice. A pair the owner added or dismissed does not come back.
    func record(_ corrections: [DetectedCorrection]) {
        enqueue { [store] in
            for correction in corrections where !self.dictionary.contains(correction.candidate) {
                do {
                    _ = try await store.record(correction.candidate, isStrong: correction.isStrong, at: .now)
                } catch {
                    Log.dictionary.error("Cannot record a suggestion: \(error)")
                }
            }
        }
    }

    /// Corrections the owner saw and unchecked: never suggested again.
    func dismiss(_ candidates: [SuggestionCandidate]) {
        enqueue { [store] in
            do {
                try await store.dismiss(candidates, at: .now)
            } catch {
                Log.dictionary.error("Cannot dismiss corrections: \(error)")
            }
        }
    }

    /// Adds corrections the owner checked ("Fix Last Dictation…") and stores them as added, so a dismissal of the
    /// same pair is lifted and they are never suggested again.
    func add(_ candidates: [SuggestionCandidate]) {
        commit(candidates.reduce(dictionary) { $0.adding($1) }, recordingAdded: candidates)
    }

    /// The entries one auto-learn added: the pill's Undo takes out exactly these.
    struct Learned: Equatable {
        /// The corrected words that added something, for the pill.
        var words: [String]
        var terms: [String]
        var rules: [ReplacementRule]
    }

    /// Adds corrections kotoba read back after a paste, stored as added like a checked fix. Nil when they add
    /// nothing new.
    func learn(_ candidates: [SuggestionCandidate]) -> Learned? {
        let before = dictionary
        let new = candidates.filter { !before.contains($0) }
        guard !new.isEmpty else { return nil }
        add(new)
        return Learned(
            words: new.map(\.corrected), terms: dictionary.terms.filter { !before.terms.contains($0) },
            rules: dictionary.rules.filter { !before.rules.contains($0) })
    }

    /// The pill's Undo. The save then marks the suggestion dismissed, so the word is not learned again.
    func undoLearned(_ learned: Learned) {
        var updated = dictionary
        updated.terms.removeAll { learned.terms.contains($0) }
        updated.rules.removeAll { learned.rules.contains($0) }
        commit(updated)
    }

    func addSuggestions(_ ids: Set<DictionarySuggestion.ID>) {
        let chosen = suggestions.filter { ids.contains($0.id) }
        suggestions.removeAll { ids.contains($0.id) }
        commit(chosen.reduce(dictionary) { $0.adding($1.candidate) }, markingAdded: chosen.map(\.id))
    }

    func dismissSuggestions(_ ids: Set<DictionarySuggestion.ID>) {
        suggestions.removeAll { ids.contains($0.id) }
        enqueue { [store] in
            do {
                try await store.dismiss(Array(ids))
            } catch {
                Log.dictionary.error("Cannot dismiss suggestions: \(error)")
            }
        }
    }

    /// Runs `work` after the edits before it, then refreshes the suggestions: the store, the pipeline and the list end
    /// with the last edit.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = saving
        saving = Task {
            await previous?.value
            await work()
            onSaved()
            await refreshSuggestions()
        }
    }

    private func refreshSuggestions() async {
        do {
            suggestions = try await store.pendingSuggestions(at: .now)
            dismissedPairs = try await store.dismissedPairs()
        } catch {
            Log.dictionary.error("Cannot read suggestions: \(error)")
        }
    }

    /// Imports against the dictionary as it is now, not as it was when the preview was shown.
    func applyWisprImport() {
        guard case .preview(_, let contents) = wisprImport else { return }
        wisprImport = nil
        var updated = dictionary
        updated.apply(updated.importPreview(of: contents.dictionary))
        commit(updated)
    }

    /// `ids`: suggestions this edit adds, and `candidates`: checked corrections, both stored as added in the same
    /// save. A deleted entry that came from a suggestion makes it dismissed in the store.
    private func commit(
        _ updated: PersonalDictionary,
        markingAdded ids: [DictionarySuggestion.ID] = [],
        recordingAdded candidates: [SuggestionCandidate] = []
    ) {
        guard updated != dictionary || !ids.isEmpty || !candidates.isEmpty else { return }
        dictionary = updated
        enqueue { [store, onChange] in
            await onChange(updated)
            do {
                try await store.save(updated, markingAdded: ids, recordingAdded: candidates)
                self.saveError = nil
            } catch {
                Log.dictionary.error("Cannot save the dictionary: \(error)")
                self.saveError = "Couldn’t save your dictionary. Make the change again."
            }
        }
    }
}

/// The fields of the add and edit sheet.
struct EntryDraft {
    var word = ""
    var isReplacing = false
    var replacement = ""
    var isWholeWord = true
    var isCaseSensitive = false

    init(word: String = "") {
        self.word = word
    }

    init(rule: ReplacementRule) {
        word = rule.find
        isReplacing = true
        replacement = rule.replacement
        isWholeWord = rule.isWholeWord
        isCaseSensitive = rule.isCaseSensitive
    }

    /// Nil when the draft is a plain word.
    var rule: ReplacementRule? {
        guard isReplacing else { return nil }
        return ReplacementRule(
            find: word, replacement: replacement, isWholeWord: isWholeWord, isCaseSensitive: isCaseSensitive)
    }
}
