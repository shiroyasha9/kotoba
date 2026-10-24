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

/// The owner's words and replacements, the switch that learns them from edits, and the suggestions it learned; the
/// stars and the hint limit are in "Advanced…" (docs/research/ui-redesign.md, "Page map").
private struct DictionaryPane: View {
    @Bindable var model: DictionaryModel
    @State private var search = ""
    /// The sheet: nil row adds a new entry.
    @State private var editing: Editing?
    @State private var isAdvancedShown = false

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
            }
            if !model.suggestions.isEmpty {
                SuggestionsSection(model: model)
            }
            words
        }
        .wisprImportAlert(model)
        .sheet(item: $editing) { editing in
            EntryEditor(draft: editing.draft, isNew: editing.row == nil) { draft throws(DictionaryError) in
                try model.save(draft, replacing: editing.row)
                // A new word shows in the list, whatever the search was.
                if editing.row == nil { search = "" }
            }
        }
        .sheet(isPresented: $isAdvancedShown) {
            DictionaryAdvanced(model: model)
        }
    }

    private var words: some View {
        Section {
            EditableList(
                rows: visibleRows, emptyText: emptyText, addTitle: "Add Word", addHelp: "Add a word or a replacement",
                removeTitle: "Delete", remove: model.delete, add: add, edit: edit
            ) { row in
                DictionaryRowView(draft: model.draft(for: row))
            } accessory: {
                if isReading {
                    ProgressView().controlSize(.small)
                }
                if model.isWisprInstalled {
                    Button("Import from Wispr Flow…") { model.previewWisprImport() }
                        .buttonStyle(.automatic)
                        .disabled(model.wisprImport != nil)
                }
            }
        } header: {
            // The field names the list ("Search words"), so the group needs no other header. It stays while it
            // filters, even when no word is left, so a search never hides words with no field to clear it.
            if model.rows.isEmpty && search.isEmpty {
                Text("Words")
            } else {
                PageSearchField(text: $search, prompt: "Search words")
            }
        } footer: {
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    // An empty dictionary says so in the list; "0 words" adds nothing.
                    if !model.rows.isEmpty {
                        Text(summary)
                    }
                    Spacer()
                    // Alone at the trailing edge under the last group, as Activity's and Battery's "Options…". Its
                    // stars need words.
                    if !model.rows.isEmpty {
                        Button("Advanced…") { isAdvancedShown = true }
                    }
                }
                if let saveError = model.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
        }
        .task { await model.checkWisprInstalled() }
    }

    private var emptyText: String {
        if !search.isEmpty { return "No words match “\(search)”." }
        let wispr = model.isWisprInstalled ? " Or import them from Wispr Flow." : ""
        return "No words yet. Add names and terms kotoba spells wrong, and it spells them right next time.\(wispr)"
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
        return "\(words), \(replacements)."
    }

    private var isReading: Bool { model.wisprImport?.isReading == true }

    private func add() {
        editing = Editing(row: nil, draft: EntryDraft())
    }

    private func edit(_ row: DictionaryModel.Row) {
        editing = Editing(row: row, draft: model.draft(for: row))
    }
}

/// The Dictionary page's "Advanced…": the hint limit, and the star that always sends a word to the speech model.
struct DictionaryAdvanced: View {
    let model: DictionaryModel

    /// The rows that send a hint, then the ones too long to send. A replacement that deletes its word sends none and has
    /// no row.
    private var rows: [DictionaryModel.Row] {
        let sent = model.rows.filter { model.keyterm(for: $0) != nil }
        let tooLong = model.rows.filter { row in
            let draft = model.draft(for: row)
            return model.keyterm(for: row) == nil && !(draft.isReplacing && draft.replacement.isEmpty)
        }
        return sent + tooLong
    }

    /// The hint a row sends, or the text too long to send.
    private func hint(of row: DictionaryModel.Row) -> String {
        let draft = model.draft(for: row)
        return model.keyterm(for: row) ?? (draft.isReplacing ? draft.replacement : draft.word)
    }

    var body: some View {
        PageSheet(title: "Advanced Dictionary Settings") {
            Section {
                // On top, not in the footer: the limit is why the stars exist, and a long list scrolls a footer away.
                Text(hints)
                ForEach(rows) { row in
                    StarRow(
                        word: hint(of: row),
                        sendsKeyterm: model.keyterm(for: row) != nil, isPinned: model.isPinned(row),
                        isNotSent: model.isNotSent(row)
                    ) { model.setPinned(row, $0) }
                }
            } header: {
                Text("Hints for the Speech Model")
            }
        }
    }

    private var hints: String {
        let limit = PersonalDictionary.maxKeyterms
        return model.dictionary.keyterms.count <= limit
            ? "kotoba sends up to \(limit) of your words as hints with each dictation. Star a word to send it first."
            : "kotoba sends \(limit) of your words as hints with each dictation: starred words first, then the words "
                + "you use most."
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
                ? ", including \(StatusText.counted(learnedCount, "correction")) Wispr learned from your edits" : ""
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
            MainWindow.sheetSnapshot(named: "settings-dictionary-advanced") {
                DictionaryAdvanced(model: sampleOverCapModel)
            },
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
