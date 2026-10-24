import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the inset
/// list style of Apple's list apps, across the whole detail column as Mail's and Notes' lists. Put `PageHeader` and rows
/// that are not selectable in its first sections with `.selectionDisabled()`.
///
/// Full width, not in the page column (chief of staff, 2026-10-25, option A): SwiftUI's List ignores scroll content
/// margins, and a list narrowed by safe-area padding narrows its scroll view, so the title bar took its tint over the
/// column only (dark mode, ui-history). The centred list (d19b02d) comes back with a revert of this change.
struct PageList<SelectionValue: Hashable, Content: View>: View {
    @Binding var selection: Set<SelectionValue>
    /// The page's search (`PageSearchField`), pinned above the rows: it stays in view and keeps the focus while the
    /// list scrolls and reloads under it. Nil: no search.
    var search: (text: Binding<String>, prompt: String)?
    @ViewBuilder let content: Content

    var body: some View {
        List(selection: $selection) {
            content
        }
        .listStyle(.inset)
        // In the list's top safe area, so the rows scroll under it and the title bar keeps the list's tint across.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let search {
                PageSearchField(text: search.text, prompt: search.prompt)
                    .padding()
            }
        }
    }
}
