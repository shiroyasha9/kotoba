import KotobaCore
import SwiftUI

/// One word or replacement in the Dictionary list, with its star (always sent) and, when the last dictation was over
/// `PersonalDictionary.maxKeyterms`, whether it was left out. Values, not the model, so a pin or a count redraws only
/// the rows whose values changed.
struct DictionaryRowView: View {
    let draft: EntryDraft
    /// False for a word too long to send and a rule that deletes its word: no star.
    let sendsKeyterm: Bool
    let isPinned: Bool
    let isNotSent: Bool
    let onPin: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
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
                            + "the speech model."
                    )
            }
            Spacer()
            if isNotSent {
                Text("Not sent")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(
                        "Not sent with the last dictation, because the list has more than "
                            + "\(PersonalDictionary.maxKeyterms) words. Star it to always send it.")
            }
            if sendsKeyterm {
                star
            }
        }
    }

    private var star: some View {
        Button {
            onPin(!isPinned)
        } label: {
            Label(isPinned ? "Starred" : "Star", systemImage: isPinned ? "star.fill" : "star")
                .labelStyle(.iconOnly)
                .foregroundStyle(isPinned ? AnyShapeStyle(.yellow) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .help(
            isPinned
                ? "Always sent to the speech model. Click to unstar." : "Star to always send it to the speech model.")
    }
}
