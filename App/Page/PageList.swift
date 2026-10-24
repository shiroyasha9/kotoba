import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the list
/// style of Apple's list apps. Its rows sit where a `PageForm`'s cards sit, in the same centred column. Put
/// `PageHeader` and rows that are not selectable in its first sections with `.selectionDisabled()`.
struct PageList<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: Set<SelectionValue>
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        List(selection: $selection) {
            content
        }
        .listStyle(.inset)
        // A list draws its rows in the safe area; `contentMargins(for: .scrollContent)`, which centres a form, leaves a
        // list's rows full width (ui-history, 2026-10-25).
        .safeAreaPadding(.horizontal, sideInset)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    /// The margin that centres the column, then the form's own inset to its cards, less the list's deeper row inset, so
    /// a row's text starts where a card's text does.
    private var sideInset: CGFloat {
        max(width - PageMetrics.columnWidth, 0) / 2 + PageMetrics.formInset - PageMetrics.listRowExtraInset
    }
}
