import KotobaCore
import SwiftUI

/// The sheet that adds or edits one Dictionary entry: a word, or a word and its replacement. A save that fails (an empty
/// or duplicate word) says why in the form and keeps the sheet open.
struct EntryEditor: View {
    @State var draft: EntryDraft
    let isNew: Bool
    let onSave: (EntryDraft) throws(DictionaryError) -> Void
    @State private var error: DictionaryError?

    var body: some View {
        let title = isNew ? "Add Word" : "Edit Word"
        PageSheet(title: title, confirm: .init(title: isNew ? "Add" : "Save", action: save)) {
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
                // A sheet shows no window title, so its first header names it, as Activity's "Advanced…".
                Text(title)
            }
        }
    }

    private func save() -> Bool {
        do {
            try onSave(draft)
            return true
        } catch {
            self.error = error
            return false
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
