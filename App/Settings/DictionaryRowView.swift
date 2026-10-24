import KotobaCore
import SwiftUI

/// One word or replacement in the Dictionary list: the word, or the word, an arrow and what kotoba writes instead.
/// Values, not the model, so a change redraws only the rows whose values changed.
struct DictionaryRowView: View {
    let draft: EntryDraft

    var body: some View {
        HStack {
            Text(draft.word)
            if draft.isReplacing {
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(draft.replacement.isEmpty ? "(deleted from text)" : draft.replacement)
                    .foregroundStyle(draft.replacement.isEmpty ? .secondary : .primary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One word in the Dictionary's "Advanced…": its star (always sent to the speech model) and, when the last dictation was
/// over `PersonalDictionary.maxKeyterms`, that it was left out.
struct StarRow: View {
    /// The hint the row sends: its word, or the spelling its replacement writes.
    let word: String
    /// False for a word too long to send and a rule that deletes its word: no star.
    let sendsKeyterm: Bool
    let isPinned: Bool
    let isNotSent: Bool
    let onPin: (Bool) -> Void

    var body: some View {
        PageRow(title: word, subtitle: subtitle) {
            if sendsKeyterm {
                Button {
                    onPin(!isPinned)
                } label: {
                    Label(isPinned ? "Starred" : "Star", systemImage: isPinned ? "star.fill" : "star")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(isPinned ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
                }
                .buttonStyle(.borderless)
                .help(isPinned ? "Always sent. Click to unstar." : "Star to always send it.")
            }
        }
    }

    private var subtitle: String? {
        if !sendsKeyterm {
            return "Longer than \(PersonalDictionary.maxKeytermLength) characters, so kotoba never sends it."
        }
        return isNotSent ? "Not sent with your last dictation" : nil
    }
}
