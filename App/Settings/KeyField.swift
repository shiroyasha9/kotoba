import KotobaProviders
import SwiftUI

/// One provider's key, as the Speech pane and onboarding show it. With no key saved: a secure field and Save. With a
/// key saved: the masked key ("sk-or-v1-…a1b2") with Change… and Remove, as provider dashboards show a key they keep.
/// An empty field with a placeholder would say no key is saved (HIG, Text fields: placeholder text shows only when the
/// field holds nothing). The key itself never comes back to the screen; it stays in the Keychain.
struct KeyField: View {
    let account: ProviderAccount
    let keyChecks: KeyChecks
    var fieldWidth: CGFloat = 220
    /// The owner clicked Change…: the field shows over the saved key until Save or Cancel.
    @State private var isChanging = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let isSaved = keyChecks.isSaved(account)
        if isSaved && !isChanging {
            HStack {
                // Dots until the Keychain answers, or when it is locked: a saved password shows so in System Settings.
                Text(keyChecks.masks[account] ?? "••••••••")
                    .foregroundStyle(.secondary)
                    .textSelection(.disabled)
                    .accessibilityLabel("Saved \(account.title) key")
                Button("Change…") { isChanging = true }
                Button("Remove", role: .destructive) { keyChecks.remove(account) }
            }
            .task { await keyChecks.loadMask(for: account) }
        } else {
            HStack {
                SecureField("Key", text: $draft, prompt: Text("Paste your \(account.title) key"))
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .focused($isFieldFocused)
                    .onSubmit(save)
                    // After Change…, the cursor goes in the field for the new key.
                    .onAppear { isFieldFocused = isChanging }
                Button("Save", action: save).disabled(isDraftEmpty)
                if isSaved {
                    Button("Cancel") {
                        draft = ""
                        isChanging = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private var isDraftEmpty: Bool { draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func save() {
        // Return in an empty field keeps it open.
        guard !isDraftEmpty else { return }
        let key = draft
        draft = ""
        isChanging = false
        Task { await keyChecks.save(key, for: account) }
    }
}
