import SwiftUI

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

    /// The icon of a row with a title and a subtitle, and of a header card: System Settings' Accessibility header tile
    /// (52 px in the 2x capture, refs/apple/system-settings-accessibility).
    static let rowTileSide: CGFloat = 26

    /// A tile's or keycap's corner as a share of its side, continuous: an app icon's shape, as System Settings' tiles
    /// (0.22 measured in the owner's capture).
    static let tileCornerRatio: CGFloat = 0.225

    /// A tile symbol's point size as a share of the tile's side: System Settings' Wi-Fi glyph spans about 55 % of its
    /// tile in the owner's capture. The symbol keeps its own weight and optical size (no `.resizable()`).
    static let tileSymbolRatio: CGFloat = 0.55

    /// A keycap is as tall as two lines of body text (2 x 16 pt leading, HIG Typography), so the Title 2 key symbol
    /// reads at a glance.
    static let keycapSide: CGFloat = 32

    /// A keycap's inset on each side: a quarter of its side, so a symbol stays square and a word ("Space") grows.
    static let keycapInset: CGFloat = keycapSide / 4

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

    // MARK: Snapshots

    /// A wide screen's window, where the column must stay centred.
    static let wideWindowSize = CGSize(width: 1_440, height: 900)

    /// The detail column at the default window size, for a page drawn alone.
    static let detailWidth = defaultWindowSize.width - sidebarWidth

    /// Tall enough to draw each prototype page whole.
    static let homePageHeight: CGFloat = 1_000
    static let activityPageHeight: CGFloat = 1_300
}
