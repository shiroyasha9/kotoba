import KotobaCore
import SwiftUI

extension AppMode {
    /// The style's name in the page's pickers.
    var title: String {
        switch self {
        case .code: "Code"
        case .writing: "Writing"
        }
    }

    /// Which apps the style is for, under its switch.
    var apps: String {
        switch self {
        case .code: "Terminals, editors and coding agents"
        case .writing: "Messages, mail and notes"
        }
    }

    /// What the owner says and what the style's cleanup pastes: the first example in the style's prompt
    /// (`OpenRouterCleaner`), so the page shows what the model was taught.
    var sample: (spoken: String, cleaned: String) {
        switch self {
        case .code:
            (
                "um so can you uh open the the auth dot ts file and uh check why login fails when I pass dash dash "
                    + "verbose, no, dash dash debug",
                "Can you open the auth.ts file and check why login fails when I pass --debug?"
            )
        case .writing:
            (
                "um hey so I I looked at the the PR and uh it looks good to me, can you merge it on Monday, no, on "
                    + "Tuesday",
                "Hey, I looked at the PR and it looks good to me. Can you merge it on Tuesday?"
            )
        }
    }
}

// Custom: no native control shows a before and after.
/// An example on the Cleanup page, in the row under the line that says what the feature does: what goes in, with the
/// words kotoba drops struck through in History's View Changes look (`ChangesView.marked`), then what kotoba pastes
/// under it in the primary colour (owner QA 1, Q14: two columns side by side did not read as before and after).
struct CleanupSample: View {
    let before: (title: String, text: String)
    let after: (title: String, text: String)
    /// `before` with the words `after` drops (`WordDiff.dropped`): the pasted text below shows the rest.
    private let kept: [WordDiff.Run]

    init(before: (title: String, text: String), after: (title: String, text: String)) {
        self.before = before
        self.after = after
        kept = WordDiff.dropped(from: before.text, to: after.text)
    }

    var body: some View {
        VStack(alignment: .leading) {
            // The struck words keep their own colour; the rest is secondary, as the input was before.
            part(before.title, Text(AttributedString("“") + ChangesView.marked(kept) + AttributedString("”")))
                .foregroundStyle(.secondary)
                // The system's spacing between the two parts, so each title starts its own block.
                .padding(.bottom)
                .accessibilityLabel("\(before.title): \(ChangesView.spoken(kept))")
            part(after.title, Text("“\(after.text)”"))
        }
    }

    private func part(_ title: String, _ text: Text) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            text
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
