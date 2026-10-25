import AppKit
import KotobaCore
import KotobaStorage
import SwiftUI

extension Pane {
    static func dictionary(_ model: DictionaryModel) -> Self {
        Pane(id: .dictionary, badge: { model.suggestions.count }, content: { AnyView(DictionaryPane(model: model)) })
    }
}

extension DictionaryModel.Row: Identifiable {
    var id: Self { self }
}

/// The owner's words and replacements, each with its star, the switch that learns them from edits, and the suggestions
/// it learned; the hint limit is in the list's footer (owner QA 1, Q13: starring needs no sheet).
private struct DictionaryPane: View {
    @Bindable var model: DictionaryModel
    @State private var search = ""
    /// The sheet: nil row adds a new entry.
    @State private var editing: Editing?

    private struct Editing: Identifiable {
        let id = UUID()
        let row: DictionaryModel.Row?
        let draft: EntryDraft
    }

    var body: some View {
        PageForm {
            Section {
                PageHeader(
                    page: .dictionary,
                    summary: "Names and terms kotoba spells your way, and words it replaces with others.")
            }
            Section {
                LearnFromEditsToggle()
            } footer: {
                // Said here, where it is turned on, not in onboarding (docs/research/copywriting.md, Onboarding steps).
                Text("kotoba reads only the text field it pasted into. It never reads a password field or your screen.")
            }
            // Not while a search runs: the matches come first, as in 0.4.
            if !model.suggestions.isEmpty && search.isEmpty {
                SuggestionsSection(model: model)
            }
            words
        }
        // In the window toolbar, always in view however long the list is, as Passwords' search and + (owner QA 1, Q12).
        .pageSearch(text: $search, prompt: "Search words")
        .pageToolbar {
            if model.isWisprInstalled {
                Button("Import from Wispr Flow…", systemImage: "square.and.arrow.down") { model.previewWisprImport() }
                    .disabled(model.wisprImport != nil)
            }
            Button("Add Word…", systemImage: "plus", action: add)
                .help("Add a word or a replacement")
        }
        .task { await model.checkWisprInstalled() }
        .wisprImportAlert(model)
        .sheet(item: $editing) { editing in
            EntryEditor(draft: editing.draft, isNew: editing.row == nil) { draft throws(DictionaryError) in
                try model.save(draft, replacing: editing.row)
                // A new word shows in the list, whatever the search was.
                if editing.row == nil { search = "" }
            }
        }
    }

    private var words: some View {
        Section {
            EditableList(
                rows: visibleRows, emptyText: emptyText, removeTitle: "Delete", remove: model.delete, edit: edit
            ) { row in
                DictionaryRowView(
                    draft: model.draft(for: row), sendsKeyterm: model.keyterm(for: row) != nil,
                    isPinned: model.isPinned(row), isNotSent: model.isNotSent(row)
                ) { model.setPinned(row, $0) }
            }
        } header: {
            Text("Words")
        } footer: {
            VStack(alignment: .leading) {
                // An empty dictionary says so in the list; "0 words" adds nothing.
                if !model.rows.isEmpty {
                    Text(summary)
                }
                if let saveError = model.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
        }
    }

    private var emptyText: String {
        if !search.isEmpty { return "No words match “\(search)”." }
        let wispr = model.isWisprInstalled ? " Or import them from Wispr Flow." : ""
        return "No words yet. Add the names and terms kotoba should know.\(wispr)"
    }

    private var visibleRows: [DictionaryModel.Row] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return model.rows }
        return model.rows.filter { row in
            let draft = model.draft(for: row)
            return draft.word.localizedCaseInsensitiveContains(query)
                || (draft.isReplacing && draft.replacement.localizedCaseInsensitiveContains(query))
        }
    }

    private var summary: String {
        let dictionary = model.dictionary
        let words = StatusText.counted(dictionary.terms.count, "word")
        let replacements = StatusText.counted(dictionary.rules.count, "replacement")
        let limit = PersonalDictionary.maxKeyterms
        let hints =
            dictionary.keyterms.count <= limit
            ? "kotoba sends up to \(limit) words as hints with each dictation; star a word to send it first."
            : "kotoba sends \(limit) words as hints with each dictation: starred words first, then the words you use "
                + "most."
        return "\(words), \(replacements). " + hints
    }

    private func add() {
        editing = Editing(row: nil, draft: EntryDraft())
    }

    private func edit(_ row: DictionaryModel.Row) {
        editing = Editing(row: row, draft: model.draft(for: row))
    }
}

