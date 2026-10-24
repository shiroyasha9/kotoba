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
/// An example on the Cleanup page, in the row under the line that says what the feature does: what goes in and what
/// kotoba pastes in two columns, the input in the secondary colour and the result in the primary one.
struct CleanupSample: View {
    let before: (title: String, text: String)
    let after: (title: String, text: String)

    var body: some View {
        HStack(alignment: .top) {
            column(before, style: .secondary)
            column(after, style: .primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func column(_ part: (title: String, text: String), style: HierarchicalShapeStyle) -> some View {
        VStack(alignment: .leading) {
            Text(part.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("“\(part.text)”")
                .foregroundStyle(style)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
