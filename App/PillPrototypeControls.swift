import AppKit
import SwiftUI

// The 0.5.0 pill prototype's controls (docs/research/ui-redesign.md, "Pill"): its buttons and the idle pill's keycaps.
// They sit on the pill's glass, so none has glass of its own: Apple's rule is fills on glass, never glass on glass.

/// A pill button: a text button ("Retry", "Undo") or a round symbol button (Cancel ×, Stop ■), in a system fill.
struct PillFillButton: View {
    enum Face: Equatable {
        case text(String)
        /// A round button that shows `symbol`; VoiceOver reads `label`.
        case symbol(String, label: String)
    }

    var face = Face.text("")
    /// The accent fill, for the one main action (Stop); the others take the neutral fill.
    var isProminent = false
    var onClick: () -> Void = {}

    var body: some View {
        let button = Button(action: onClick) {
            switch face {
            case .text(let title): Text(title)
            case .symbol(let symbol, let label): Image(systemName: symbol).accessibilityLabel(label)
            }
        }
        .buttonBorderShape(isRound ? .circle : .capsule)
        // A large round button is as tall as a regular text button (24.5 and 24 pt on macOS 27), so both keep the
        // same margin in the capsule.
        .controlSize(isRound ? .large : .regular)
        // The pill's panel is never key; this draws the button as in the key window, not dimmed.
        .environment(\.controlActiveState, .key)
        if isProminent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var isRound: Bool {
        if case .symbol = face { return true }
        return false
    }

    /// What VoiceOver reads for the button.
    var label: String {
        switch face {
        case .text(let title): title
        case .symbol(_, let label): label
        }
    }
}

/// Hosts a `PillFillButton` in the pill. It acts on the first click in the panel that is never key, and it is the
/// button itself for VoiceOver, offscreen too: SwiftUI exposes no button inside a hosting view before it shows
/// (as `FirstClickHostingView`).
final class PillFillButtonHost: NSHostingView<PillFillButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        rootView.label
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        self
    }

    override func accessibilityPerformPress() -> Bool {
        rootView.onClick()
        return true
    }
}

/// The idle pill's keycaps on hover: one cap per key of the chord ("⌃", "⌥", "⌘"), after the word that says what the
/// chord does. Custom: macOS has no keycap view. Each cap is as tall as a regular button, so it sits in the capsule
/// with the same margin as one.
struct PillKeycaps: View {
    var keys: [String] = []

    var body: some View {
        HStack(spacing: PillGeometry.keycapGap) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.body)
                    // Primary: secondary keys were almost gone on coloured glass (owner trial, 2026-10-24).
                    .foregroundStyle(.primary)
                    .frame(width: PillGeometry.controlHeight, height: PillGeometry.controlHeight)
                    .background(.fill.tertiary, in: .rect(cornerRadius: PillGeometry.keycapRadius))
            }
        }
        // The pill reads the chord as one label; the caps are not buttons.
        .accessibilityHidden(true)
    }
}
