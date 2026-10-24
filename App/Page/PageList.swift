import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the inset
/// list style of Apple's list apps, across the whole detail column as Mail's and Notes' lists.
///
/// What must stay in view (the page's header, a setting, its `PageSearchField`) goes in `pinned`: above the rows, never
/// scrolled and never rebuilt with them, so a search keeps its focus while the rows reload, ⌘F always reaches it, and a
/// failed read does not hide it. It lines up with the rows' text, and a `PageRow` in it has a list row's insets.
///
/// Full width, not in the page column (chief of staff, 2026-10-25, option A): SwiftUI's List ignores scroll content
/// margins, and a list narrowed by safe-area padding narrows its scroll view, so the title bar took its tint over the
/// column only (dark mode, ui-history). The centred list (d19b02d) comes back with a revert of 1345ab7.
struct PageList<SelectionValue: Hashable, Content: View, Pinned: View>: View {
    @Binding var selection: Set<SelectionValue>
    @ViewBuilder let content: Content
    @ViewBuilder let pinned: Pinned

    var body: some View {
        List(selection: $selection) {
            content
        }
        .listStyle(.inset)
        // In the list's top safe area, so the rows scroll under it and the title bar keeps the list's tint across.
        .safeAreaInset(edge: .top, spacing: 0) {
            if Pinned.self != EmptyView.self {
                VStack(alignment: .leading) {
                    pinned
                }
                .padding()
            }
        }
    }
}

extension PageList where Pinned == EmptyView {
    init(selection: Binding<Set<SelectionValue>>, @ViewBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { EmptyView() }
    }
}
