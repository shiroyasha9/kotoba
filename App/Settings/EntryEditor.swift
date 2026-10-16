import KotobaCore
import SwiftUI

/// The sheet that adds or edits one Dictionary entry: a word, or a word and its replacement.
struct EntryEditor: View {
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
