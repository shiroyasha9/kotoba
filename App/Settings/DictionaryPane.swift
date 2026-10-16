import KotobaCore
import KotobaStorage
import SwiftUI

extension SettingsPane {
    static func dictionary(_ model: DictionaryModel) -> Self {
        SettingsPane(id: .dictionary) {
            AnyView(DictionaryPane(model: model))
        }
    }
}

private struct DictionaryPane: View {
    @Bindable var model: DictionaryModel
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.settingsFindRequests) private var findRequests
    @State private var selection: Set<DictionaryModel.Row> = []
    /// The sheet: nil row adds a new entry.
    @State private var editing: Editing?

    private struct Editing: Identifiable {
        let id = UUID()
        let row: DictionaryModel.Row?
        let draft: EntryDraft
    }

    var body: some View {
        // A list in a group box with Add and Delete at its foot, as in System Settings > General > Login Items: a list
        // this long needs the list's own selection and lazy rows, which a grouped form has not.
        VStack(alignment: .leading) {
            // The pane's own switch sits in its header box, as the Bluetooth switch does in System Settings.
            GroupBox {
                VStack(alignment: .leading) {
                    PaneHeader(pane: .dictionary)
                    Divider()
                    LearnFromEditsToggle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            words
        }
        .padding()
        .searchable(text: $search, placement: .toolbar, prompt: "Search words")
        .searchFocused($isSearchFocused)
        .onChange(of: findRequests) { isSearchFocused = true }
        .alert(Self.importTitle(model.wisprImport), isPresented: isAlertShown, presenting: model.wisprImport) { state in
            // Each button clears the state itself, so the binding never has to.
            if case .preview(let preview, _) = state, !preview.isEmpty {
                Button("Cancel", role: .cancel) { model.wisprImport = nil }
                Button("Import") { model.applyWisprImport() }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("OK") { model.wisprImport = nil }
            }
        } message: { state in
            Text(Self.importMessage(state))
        }
        .sheet(item: $editing) { editing in
            EntryEditor(draft: editing.draft, isNew: editing.row == nil) { draft throws(DictionaryError) in
                try model.save(draft, replacing: editing.row)
                selection = []
            }
        }
    }

    private var words: some View {
        VStack(alignment: .leading) {
            GroupBox {
                list
                Divider()
                editButtons
            }
            footer
        }
    }

    private var list: some View {
        let rows = visibleRows
        return List(selection: $selection) {
            if !model.suggestions.isEmpty, search.isEmpty {
                SuggestionsSection(model: model)
            }
            Section {
                ForEach(rows, id: \.self) { row in
                    DictionaryRowView(
                        draft: model.draft(for: row), sendsKeyterm: model.keyterm(for: row) != nil,
                        isPinned: model.isPinned(row), isNotSent: model.isNotSent(row)
                    ) { model.setPinned(row, $0) }
                }
            } header: {
                if !model.suggestions.isEmpty, search.isEmpty, !rows.isEmpty {
                    Text("Words and Replacements")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
            if rows.isEmpty, model.suggestions.isEmpty || !search.isEmpty {
                emptyState
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if search.isEmpty {
            ContentUnavailableView {
                Label("No Words Yet", systemImage: "character.book.closed")
            } description: {
                Text(
                    "Add names and terms the speech model should know, or fix a word it always gets wrong. "
                        + "You can also import from Wispr Flow.")
            } actions: {
                Button("Add Word…", action: add)
            }
        } else {
            ContentUnavailableView.search(text: search)
        }
    }

    private var editButtons: some View {
        HStack {
            Button("Add", systemImage: "plus", action: add)
            Button("Delete", systemImage: "minus") { delete() }
                .disabled(selection.isEmpty)
            Spacer()
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
    }

    /// The counts, a save error, and the import from Wispr Flow, under the box.
    private var footer: some View {
        HStack {
            VStack(alignment: .leading) {
                // An empty dictionary shows its own message in the box; "0 words" adds nothing.
                if !model.rows.isEmpty {
                    Text(summary)
                }
                if let saveError = model.saveError {
                    Text(saveError).foregroundStyle(.red)
                }
            }
            .font(.callout)
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
            dictionary.keyterms.count <= PersonalDictionary.maxKeyterms
            ? "The speech model gets up to \(PersonalDictionary.maxKeyterms) words as hints."
            : "The speech model gets \(PersonalDictionary.maxKeyterms) words as hints: starred words first, then the "
                + "words you use most."
        let words = StatusText.counted(dictionary.terms.count, "word")
        let replacements = StatusText.counted(dictionary.rules.count, "replacement")
        return "\(words), \(replacements). " + hints
    }

    private var isReading: Bool {
        if case .reading = model.wisprImport { true } else { false }
    }

    /// The import preview, or why there is none, as an alert until the owner answers.
    private var isAlertShown: Binding<Bool> {
        Binding(get: { model.wisprImport != nil && !isReading }, set: { _ in })
    }

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
            var lines = [
                preview.isEmpty
                    ? "Every word in Wispr Flow’s dictionary is already here."
                    : "Adds \(StatusText.counted(preview.terms.count, "word")) and "
                        + "\(StatusText.counted(preview.rules.count, "replacement"))."
            ]
            if contents.learnedCorrections > 0 {
                lines.append(
                    "Includes \(StatusText.counted(contents.learnedCorrections, "learned correction")). "
                        + "Each one replaces what Wispr heard with the word you corrected it to.")
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

    private func add() {
        editing = Editing(row: nil, draft: EntryDraft())
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

// MARK: - Snapshots

@MainActor
extension SettingsPane {
    static func dictionarySnapshots() -> [Snapshot] {
        let sample = sampleDictionary
        let (incoming, contents) = sampleWisprImport
        return [
            SettingsWindow.snapshot(of: .dictionary(sampleModel(sample)), named: "settings-dictionary"),
            SettingsWindow.snapshot(of: .dictionary(sampleOverCapModel), named: "settings-dictionary-over-cap"),
            SettingsWindow.snapshot(
                of: .dictionary(sampleModel(PersonalDictionary())), named: "settings-dictionary-empty"),
            importAlert(.preview(sample.importPreview(of: incoming), contents), named: "settings-dictionary-import"),
            importAlert(.notFound, named: "settings-dictionary-import-not-found"),
            Snapshot(name: "settings-dictionary-editor") {
                let rule = ReplacementRule(find: "cloud code", replacement: "Claude Code")
                let editor = EntryEditor(draft: EntryDraft(rule: rule), isNew: false) { _ throws(DictionaryError) in }
                return Snapshots.hostingView(editor)
            },
        ] + windowSnapshots()
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
