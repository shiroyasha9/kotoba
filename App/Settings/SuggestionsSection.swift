import AppKit
import KotobaCore
import SwiftUI

/// Suggestions learned from corrections, at the top of the Dictionary pane: the owner adds or dismisses each one
/// (docs/research/auto-learning.md 4.2). Nothing is added without a click.
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
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(.vertical, 2)
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
