import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the inset
/// list style of Apple's list apps, across the whole detail column as Mail's and Notes' lists.
///
/// What must stay in view (the page's header, a setting) goes in `pinned`, as form sections: cards above the rows as on
/// every other page, never scrolled with the rows and never rebuilt with them, so a failed read does not hide them. The
/// page's search is in the window toolbar (`pageSearch`).
///
/// The list exists only while the page has rows (`hasRows`); until then `unavailable` (nothing while the first read
/// runs, an `EmptyState`) takes its place. SwiftUI's list is an outline view that sizes each row to its content, and in
/// the window's detail column a list that is on screen with no sections kept the default 24 pt height for every row of
/// the sections that came in later: on the first open after launch, History's rows drew as one cut line until a page
/// switch built the list again (owner QA 1, Q8; `Pane.historyArrivalChecks`). A list built with its rows measures them.
///
/// Full width, not in the page column (chief of staff, 2026-10-25, option A): SwiftUI's List ignores scroll content
/// margins, and a list narrowed by safe-area padding narrows its scroll view, so the title bar took its tint over the
/// column only (dark mode, ui-history).
struct PageList<SelectionValue: Hashable, Content: View, Unavailable: View, Pinned: View>: View {
    @Binding var selection: Set<SelectionValue>
    let hasRows: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let unavailable: Unavailable
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
            if hasRows {
                List(selection: $selection) {
                    content
                }
                .listStyle(.inset)
                // The rows take the height left under the cards; a list's own ideal height is all its rows.
                .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity)
            } else {
                // Over a clear fill, so the space under the cards stays taken while `unavailable` draws nothing.
                Color.clear
                    .overlay { unavailable }
            }
        }
    }
}
extension PageList where Pinned == EmptyView {
    init(
        selection: Binding<Set<SelectionValue>>, hasRows: Bool, @ViewBuilder content: () -> Content,
        @ViewBuilder unavailable: () -> Unavailable
    ) {
        self.init(selection: selection, hasRows: hasRows, content: content, unavailable: unavailable) { EmptyView() }
    }
}
