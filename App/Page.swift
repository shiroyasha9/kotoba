import AppKit
import SwiftUI

// The main window's visual system for 0.5.0 (docs/research/ui-redesign.md, "Window"). A page is a grouped form in a
// centred column, opened by a header card. Cards are the form's sections and rows are its rows, so heights, paddings,
// corner radii and text colours are the system's. Symbols take the font of the text next to them. The few sizes Apple
// gives no value for live in `PageMetrics`, each with its source.

/// The sizes the system gives no value for (Apple publishes no tile, keycap or column size: HIG Sidebars, WWDC25 310),
/// each with where it comes from. Every other size in a page comes from a system style.
enum PageMetrics {
    /// The widest the content column gets; a wider window adds margin on both sides. The form keeps its own inset
    /// inside it, so sections are 520 pt wide at most: about 80 characters of body text per line (measured in the
    /// Home snapshot at 6.2 pt a character), near the usual 45-75 for reading. System Settings keeps its sections near
    /// 450 pt because its window does not grow (owner's capture).
    static let columnWidth: CGFloat = 560

    /// The sidebar's width, as System Settings' and CodeEdit's (`navigationSplitViewColumnWidth(215)`, research R9).
    static let sidebarWidth: CGFloat = 215

    /// A sidebar tile's side at each sidebar icon size (System Settings > Appearance). 20 pt is System Settings' tile
    /// at the default size, measured against the 13 pt body text beside it in the owner's capture; small and large
    /// step by the 4 pt that the system's sidebar text steps by (11, 13, 15 pt).
    static func sidebarTileSide(_ size: SidebarRowSize) -> CGFloat {
        switch size {
        case .small: 16
        case .large: 24
        default: 20
        }
    }

    /// A one-line row's icon (an app icon, a tile): the sidebar's default tile, so rows and sidebar match.
    static let lineTileSide: CGFloat = 20

    /// The icon of a row with a title and a subtitle, and of a header card: it spans both lines (16 + 14 pt leading,
    /// HIG Typography body and subheadline), as Screen Time's header tile (about 28 pt in the owner's capture).
    static let rowTileSide: CGFloat = 28

    /// A tile's or keycap's corner as a share of its side, continuous: an app icon's shape, as System Settings' tiles
    /// (0.22 measured in the owner's capture).
    static let tileCornerRatio: CGFloat = 0.225

    /// A tile symbol's point size as a share of the tile's side: System Settings' Wi-Fi glyph spans about 55 % of its
    /// tile in the owner's capture. The symbol keeps its own weight and optical size (no `.resizable()`).
    static let tileSymbolRatio: CGFloat = 0.55

    /// A keycap is as tall as two lines of body text (2 x 16 pt leading, HIG Typography), so the Title 2 key symbol
    /// reads at a glance.
    static let keycapSide: CGFloat = 32

    /// A bar chart's height: Screen Time's daily chart is about 110 pt in the owner's capture; 120 pt is the height of
    /// the Insights chart today.
    static let chartHeight: CGFloat = 120

    /// A bar's width as a share of its day's slot, as Screen Time's bars (0.57 in the owner's capture).
    static let barWidthRatio: CGFloat = 0.6

    /// A bar's corner: Screen Time rounds its bars at about a quarter of a week bar's width. Charts takes only a fixed
    /// radius, so a month's thin bar keeps it too.
    static let barCornerRadius: CGFloat = 4

    /// A chart's average line: a hairline of short dashes, as Screen Time's.
    static let averageLine = StrokeStyle(lineWidth: 1, dash: [2, 2])
}

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

/// The card that opens a page, as in System Settings' Screen Time: an icon, the page's name, one line on what the page
/// does, and a link when there is more to learn. Put it in the page's first `Section`.
struct PageHeader<Icon: View>: View {
    let title: String
    let summary: String
    var link: (title: String, action: () -> Void)?
    @ViewBuilder let icon: Icon

    var body: some View {
        Label {
            Text(title)
            Text(summary)
            if let link {
                Button(link.title, action: link.action)
                    .buttonStyle(.link)
            }
        } icon: {
            icon
        }
    }
}

/// A symbol in white on a rounded square of a colour, as in the System Settings sidebar and Screen Time's rows. The
/// symbol keeps its weight and optical size: it is drawn at a point size, never stretched. Custom: SwiftUI has no
/// settings icon style.
struct SymbolTile: View {
    let systemImage: String
    let tint: Color
    let side: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .symbolVariant(.fill)
            .font(.system(size: side * PageMetrics.tileSymbolRatio, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(tint.gradient, in: .rect(cornerRadius: side * PageMetrics.tileCornerRatio, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A sidebar tile whose side follows the owner's sidebar icon size.
struct SidebarTile: View {
    let systemImage: String
    let tint: Color
    @Environment(\.sidebarRowSize) private var rowSize

    var body: some View {
        SymbolTile(systemImage: systemImage, tint: tint, side: PageMetrics.sidebarTileSide(rowSize))
    }
}

/// An app's icon at a row's icon size; a dashed app symbol when the app is unknown.
struct AppIconView: View {
    let icon: NSImage?
    let side: CGFloat

    var body: some View {
        Group {
            if let icon {
                // An app icon is a bitmap: it scales; a symbol never does.
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").font(.system(size: side * PageMetrics.tileSymbolRatio))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// A chord drawn as keys, one keycap per key. Custom: macOS has no keycap view.
struct Keycaps: View {
    let keys: [String]

    var body: some View {
        HStack {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.title2.weight(.medium))
                    // A quarter of the side on each side: a symbol stays square, a word ("Space") grows.
                    .padding(.horizontal, PageMetrics.keycapSide / 4)
                    .frame(minWidth: PageMetrics.keycapSide, minHeight: PageMetrics.keycapSide)
                    .fixedSize()
                    .background(.fill.tertiary, in: Self.shape)
                    .overlay(Self.shape.strokeBorder(.separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " "))
    }

    private static let shape = RoundedRectangle(
        cornerRadius: PageMetrics.keycapSide * PageMetrics.tileCornerRatio, style: .continuous)
}
