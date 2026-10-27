import AppKit
import SwiftUI

/// A page that is a list (History: many rows, selection, list keys, rows built as they scroll into view), in the inset
/// list style of Apple's list apps, its cards and rows in the centred page column of every other page (`pageColumn`).
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
/// One set of edges for the cards and the rows (qa1-review 1): the selection runs from card edge to card edge, and the
/// rows' content and the day titles start in the cards' text column. A day is a `PageListSection`.
///
/// The column (docs/research/history-width.md): SwiftUI's List ignores scroll content margins (macOS 27, measured
/// 2026-10-27), so its rows move in by safe-area padding. The list's scroll view keeps the whole width (it scrolls
/// under the margins, and its title bar edge stays full width), but AppKit tiles its scroll bar inside the padding;
/// `ScrollerAtEdge` puts the bar back at the window's edge, as every other page's.
struct PageList<SelectionValue: Hashable, Content: View, Unavailable: View, Pinned: View>: View {
    @Binding var selection: Set<SelectionValue>
    let hasRows: Bool
    @ViewBuilder let content: Content
    @ViewBuilder let unavailable: Unavailable
    @ViewBuilder let pinned: Pinned
    @State private var width: CGFloat = 0
    @State private var legacyScrollerWidth = ScrollerAtEdge.legacyWidth

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
                    .pageColumn()
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            if hasRows {
                List(selection: $selection) {
                    content
                        // A row's content in the cards' text column, and its line ending where the content column
                        // ends, as a card's lines do.
                        .listRowInsets(.horizontal, PageMetrics.listRowInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .alignmentGuide(.listRowSeparatorTrailing) { $0[.trailing] }
                        .background { ScrollerAtEdge(trailingInset: trailingInset) }
                }
                .listStyle(.inset)
                // The selection at the cards' edges (qa1-review 1). Safe-area padding moves the rows only: the scroll
                // view keeps the full width.
                .safeAreaPadding(.leading, PageMetrics.columnMargin(in: width) + PageMetrics.listSideInset)
                .safeAreaPadding(.trailing, trailingInset)
                // The rows take the height left under the cards; a list's own ideal height is all its rows.
                .frame(minHeight: 0, idealHeight: 0, maxHeight: .infinity)
            } else {
                // Over a clear fill, so the space under the cards stays taken while `unavailable` draws nothing.
                Color.clear
                    .overlay { unavailable }
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSScroller.preferredScrollerStyleDidChangeNotification)
            {
                legacyScrollerWidth = ScrollerAtEdge.legacyWidth
            }
        }
    }

    /// The selection's trailing edge at the card edge: a legacy scroll bar takes its width from the list's content
    /// area, so the padding there is that much less (never less than the list's own inset).
    private var trailingInset: CGFloat {
        let inset = PageMetrics.columnMargin(in: width) + PageMetrics.listSideInset - legacyScrollerWidth
        return max(PageMetrics.listSideInset, inset)
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

/// Puts a list's vertical scroll bar at its scroll view's trailing edge. AppKit tiles the bar inside the content insets
/// that SwiftUI's safe-area padding sets, so a list in the page column drew its bar at the column's edge. Custom:
/// SwiftUI has no way to move a scroll bar out of the safe area (`contentMargins(_:_:for: .scrollIndicators)` ignores
/// a negative margin, measured 2026-10-27). It sits in each row's background, so its view is in the list's scroll view
/// whichever rows are on screen; it draws nothing and takes no clicks.
private struct ScrollerAtEdge: NSViewRepresentable {
    /// The list's trailing safe-area padding, which the bar is moved back over.
    let trailingInset: CGFloat

    /// The width a legacy scroll bar takes from a list's content ("Show scroll bars: Always", or a mouse); an overlay
    /// bar takes none.
    @MainActor static var legacyWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    func makeNSView(context: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.trailingInset = trailingInset
    }

    final class Probe: NSView {
        var trailingInset: CGFloat = 0 {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        private func apply() {
            guard let scroll = enclosingScrollView, scroll.scrollerInsets.right != -trailingInset else { return }
            scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -trailingInset)
        }
    }
}

/// A group of a `PageList`'s rows under its title ("Today"): the title is the group's first row, in the form's section
/// title type, so it scrolls with the rows and draws no band. A section header floats in an inset list, and a floating
/// header drew its own fill (a grey band in dark mode, none in light) and a full-width line (qa1-review 2). No line
/// under the title or under the group's last row: the space between groups separates them, as a form's sections.
struct PageListSection<Row: Identifiable, RowView: View>: View {
    let title: String
    let rows: [Row]
    @ViewBuilder let row: (Row) -> RowView

    var body: some View {
        Section {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .selectionDisabled()
                .listRowSeparator(.hidden)
            ForEach(rows) { item in
                row(item)
                    .listRowSeparator(.hidden, edges: item.id == rows.last?.id ? .bottom : [])
            }
        }
    }
}