extension View {
    /// The Wispr Flow import's preview, or why there is none, as an alert until the owner answers. Settings >
    /// Dictionary and onboarding show the same alert; onboarding's dictionary is nil until it is read at launch.
    /// `imported` gets what the import added, or the empty preview when Wispr Flow had nothing new.
    func wisprImportAlert(
        _ model: DictionaryModel?, imported: @escaping @MainActor (DictionaryImport) -> Void = { _ in }
    ) -> some View {
        let isShown = Binding(get: { model?.wisprImport?.isReading == false }, set: { _ in })
        return alert(
            DictionaryPane.importTitle(model?.wisprImport), isPresented: isShown, presenting: model?.wisprImport
        ) { state in
            // Each button clears the state itself, so the binding never has to.
            if case .preview(let preview, _) = state, !preview.isEmpty {
                Button("Cancel", role: .cancel) { model?.wisprImport = nil }
                Button("Import") {
                    if let added = model?.applyWisprImport() {
                        imported(added)
                    }
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("OK") {
                    model?.wisprImport = nil
                    if case .preview(let preview, _) = state {
                        imported(preview)
                    }
                }
            }
        } message: { state in
            Text(DictionaryPane.importMessage(state))
        }
    }
}

extension DictionaryImport {
    /// "3 words and 1 replacement", with a zero count left out (CODING_STANDARDS, user-facing text 10). The import
    /// alert and onboarding's Wispr Flow step say it.
    var countsText: String {
        let words = terms.isEmpty ? nil : StatusText.counted(terms.count, "word")
        let replacements = rules.isEmpty ? nil : StatusText.counted(rules.count, "replacement")
        return [words, replacements].compactMap { $0 }.joined(separator: " and ")
    }
}

extension DictionaryPane {
    static func importTitle(_ state: DictionaryModel.WisprImport?) -> String {
        switch state {
        case .preview(let preview, _) where !preview.isEmpty: "Import from Wispr Flow?"
        case .preview: "Nothing New in Wispr Flow"
        case .notFound: "Wispr Flow Not Found"
        case .failed: "Couldn’t Read Wispr Flow’s Dictionary"
        case .reading, nil: ""
        }
    }

    static func importMessage(_ state: DictionaryModel.WisprImport) -> String {
        switch state {
        case .preview(let preview, let contents):
            // Only the learned corrections the import adds; the others are already here. The dictionary stores a rule's
            // find text trimmed.
            let learnedFinds = Set(contents.learned.map { $0.find.trimmingCharacters(in: .whitespacesAndNewlines) })
            let learnedCount = preview.rules.count { learnedFinds.contains($0.find) }
            let learned =
                learnedCount > 0
                ? ", including \(StatusText.counted(learnedCount, "correction")) Wispr Flow learned from your edits"
                : ""
            var lines = [
                preview.isEmpty
                    ? "Every word in Wispr Flow’s dictionary is already in kotoba."
                    : "Adds \(preview.countsText)\(learned)."
            ]
            if preview.duplicateCount > 0 {
                lines.append("Already in your dictionary: \(StatusText.counted(preview.duplicateCount, "entry")).")
            }
            if contents.snippets > 0 {
                lines.append("Skips \(StatusText.counted(contents.snippets, "snippet")).")
            }
            return lines.joined(separator: " ")
        case .notFound:
            return "Wispr Flow is not on this Mac, or it has no dictionary yet."
        case .failed(let reason):
            return reason
        case .reading:
            return ""
        }
    }
}

// MARK: - Snapshots

@MainActor
extension Pane {
    static func dictionarySnapshots() -> [Snapshot] {
        let sample = sampleDictionary
        let (incoming, contents) = sampleWisprImport
        return [
            MainWindow.snapshot(of: .dictionary(sampleModel(sample)), named: "settings-dictionary", height: 1_000),
            MainWindow.snapshot(
                of: .dictionary(sampleModel(sample, suggestions: sampleSuggestions)),
                named: "settings-dictionary-suggestions", height: 1_200),
            MainWindow.snapshot(
                of: .dictionary(sampleOverCapModel), named: "settings-dictionary-over-cap", height: 1_000),
            MainWindow.snapshot(
                of: .dictionary(sampleModel(PersonalDictionary())), named: "settings-dictionary-empty"),
            importAlert(.preview(sample.importPreview(of: incoming), contents), named: "settings-dictionary-import"),
            importAlert(.notFound, named: "settings-dictionary-import-not-found"),
            MainWindow.sheetSnapshot(named: "settings-dictionary-editor") {
                let rule = ReplacementRule(find: "cloud code", replacement: "Claude Code")
                return EntryEditor(draft: EntryDraft(rule: rule), isNew: false) { _ throws(DictionaryError) in }
            },
        ]
    }

    /// The import alert as AppKit draws it, with the pane's words: SwiftUI's `.alert` is a sheet on the window, which
    /// an offscreen run cannot show.
    private static func importAlert(_ state: DictionaryModel.WisprImport, named name: String) -> Snapshot {
        Snapshot(name: name) {
            let alert = NSAlert()
            alert.messageText = DictionaryPane.importTitle(state)
            alert.informativeText = DictionaryPane.importMessage(state)
            if case .preview(let preview, _) = state, !preview.isEmpty {
                alert.addButton(withTitle: "Import")
                alert.addButton(withTitle: "Cancel")
            } else {
                alert.addButton(withTitle: "OK")
            }
            alert.layout()
            return alert.window.contentView ?? NSView()
        }
    }
}
