import SwiftUI

// The main window's visual system for 0.5.0 (docs/research/ui-redesign.md, "Window"; CODING_STANDARDS.md, "Pages"). A
// page is a grouped form in a centred column (`PageForm`); a settings page opens with a header card (`PageHeader`).
// Cards are the form's sections and rows are its rows (`PageRow`), so heights, paddings, corner radii and text colours
// are the system's. Symbols take the font of the text next to them. The few sizes Apple gives no value for are in
// `PageMetrics`.

/// A page of the main window: a grouped form whose sections stay in a centred column at most `PageMetrics.columnWidth`
/// wide. The margins are the scroll view's content margins, so the scroll bar stays at the window's edge and the whole
/// width scrolls.
struct PageForm<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var width: CGFloat = 0

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .contentMargins(.horizontal, sideMargin, for: .scrollContent)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    /// Nil keeps the form's own margin until the window is wider than the column.
    private var sideMargin: CGFloat? {
        width > PageMetrics.columnWidth ? (width - PageMetrics.columnWidth) / 2 : nil
    }
}

/// The card that opens a settings page, as in System Settings' Screen Time: the page's sidebar tile and name, one line
/// on what the page does, and a link when there is more to learn. The tile and name come from the page's `PaneID`, so
/// a header never drifts from its sidebar row. Put it in the page's first `Section`.
struct PageHeader: View {
    let page: PaneID
    let summary: String
    /// "Learn More…" where there is more to learn; most pages have none (review-window.md T10).
    var link: (title: String, action: () -> Void)?

    var body: some View {
        TileLabel(
            title: page.title, subtitle: summary,
            icon: {
                SymbolTile(systemImage: page.systemImage, tint: page.tint, side: PageMetrics.headerTileSide)
            },
            extra: {
                if let link {
                    Button(link.title, action: link.action)
                        .buttonStyle(.link)
                }
            })
    }
}

/// A page's read failed: one row in the form's own type, with the button that reads again, in place of what the page
/// shows (review-window.md 8: a pane-sized empty view in a card looked out of place).
struct LoadFailedRow: View {
    let retry: @MainActor () -> Void

    var body: some View {
        PageRow(title: StatusText.historyReadFailedTitle, subtitle: StatusText.historyReadFailedMessage) {
            SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
        } trailing: {
            Button("Try Again", action: retry)
        }
    }
}

/// A sheet over a page, such as a page's "Advanced…": its sections in a grouped form, and Done at the bottom, as System
/// Settings' sheets. It is the page column's width and as tall as its sections, between `PageMetrics.sheetHeights`
/// (the smallest window's height at most, so it fits every window); longer content scrolls.
struct PageSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    /// The form's content height: a form takes all the height it is offered, so the sheet asks for its content's.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
            contentHeight = height
        }
        .navigationTitle(title)
        .frame(
            width: PageMetrics.sheetWidth,
            height: min(max(contentHeight, PageMetrics.sheetHeights.lowerBound), PageMetrics.sheetHeights.upperBound)
        )
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

extension Duration {
    /// A duration as Screen Time writes it, in the system formatter's narrow units: "14h 20m", and "42s" under a minute
    /// (review-window.md T8).
    var pageText: String {
        self < .seconds(60)
            ? formatted(.units(allowed: [.seconds], width: .narrow))
            : formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
}
