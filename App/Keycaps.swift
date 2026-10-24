import SwiftUI

/// A chord drawn as keys, one keycap per key. Custom: macOS has no keycap view.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                // The push button's own title size.
                Self.legend(key)
                    .font(.body)
                    .frame(minWidth: PageMetrics.keycapSide, minHeight: PageMetrics.keycapSide)
                    .fixedSize()
                    .background(.fill.tertiary, in: Self.shape)
                    .overlay(Self.shape.strokeBorder(.separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spoken(keys))
    }

    /// A modifier as its SF Symbol, which centres in the key; the font draws ⌃ at cap height, 3 pt above ⌥ and ⌘
    /// (review-window.md, 5). Any other key as text.
    @ViewBuilder private static func legend(_ key: String) -> some View {
        if let symbol = modifiers[key]?.symbol {
            Image(systemName: symbol)
        } else {
            Text(key)
                .padding(.horizontal, PageMetrics.keycapInset)
        }
    }

    /// A modifier key: the SF Symbol its keycap draws (nil: its legend is text, as fn) and the name Apple's keyboards
    /// print on it.
    private struct Modifier {
        var symbol: String?
        let name: String
    }

    /// The modifier keys, by the legend a chord's title uses: one table for what a keycap draws and what VoiceOver
    /// reads.
    private static let modifiers: [String: Modifier] = [
        "⌃": Modifier(symbol: "control", name: "control"),
        "⌥": Modifier(symbol: "option", name: "option"),
        "⌘": Modifier(symbol: "command", name: "command"),
        "⇧": Modifier(symbol: "shift", name: "shift"),
        "fn": Modifier(name: "fn"),
    ]

    /// The names VoiceOver reads for the modifier legends ("control option command"); a letter or a word key ("Esc")
    /// names itself. Onboarding prints them under its keycaps.
    static let names = modifiers.mapValues(\.name)

    static func spoken(_ keys: [String]) -> String {
        keys.map { names[$0] ?? $0 }.joined(separator: " ")
    }

    private static let shape = RoundedRectangle(
        cornerRadius: PageMetrics.keycapSide * PageMetrics.tileCornerRatio, style: .continuous)
}
