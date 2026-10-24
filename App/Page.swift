import AppKit
import SwiftUI

// The main window's visual system for 0.5.0 (docs/research/ui-redesign.md, "Window"). A page is a grouped form in a
// centred column, opened by a header card. Cards are the form's sections and rows are its rows, so heights, paddings,
// corner radii and text colours are the system's. Symbols take the font of the text next to them. The few sizes Apple
// gives no value for live in `PageMetrics`, each with its source.

/// The sizes the system gives no value for (Apple publishes no tile, keycap or column size: HIG Sidebars, WWDC25 310),
/// each with where it comes from. Every other size in a page comes from a system style.
enum PageMetrics {
    // MARK: Window

    /// The window's first size: room for History's rows and Home's figures next to the sidebar (owner, 2026-10-16:
    /// open big by default). The same as `MainWindow.defaultSize` today.
    static let defaultWindowSize = CGSize(width: 960, height: 640)

    /// The smallest window: the sidebar and a page column with its form inset, as the main window today.
    static let minimumWindowSize = CGSize(width: 720, height: 480)

    // MARK: Page

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

    /// A header card's icon: System Settings' Accessibility and Screen Time header tiles (52 px in the 2x captures,
    /// refs/apple/system-settings-accessibility, owner-trial/round2/img18).
    static let headerTileSide: CGFloat = 26

    /// The icon of a row with a title and a subtitle: Screen Time's "Apps & Websites" tile (56 px in the 2x capture,
    /// owner-trial/round2/img18).
    static let rowTileSide: CGFloat = 28

    /// From a row's tile to its text: Screen Time's rows, 22 px from the tile to the title in the 2x capture
    /// (owner-trial/round2/img18), of which about 2 px is the letter's side bearing.
    static let tileTextGap: CGFloat = 10

    /// A tile's or keycap's corner as a share of its side, continuous: an app icon's shape, as System Settings' tiles
    /// (0.22 measured in the owner's capture).
    static let tileCornerRatio: CGFloat = 0.225

    /// The share of a tile that its symbol's larger side fills. Apple's tile glyphs stay within 60-70 % of the tile
    /// whatever their shape (Network's globe 28 of 40 px, Accessibility 26 of 38 px, Screen Time's header hourglass 30
    /// of 50 px in the 2x captures); one point size for every symbol made wide ones (house, chart) fill 80-88 %.
    static let tileGlyphShare: CGFloat = 0.62

    /// A keycap is as tall as two lines of body text (2 x 16 pt leading, HIG Typography), so the Title 2 key symbol
    /// reads at a glance.
    static let keycapSide: CGFloat = 32

    /// A word keycap's inset on each side ("Space"): a quarter of its side. A modifier symbol's keycap stays square.
    static let keycapInset: CGFloat = keycapSide / 4

    /// A bar chart's height: Screen Time's daily chart is about 110 pt in the owner's capture; 120 pt is the height of
    /// the Insights chart today.
    static let chartHeight: CGFloat = 120

    /// A bar's width as a share of its day's slot, as Screen Time's bars (0.57 in the owner's capture).
    static let barWidthRatio: CGFloat = 0.6

    /// A bar's corner: Screen Time rounds its bars at about a quarter of a week bar's width. Charts takes only a fixed
    /// radius, so a month's thin bar keeps it too.
    static let barCornerRadius: CGFloat = 4

    /// A chart's average line and a month's date lines: a hairline of short dashes, as Screen Time's average and
    /// Battery's time lines.
    static let dashedLine = StrokeStyle(lineWidth: 1, dash: [2, 2])

    // MARK: Snapshots

    /// A wide screen's window, where the column must stay centred.
    static let wideWindowSize = CGSize(width: 1_440, height: 900)

    /// The detail column at the default window size, for a page drawn alone.
    static let detailWidth = defaultWindowSize.width - sidebarWidth

    /// Tall enough to draw each prototype page whole.
    static let homePageHeight: CGFloat = 1_000
    static let activityPageHeight: CGFloat = 1_300
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
        TileLabel(
            title: title, subtitle: summary, icon: { icon },
            extra: {
                if let link {
                    Button(link.title, action: link.action)
                        .buttonStyle(.link)
                }
            })
    }
}

/// A row's title, its one grey subtitle and its icon, centred on both lines as in System Settings' rows. Custom:
/// SwiftUI's `Label` centres its icon on the first line only, so a two-line row's tile sat high (owner trial,
/// 2026-10-24), and a custom `LabelStyle` loses the form's subtitle style. The subtitle takes the form's own style
/// (subheadline, secondary), measured equal in the snapshot.
struct TileLabel<Icon: View, Extra: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let icon: Icon
    /// Under the subtitle: a header card's link.
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: PageMetrics.tileTextGap) {
            icon
            VStack(alignment: .leading) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                extra
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TileLabel where Extra == EmptyView {
    init(title: String, subtitle: String?, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, subtitle: subtitle, icon: icon) { EmptyView() }
    }
}

/// A symbol in white on a rounded square of a colour, as in the System Settings sidebar and Screen Time's rows. The
/// symbol keeps its weight and optical size: it is drawn at a point size, never stretched. Custom: SwiftUI has no
/// settings icon style.
struct SymbolTile: View {
    let tint: Color
    let side: CGFloat
    /// The symbol's filled form when it has one.
    private let name: String
    private let pointSize: CGFloat

    init(systemImage: String, tint: Color, side: CGFloat) {
        self.tint = tint
        self.side = side
        let filled = systemImage + ".fill"
        name = NSImage(systemSymbolName: filled, accessibilityDescription: nil) == nil ? systemImage : filled
        // Each symbol gets the point size at which its larger side fills `tileGlyphShare` of the tile, read from the
        // symbol's own bounds at a probe size, so a wide house and a narrow mic look the same size.
        let probe: CGFloat = 100
        let bounds = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: probe, weight: Self.weight))?.size
        let larger = bounds.map { max($0.width, $0.height) } ?? probe
        pointSize = probe * side * PageMetrics.tileGlyphShare / larger
    }

    /// Apple's tile glyphs are light and even; semibold looked heavy (review-window.md, 1).
    private static let weight = NSFont.Weight.medium

    var body: some View {
        Image(systemName: name)
            .font(.system(size: pointSize, weight: .medium))
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
                Image(systemName: "app.dashed").font(.system(size: side * PageMetrics.tileGlyphShare))
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
                Self.legend(key)
                    .font(.title2.weight(.medium))
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
