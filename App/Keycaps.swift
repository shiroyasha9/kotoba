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
        .accessibilityLabel(keys.joined(separator: " "))
    }

    /// A modifier as its SF Symbol, which centres in the key; the font draws ⌃ at cap height, 3 pt above ⌥ and ⌘
    /// (review-window.md, 5). Any other key as text.
    @ViewBuilder private static func legend(_ key: String) -> some View {
        if let symbol = modifierSymbols[key] {
            Image(systemName: symbol)
        } else {
            Text(key)
                .padding(.horizontal, PageMetrics.keycapInset)
        }
    }

    private static let modifierSymbols = ["⌃": "control", "⌥": "option", "⌘": "command", "⇧": "shift"]

    private static let shape = RoundedRectangle(
        cornerRadius: PageMetrics.keycapSide * PageMetrics.tileCornerRatio, style: .continuous)
}
