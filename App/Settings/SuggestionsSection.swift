import AppKit
import KotobaCore
import SwiftUI

/// Suggestions learned from corrections, at the top of the Dictionary pane: the owner adds or dismisses each one
/// (docs/research/auto-learning.md 4.2). Strong corrections kotoba reads back after a paste skip this list: they are
/// added at once, with Undo on the pill (docs/spec.md, Owner round 2026-10-16).
struct SuggestionsSection: View {
    let model: DictionaryModel

    var body: some View {
        Section {
            ForEach(model.suggestions) { suggestion in
                SuggestionRow(suggestion: suggestion) {
                    model.addSuggestions([suggestion.id])
                } dismiss: {
                    model.dismissSuggestions([suggestion.id])
                }
                .selectionDisabled()
            }
        } header: {
            HStack {
                Text("Suggestions")
                Spacer()
                if model.suggestions.count > 1 {
                    Button("Add All") { model.addSuggestions(Set(model.suggestions.map(\.id))) }
                        .buttonStyle(.link)
                }
            }
        }
    }
}

/// "Learn from my edits", in the Dictionary pane's header box: a pane-level setting, as System Settings places them.
/// Off, kotoba never observes another app's field (`AXFieldWatcher`).
struct LearnFromEditsToggle: View {
    // The registered default applies; the initial value here is only what @AppStorage requires.
    @AppStorage(AppDefaults.Key.learnsFromEdits.rawValue)
    private var isLearningFromEdits = AppDefaults.isLearningFromEdits

    // Custom row: outside a Form a switch sits next to its label, and this row puts it at the trailing edge, as a Form
    // row does. A grouped Form above the word list cannot hold it: a fixed-height Form makes the pane's ideal height
    // the list's full height, and the Settings window then grows past the screen (spike, docs/research/native-ui.md).
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Learn from my edits")
                Text("When you fix a word kotoba pasted, kotoba adds it to your dictionary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Learn from my edits", isOn: $isLearningFromEdits)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: DictionarySuggestion
    let add: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let candidate = suggestion.candidate
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                SuggestionCandidateLabel(candidate: candidate)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            Button("Add", action: add)
        }
        .controlSize(.small)
    }

    /// "Cursor · Seen 3 times"
    private var detail: String {
        var parts: [String] = []
        if let app = appName {
            parts.append(app)
        }
        if suggestion.evidence > 1 {
            parts.append("Seen " + StatusText.counted(suggestion.evidence, "time"))
        }
        return parts.joined(separator: " · ")
    }

    private var appName: String? {
        guard let bundleID = suggestion.candidate.appBundleID,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacing(/\.app$/, with: "")
    }
}

/// A correction as the owner reads it: "versel → Vercel" for a word and its replacement, "embra  Heard as “ember”"
/// for a word only. The Suggestions section and "Fix Last Dictation…" show it the same way.
struct SuggestionCandidateLabel: View {
    let candidate: SuggestionCandidate

    var body: some View {
        HStack(spacing: 6) {
            if candidate.proposes == .termAndRule {
                Text(candidate.heard)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(candidate.corrected).bold()
            } else {
                Text(candidate.corrected).bold()
                if !candidate.heard.isEmpty {
                    Text("Heard as “\(candidate.heard)”").foregroundStyle(.secondary)
                }
            }
        }
    }
}
