import SwiftUI

/// A chord as keycaps with each key's name in small text under it, as a Mac keyboard prints "control" under ⌃
/// (docs/research/ui-redesign.md, "Onboarding"): the first time the owner meets the symbols, the names teach them. A
/// one-side modifier ("right ⌥", from Wispr Flow's keys) draws its symbol, and its name says the side. Its vertical
/// centre is the keycaps' centre, with the names hanging below, so the keycaps centre on a button or a row's title
/// beside them (owner QA 3, S1: centred as a whole, the keycaps sat above Change…). `KeyColumns` spaces the keys.
struct NamedKeycaps: View {
    let keys: [String]

    var body: some View {
        let keys = keys.map(Self.legendAndName)
        KeyColumns {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Keycaps(keys: [key.legend])
                    .anchorPreference(key: Parts.self, value: .bounds) { [Part(isName: false, bounds: $0)] }
                if let name = key.name {
                    Self.nameText(name)
                        .layoutValue(key: KeyColumns.Role.self, value: .name)
                        .anchorPreference(key: Parts.self, value: .bounds) { [Part(isName: true, bounds: $0)] }
                }
            }
            ForEach(Self.modifierNames, id: \.self) { name in
                Self.nameText(name).hidden().layoutValue(key: KeyColumns.Role.self, value: .reference)
            }
        }
        // At its own width beside Change…: the row's text wraps instead of the key names.
        .fixedSize()
        .alignmentGuide(VerticalAlignment.center) { $0[.top] + Self.keysCentre }
        .alignmentGuide(.titleLine) { $0[.top] + Self.keysCentre }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map { $0.name ?? $0.legend }.joined(separator: " "))
    }

    /// The keycaps' centre below the view's top: the names hang under it.
    static var keysCentre: CGFloat { PageMetrics.keycapSide / 2 }

    /// Every modifier's name, in a fixed order: `KeyColumns` sets the gap between keys from them.
    private static let modifierNames = Keycaps.names.values.sorted()

    /// A key's name; the keycap's legend keeps the primary label colour.
    private static func nameText(_ name: String) -> some View {
        Text(name)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// What a key's cap draws, and the name under it: "right ⌥" draws ⌥ over "right option".
    private static func legendAndName(_ key: String) -> (legend: String, name: String?) {
        for side in ["left ", "right "] where key.hasPrefix(side) {
            let legend = String(key.dropFirst(side.count))
            if let name = Keycaps.names[legend] { return (legend, side + name) }
        }
        return (key, Keycaps.names[key])
    }

    /// A keycap's or a name's bounds, for the view check that measures the gaps (`keycapsBesideButtonSnapshot`).
    struct Part {
        let isName: Bool
        let bounds: Anchor<CGRect>
    }

    struct Parts: PreferenceKey {
        static var defaultValue: [Part] { [] }

        static func reduce(value: inout [Part], nextValue: () -> [Part]) {
            value += nextValue()
        }
    }
}

/// `NamedKeycaps`' keys one gap apart in every row, each name centred under its key (owner QA 4, U2: with every
/// column as wide as the chord's widest name, "command" spread ⌃⌥⌘ twice as wide as ⌥⇧S). The gap is the one at which
/// the two widest modifier names ("control", "command") stay a text space apart under two neighbouring keys, so any
/// two modifiers fit; a pair moves further apart only when its own names need it ("right control", "right option").
/// The names may run past the last key by as much as the widest modifier name does, so the last key ends at one x
/// before the button beside it in every row, and the first name never runs into the row's text.
struct KeyColumns: Layout {
    /// A keycap starts a column; a name under it follows it; a reference is a hidden modifier name.
    enum Kind {
        case key, name, reference
    }

    enum Role: LayoutValueKey {
        static let defaultValue = Kind.key
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(of: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(of: subviews).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    /// Every subview's frame from the view's top leading corner, and the view's size.
    private func frames(of subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var columns: [(key: Int, name: Int?)] = []
        var references: [Int] = []
        for (index, subview) in subviews.enumerated() {
            switch subview[Role.self] {
            case .key: columns.append((index, nil))
            case .name: columns[columns.count - 1].name = index
            case .reference: references.append(index)
            }
        }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var frames = sizes.map { CGRect(origin: .zero, size: $0) }
        guard let first = columns.first else { return (frames, .zero) }

        // The system's spaces: between two keycaps, between two words side by side, from a keycap down to its name.
        let keySpacing = columns.count > 1 ? spacing(subviews, columns[0].key, columns[1].key, .horizontal) : 0
        let nameSpacing = references.count > 1 ? spacing(subviews, references[0], references[1], .horizontal) : 0
        let side = sizes[first.key].height
        let widest = references.map { sizes[$0].width }.sorted(by: >)
        let keyGap = max(keySpacing, widest.count > 1 ? (widest[0] + widest[1]) / 2 + nameSpacing - side : 0)
        let nameWidth = { (column: (key: Int, name: Int?)) in column.name.map { sizes[$0].width } ?? 0 }

        var centre = max(sizes[first.key].width, nameWidth(first)) / 2
        var namesHeight: CGFloat = 0
        for (offset, column) in columns.enumerated() {
            if offset > 0 {
                let previous = columns[offset - 1]
                var step = (sizes[previous.key].width + sizes[column.key].width) / 2 + keyGap
                if previous.name != nil, column.name != nil {
                    step = max(step, (nameWidth(previous) + nameWidth(column)) / 2 + nameSpacing)
                }
                centre += step
            }
            frames[column.key].origin = CGPoint(x: centre - sizes[column.key].width / 2, y: 0)
            if let name = column.name {
                let top = side + spacing(subviews, column.key, name, .vertical)
                frames[name].origin = CGPoint(x: centre - sizes[name].width / 2, y: top)
                namesHeight = max(namesHeight, top + sizes[name].height)
            }
        }
        let last = columns[columns.count - 1]
        let overhang = max((widest.first ?? 0) - side, nameWidth(last) - sizes[last.key].width, 0) / 2
        let width = centre + sizes[last.key].width / 2 + overhang
        return (frames, CGSize(width: width, height: max(side, namesHeight)))
    }

    private func spacing(_ subviews: Subviews, _ from: Int, _ to: Int, _ axis: Axis) -> CGFloat {
        subviews[from].spacing.distance(to: subviews[to].spacing, along: axis)
    }
}
