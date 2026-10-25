import AppKit
import KotobaCore
import SwiftUI

/// Suggestions learned from corrections, above the Dictionary page's words: the owner adds or dismisses each one
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

/// "Learn from edits", at the top of the Dictionary page: a page-level setting, as System Settings places them. Off,
/// kotoba never observes another app's field (`AXFieldWatcher`).
struct LearnFromEditsToggle: View {
    // The registered default applies; the initial value here is only what @AppStorage requires.
    @AppStorage(AppDefaults.Key.learnsFromEdits.rawValue)
    private var isLearningFromEdits = AppDefaults.isLearningFromEdits

    var body: some View {
        PageToggle(
            title: "Learn from edits",
            subtitle: "When you fix a word after kotoba pastes it, the word goes into your dictionary.",
            isOn: $isLearningFromEdits)
    }
}

private struct SuggestionRow: View {
    let suggestion: DictionarySuggestion
    let add: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let candidate = suggestion.candidate
        // Not a `PageRow`: the title is a correction ("versel → Vercel"), not one string.
        HStack {
            SuggestionCandidateLabel(candidate: candidate, detail: detail)
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            Button("Add", action: add)
        }
    }

    /// "Cursor", "Seen 3 times"
    private var detail: [String] {
        var parts: [String] = []
        if let app = appName {
            parts.append(app)
        }
        if suggestion.evidence > 1 {
            parts.append("Seen " + StatusText.counted(suggestion.evidence, "time"))
        }
        return parts
    }

    private var appName: String? {
        suggestion.candidate.appBundleID.flatMap(InstalledApp.name(of:))
    }
}

/// A correction as the owner reads it, in one layout for both kinds (qa1-review, Dictionary): the change on the title
/// line, "versel → Vercel" for a word and its replacement, "embra" for a word only; under it, in a row's subtitle style,
/// what was heard for a word only, then `detail`. The Suggestions section and "Fix Last Dictation…" show it the same
/// way.
struct SuggestionCandidateLabel: View {
    let candidate: SuggestionCandidate
    /// After what was heard: where and how often ("TextEdit · Seen 3 times").
    var detail: [String] = []

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if candidate.proposes == .termAndRule {
                    Text(candidate.heard)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                }
                Text(candidate.corrected).bold()
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        let heard =
            candidate.proposes == .termAndRule || candidate.heard.isEmpty ? nil : "Heard as “\(candidate.heard)”"
        return ([heard].compactMap(\.self) + detail).joined(separator: " · ")
    }
}
