import Foundation
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
    /// A save that failed, shown under the list until the next save works.
    private(set) var saveError: String?
    var wisprImport: WisprImport?

    @ObservationIgnored private let store: DictionaryStore
    @ObservationIgnored private let onChange: @MainActor (PersonalDictionary) async -> Void
    /// Each edit goes to the pipeline and then to disk, one edit after another, so both end with the last edit.
    @ObservationIgnored private var saving: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?

    init(
        dictionary: PersonalDictionary, store: DictionaryStore,
        onChange: @escaping @MainActor (PersonalDictionary) async -> Void
    ) {
        self.dictionary = dictionary
        self.store = store
        self.onChange = onChange
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
                guard let contents = try await WisprFlowImport.readInstalled() else {
                    wisprImport = .notFound
                    return
                }
                wisprImport = .preview(dictionary.importPreview(of: contents.dictionary), contents)
            } catch WisprFlowImport.ImportError.changedWhileCloning {
                wisprImport = .failed("Wispr Flow kept writing to its database. Try again in a moment.")
            } catch {
                Log.dictionary.error("Cannot read Wispr Flow's dictionary: \(error)")
                wisprImport = .failed(String(describing: error))
            }
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

    private func commit(_ updated: PersonalDictionary) {
        guard updated != dictionary else { return }
        dictionary = updated
        let previous = saving
        saving = Task { [store, onChange] in
            await previous?.value
            await onChange(updated)
            do {
                try await store.save(updated)
                saveError = nil
            } catch {
                Log.dictionary.error("Cannot save the dictionary: \(error)")
                saveError = "The dictionary could not be saved: \(error)"
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
