import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the inset
/// list style of Apple's list apps, across the whole detail column as Mail's and Notes' lists.
///
/// What must stay in view (the page's header, a setting) goes in `pinned`, as form sections: cards above the rows as on
/// every other page, never scrolled with the rows and never rebuilt with them, so a failed read does not hide them. The
/// page's search is in the window toolbar (`pageSearch`).
///
/// Full width, not in the page column (chief of staff, 2026-10-25, option A): SwiftUI's List ignores scroll content
/// margins, and a list narrowed by safe-area padding narrows its scroll view, so the title bar took its tint over the
/// column only (dark mode, ui-history).
struct PageList<SelectionValue: Hashable, Content: View, Pinned: View>: View {
    @Binding var selection: Set<SelectionValue>
    @ViewBuilder let content: Content
    @ViewBuilder let pinned: Pinned

    var body: some View {
        VStack(spacing: 0) {
            if Pinned.self != EmptyView.self {
                // A grouped form at its content's height: native cards, spacing and type. At most half the smallest
                // window, so the rows always have room; taller content (large text, a narrow window) scrolls there
                // instead of being cut off, and content that fits does not bounce.
                IdealHeight(within: 0...PageMetrics.pinnedMaxHeight) {
                    Form {
                        pinned
                    }
                    .formStyle(.grouped)
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            List(selection: $selection) {
                content
            }
            .listStyle(.inset)
            // The rows take the height left under the cards; a list's own ideal height is all its rows.
            .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity)
        }
    }
}
extension PageList where Pinned == EmptyView {
    init(selection: Binding<Set<SelectionValue>>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { EmptyView() }
    }
}
