import KotobaCore
import SwiftUI

/// One word or replacement in the Dictionary list: the word, or the word, an arrow and what kotoba writes instead; then
/// its star (always sent to the speech model) and, when the last dictation was over `PersonalDictionary.maxKeyterms`,
/// that it was left out. The star shows on hover and stays while starred (owner QA 1, Q13), as Mail's flag. Values, not
/// the model, so a pin or a count redraws only the rows whose values changed.
struct DictionaryRowView: View {
    let draft: EntryDraft
    /// False for a word too long to send and a rule that deletes its word: no star.
    let sendsKeyterm: Bool
    let isPinned: Bool
    let isNotSent: Bool
    let onPin: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(draft.word)
            if draft.isReplacing {
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Text(draft.replacement.isEmpty ? "(deleted from text)" : draft.replacement)
                    .foregroundStyle(draft.replacement.isEmpty ? .secondary : .primary)
            } else if !sendsKeyterm {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .help(
                        "Longer than \(PersonalDictionary.maxKeytermLength) characters, so kotoba does not send it to "
                            + "the speech model.")
            }
            Spacer()
            if isNotSent {
                Text("Not sent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help(
                        "Not sent with the last dictation: the list has more than \(PersonalDictionary.maxKeyterms) "
                            + "words. Star it to always send it.")
            }
            if sendsKeyterm {
                star
            }
        }
        .onHover { isHovered = $0 }
    }

    /// Hidden, not removed, while the row is not hovered or starred: the row keeps its height and VoiceOver keeps the
    /// button.
    private var star: some View {
        Button {
            onPin(!isPinned)
        } label: {
            Label(isPinned ? "Starred" : "Star", systemImage: isPinned ? "star.fill" : "star")
                .labelStyle(.iconOnly)
                .foregroundStyle(isPinned ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.borderless)
        .opacity(isPinned || isHovered ? 1 : 0)
        .help(
            isPinned
                ? "Always sent to the speech model. Click to unstar." : "Star to always send it to the speech model.")
    }
}
