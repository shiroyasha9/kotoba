// 0.5.0 ratchet: the Cleanup page's rollout puts this file on the page system and removes the next line.
// swiftlint:disable ui_layout_literal
import KotobaCore
import SwiftUI

extension AppMode {
    /// The mode's name in the pane's pickers.
    var title: String {
        switch self {
        case .code: "Code"
        case .writing: "Writing"
        }
    }

    /// What the mode's apps are and what its cleanup does, under its toggle.
    var summary: String {
        switch self {
        case .code: "Terminals, editors and coding agents. Cleanup keeps commands, paths and flags as you said them."
        case .writing: "Messages, mail and notes. Cleanup writes clear sentences in your words."
        }
    }

    /// What the owner says and what the mode's cleanup pastes: the first example in the mode's prompt
    /// (`OpenRouterCleaner`), so the pane shows what the model was taught.
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

// Custom: no native control shows a before and after. A group box clips its text inside a grouped form row.
/// One mode's sample, as Wispr Flow's cleanup cards show one: what the owner says and what the cleanup pastes, side by
/// side on the system's fill.
struct CleanupSample: View {
    let mode: AppMode

    var body: some View {
        VStack(alignment: .leading) {
            Text("\(mode.title) apps")
            HStack(alignment: .top) {
                card("You say", mode.sample.spoken, style: .secondary)
                card("kotoba pastes", mode.sample.cleaned, style: .primary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func card(_ title: String, _ text: String, style: HierarchicalShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(style)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
