import KotobaCore
import KotobaStorage
import SwiftUI

extension Pane {
    static func dictionary(_ model: DictionaryModel) -> Self {
        Pane(id: .dictionary) {
            AnyView(DictionaryPane(model: model))
        }
    }
}

private struct DictionaryPane: View {
    @Bindable var model: DictionaryModel
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.findRequests) private var findRequests
    @Environment(\.addWordRequest) private var addWordRequest
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
            // The pane's own switch sits in a box above the list, as the Bluetooth switch does in System Settings.
            GroupBox {
                LearnFromEditsToggle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.groupBoxToFormInset)
            }
            words
        }
        .groupedFormLayout()
        .searchable(text: $search, placement: .toolbar, prompt: "Search words")
        .searchFocused($isSearchFocused)
        .onChange(of: findRequests) { isSearchFocused = true }
        .onChange(of: addWordRequest.wrappedValue, initial: true) { _, isRequested in
            guard isRequested else { return }
            addWordRequest.wrappedValue = false
            add()
        }
        .wisprImportAlert(model)
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
                .padding(.horizontal, Self.formFooterInset)
        }
    }

    /// A grouped Form draws its row text 10 pt in from the box and its footer 10 pt in from the box's edge; a group box
    /// insets its content 5 pt. These line the pane's switch and footer up with every other pane's (measured offscreen,
    /// 2026-10-17). Not a Form section: a Form above the list grows the window past the screen (`LearnFromEditsToggle`).
    private static let groupBoxToFormInset: CGFloat = 5
    private static let formFooterInset: CGFloat = 10

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
            EmptyState(
                title: "No Words Yet", systemImage: "character.book.closed",
                description: "Add names and terms the speech model should know, or fix a word it always gets wrong. "
                    + "You can also import from Wispr Flow."
            ) {
                Button("Add Word…", action: add)
            }
        } else {
            NoSearchResults(search: search)
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

    private var isReading: Bool { model.wisprImport?.isReading == true }

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

extension View {
    /// Lays out a pane that cannot be a grouped `Form` (Dictionary: its word list needs a list's lazy rows and
    /// selection) at a grouped Form's margins and width, so it lines up with every other pane: 20 pt from each edge,
    /// at most 704 pt wide, centred. SwiftUI has no API that reads these; measured offscreen on macOS 27 (2026-10-16)
    /// at pane widths from 360 to 1300 pt.
    func groupedFormLayout() -> some View {
        frame(maxWidth: 704)
            .padding(20)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Snapshots

@MainActor
extension Pane {
    static func dictionarySnapshots() -> [Snapshot] {
        let sample = sampleDictionary
        let (incoming, contents) = sampleWisprImport
        return [
            MainWindow.snapshot(of: .dictionary(sampleModel(sample)), named: "settings-dictionary"),
            MainWindow.snapshot(of: .dictionary(sampleOverCapModel), named: "settings-dictionary-over-cap"),
            MainWindow.snapshot(
                of: .dictionary(sampleModel(PersonalDictionary())), named: "settings-dictionary-empty"),
            importAlert(.preview(sample.importPreview(of: incoming), contents), named: "settings-dictionary-import"),
            importAlert(.notFound, named: "settings-dictionary-import-not-found"),
            Snapshot(name: "settings-dictionary-editor") {
                let rule = ReplacementRule(find: "cloud code", replacement: "Claude Code")
                let editor = EntryEditor(draft: EntryDraft(rule: rule), isNew: false) { _ throws(DictionaryError) in }
                return NSHostingView(rootView: editor)
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
