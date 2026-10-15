import KotobaCore
import KotobaStorage
import SwiftUI

extension SettingsPane {
    static func dictionary(_ model: DictionaryModel) -> Self {
        SettingsPane(id: .dictionary, title: "Dictionary", systemImage: "character.book.closed") {
            AnyView(DictionaryPane(model: model))
        }
    }
}

private struct DictionaryPane: View {
    @Bindable var model: DictionaryModel
    @State private var search = ""
    @State private var selection: Set<DictionaryModel.Row> = []
    /// The sheet: nil row adds a new entry.
    @State private var editing: Editing?

    private struct Editing: Identifiable {
        let id = UUID()
        let row: DictionaryModel.Row?
        let draft: EntryDraft
    }

    var body: some View {
        let rows = visibleRows
        VStack(spacing: 0) {
            List(selection: $selection) {
                if !model.suggestions.isEmpty, search.isEmpty {
                    SuggestionsSection(model: model)
                }
                Section {
                    ForEach(rows, id: \.self) { row in
                        DictionaryRowView(draft: model.draft(for: row))
                    }
                } header: {
                    if !model.suggestions.isEmpty, search.isEmpty, !rows.isEmpty {
                        Text("Words and Replacements")
                    }
                }
            }
            .contextMenu(forSelectionType: DictionaryModel.Row.self) { rows in
                if rows.count == 1, let row = rows.first {
                    Button("Edit…") { edit(row) }
                }
                Button("Delete", role: .destructive) {
                    // Rows are positions, so a kept selection would point at other words after the delete.
                    model.delete(rows)
                    selection = []
                }
            } primaryAction: { rows in
                if rows.count == 1, let row = rows.first {
                    edit(row)
                }
            }
            .onDeleteCommand { delete() }
            .overlay {
                if model.rows.isEmpty, model.suggestions.isEmpty {
                    ContentUnavailableView(
                        "No Words Yet",
                        systemImage: "character.book.closed",
                        description: Text(
                            "Add names and terms the speech model should know, or fix a word it always gets wrong. "
                                + "You can also import from Wispr Flow.")
                    )
                } else if rows.isEmpty, !search.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            if let state = model.wisprImport, !isReading {
                Divider()
                importBanner(state)
            }
            Divider()
            footer
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search words")
        .sheet(item: $editing) { editing in
            EntryEditor(draft: editing.draft, isNew: editing.row == nil) { draft throws(DictionaryError) in
                try model.save(draft, replacing: editing.row)
                selection = []
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Button("Add", systemImage: "plus") { editing = Editing(row: nil, draft: EntryDraft()) }
                Button("Delete", systemImage: "minus") { delete() }
                    .disabled(selection.isEmpty)
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary)
                if let saveError = model.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            if isReading {
                ProgressView().controlSize(.small)
            }
            if model.isWisprInstalled {
                Button("Import from Wispr Flow…") { model.previewWisprImport() }
                    .disabled(model.wisprImport != nil)
            }
        }
        .padding(10)
        .task { await model.checkWisprInstalled() }
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
        let hints =
            dictionary.keyterms.count < PersonalDictionary.maxKeyterms
            ? "The speech model gets up to \(PersonalDictionary.maxKeyterms) words as hints."
            : "Only the first \(PersonalDictionary.maxKeyterms) words are sent as hints."
        let words = StatusText.counted(dictionary.terms.count, "word")
        let replacements = StatusText.counted(dictionary.rules.count, "replacement")
        return "\(words), \(replacements). " + hints
    }

    private var isReading: Bool {
        if case .reading = model.wisprImport { true } else { false }
    }

    /// The import preview, or why there is none, above the footer until the owner answers.
    private func importBanner(_ state: DictionaryModel.WisprImport) -> some View {
        // The buttons sit under the message, not beside it: next to buttons in an HStack, a wrapping Text is first
        // measured at almost no width, and its height then made the whole Settings window taller than the screen.
        HStack(alignment: .top, spacing: 10) {
            if case .preview = state {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2)
                    .foregroundStyle(.tint)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.multicolor)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(importTitle).font(.headline)
                Text(importMessage(state))
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    if case .preview(let preview, _) = state, !preview.isEmpty {
                        Button("Cancel") { model.wisprImport = nil }
                        Button("Import") { model.applyWisprImport() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("OK") { model.wisprImport = nil }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
    }

    private var importTitle: String {
        switch model.wisprImport {
        case .preview(let preview, _) where !preview.isEmpty: "Import from Wispr Flow?"
        case .preview: "Nothing New in Wispr Flow"
        case .notFound: "Wispr Flow Not Found"
        case .failed: "Couldn’t Read Wispr Flow’s Dictionary"
        case .reading, nil: ""
        }
    }

    private func importMessage(_ state: DictionaryModel.WisprImport) -> String {
        switch state {
        case .preview(let preview, let contents):
            var lines = [
                preview.isEmpty
                    ? "Every word in Wispr Flow’s dictionary is already here."
                    : "Adds \(StatusText.counted(preview.terms.count, "word")) and "
                        + "\(StatusText.counted(preview.rules.count, "replacement"))."
            ]
            if contents.learnedCorrections > 0 {
                lines.append(
                    "Includes \(StatusText.counted(contents.learnedCorrections, "learned correction")): "
                        + "what Wispr heard is replaced with the word you corrected it to.")
            }
            if preview.duplicateCount > 0 {
                lines.append(
                    "\(StatusText.counted(preview.duplicateCount, "entry")) already in your dictionary.")
            }
            if contents.snippets > 0 {
                lines.append("Not imported: \(StatusText.counted(contents.snippets, "snippet")).")
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

    private func edit(_ row: DictionaryModel.Row) {
        editing = Editing(row: row, draft: model.draft(for: row))
    }

    private func delete() {
        guard !selection.isEmpty else { return }
        model.delete(selection)
        selection = []
    }
}

private struct DictionaryRowView: View {
    let draft: EntryDraft

    var body: some View {
        HStack(spacing: 6) {
            Text(draft.word)
            if draft.isReplacing {
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(draft.replacement.isEmpty ? "(deleted from text)" : draft.replacement)
                    .foregroundStyle(draft.replacement.isEmpty ? .secondary : .primary)
            } else if draft.word.count > PersonalDictionary.maxKeytermLength {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help(
                        "Longer than \(PersonalDictionary.maxKeytermLength) characters, so it is not sent to the "
                            + "speech model."
                    )
            }
        }
    }
}

private struct EntryEditor: View {
    @State var draft: EntryDraft
    let isNew: Bool
    let onSave: (EntryDraft) throws(DictionaryError) -> Void
    @State private var error: DictionaryError?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Word", text: $draft.word, prompt: Text("PyTorch"))
                Toggle("Replace it with", isOn: $draft.isReplacing.animation())
                if draft.isReplacing {
                    TextField("Replacement", text: $draft.replacement, prompt: Text("Leave empty to remove the word"))
                    Toggle("Whole words only", isOn: $draft.isWholeWord)
                    Toggle("Match case", isOn: $draft.isCaseSensitive)
                }
                if let error {
                    Text(message(for: error)).foregroundStyle(.red)
                }
            } header: {
                Text(isNew ? "Add Word" : "Edit Word").font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") { save() }
            }
        }
    }

    private func save() {
        do {
            try onSave(draft)
            dismiss()
        } catch {
            self.error = error
        }
    }

    private func message(for error: DictionaryError) -> String {
        switch error {
        case .empty: "Enter a word."
        case .duplicate:
            draft.isReplacing
                ? "There is already a replacement for this word." : "This word is already in the dictionary."
        }
    }
}

// MARK: - Snapshots

@MainActor
extension SettingsPane {
    static func dictionarySnapshots() -> [Snapshot] {
        let sample = sampleDictionary
        let (incoming, contents) = sampleWisprImport
        return [
            SettingsWindow.snapshot(of: .dictionary(sampleModel(sample)), named: "settings-dictionary"),
            SettingsWindow.snapshot(
                of: .dictionary(sampleModel(PersonalDictionary())), named: "settings-dictionary-empty"),
            SettingsWindow.snapshot(
                of: .dictionary(sampleModel(sample, import: .preview(sample.importPreview(of: incoming), contents))),
                named: "settings-dictionary-import"
            ),
            SettingsWindow.snapshot(
                of: .dictionary(sampleModel(sample, import: .notFound)), named: "settings-dictionary-import-not-found"),
            Snapshot(name: "settings-dictionary-editor") {
                let rule = ReplacementRule(find: "cloud code", replacement: "Claude Code")
                let editor = EntryEditor(draft: EntryDraft(rule: rule), isNew: false) { _ throws(DictionaryError) in }
                return Snapshots.hostingView(editor)
            },
        ] + windowSnapshots()
    }
}
