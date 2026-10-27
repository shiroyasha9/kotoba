import AppKit
import SwiftUI

// The main window's design values (docs/research/ui-redesign.md, "Window"). Every other size in a page comes from a
// system style; lint keeps numbers out of layout code everywhere else in `App/` (CODING_STANDARDS.md, "Pages").

extension Color {
    /// kotoba's brand colour, the icon's coral caret (App/Assets.xcassets/Brand, light and dark): the charts and the pill
    /// bars, always. Selection, buttons and switches keep the user's accent; the asset is also the app's accent colour
    /// (`NSAccentColorName`), which macOS uses only while the user's accent is Multicolor.
    static let brand = Color("Brand")

    /// A chart's average line and its "avg", in their own colour as Screen Time's, so the line does not read as a grid
    /// line (owner QA 1, Q10). The system green, apart from the brand coral of the bars.
    static let chartAverage = Color.green
}

/// The sizes the system gives no value for (Apple publishes no tile, keycap or column size: HIG Sidebars, WWDC25 310),
/// each with where it comes from.
enum PageMetrics {
    // MARK: Window

    /// The window's first size: room for History's rows and Home's figures next to the sidebar (owner, 2026-10-16:
    /// open big by default).
    static let defaultWindowSize = CGSize(width: 960, height: 640)

    /// The smallest window: the sidebar and a page column with its form inset. The height is the area under the
    /// toolbar (the content's minimum height), so the smallest window's frame is the toolbar's 52 pt taller: 532 pt
    /// (measured 2026-10-25). `defaultWindowSize` is the whole content, toolbar included. A framed snapshot asked for
    /// this size fails its fit check for that reason; nothing in the window is cut off.
    static let minimumWindowSize = CGSize(width: 720, height: 480)

    /// The widest window: the sidebar and a detail column one and a half columns wide, so the page column fills at
    /// least two thirds of it and never floats in blank space (review-window.md T9: at 1,440 pt a 520 pt column left
    /// 388 pt blank on each side). The height stays free.
    static let maximumWindowWidth = sidebarWidth + columnWidth * 3 / 2

    /// The sidebar's width, as System Settings' and CodeEdit's (`navigationSplitViewColumnWidth(215)`, research R9).
    static let sidebarWidth: CGFloat = 215

    /// A page's sheet ("Advanced…"): the page column's width; as tall as its content, from half the smallest window's
    /// height (a short sheet still reads as a sheet) to the smallest window's height, so it fits every window.
    static let sheetWidth = columnWidth
    static let sheetHeights = minimumWindowSize.height / 2...minimumWindowSize.height

    // MARK: Page

    /// The most a `PageList`'s pinned cards take: half the smallest window, so its rows always have room.
    static let pinnedMaxHeight = minimumWindowSize.height / 2

    /// A `PageList`'s rows in from the list's sides, so the selection runs from card edge to card edge: the form's
    /// section inset (`formInset`, 20 pt) less the 10 pt an inset list keeps around its selection (measured in the
    /// framed History snapshot, 2026-10-25).
    static let listSideInset: CGFloat = 10

    /// A grouped form's row inset on each side: the text column of a card with no icons is this far in from the card's
    /// edge (measured in the Microphone snapshot, 2026-10-25). A list that fills its row puts the row lines here.
    static let formRowInset: CGFloat = 10

    /// A `PageList` row's content in from its selection, so it starts in the cards' text column: a card's row padding
    /// (`formRowInset`) less the 6 pt an inset list row keeps. Measured: a row's text and a card's text start 0.5 pt apart in the
    /// framed History snapshot.
    static let listRowInset = formRowInset - 6

    /// The widest the content column gets; a wider window adds margin on both sides. The form keeps its own inset
    /// inside it, so sections are 520 pt wide at most: about 80 characters of body text per line (measured in the
    /// Home snapshot at 6.2 pt a character), near the usual 45-75 for reading. System Settings keeps its sections near
    /// 450 pt because its window does not grow (owner's capture).
    static let columnWidth: CGFloat = 560

    /// The margin on each side of the page column in a page `width` wide; none until the page is wider than the column.
    static func columnMargin(in width: CGFloat) -> CGFloat {
        max(0, (width - columnWidth) / 2)
    }

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

    /// A header card's icon: System Settings' Accessibility and Screen Time header tiles (52 px in the 2x captures,
    /// refs/apple/system-settings-accessibility, owner-trial/round2/img18).
    static let headerTileSide: CGFloat = 26

    /// A row's icon (an app icon, a tile) and the page's one icon column: Screen Time's "Apps & Websites" tile (56 px in
    /// the 2x capture, owner-trial/round2/img18). One-line rows use it too, as Screen Time's do.
    static let rowTileSide: CGFloat = 28

    /// From a row's tile to its text: Screen Time's rows, 22 px from the tile to the title in the 2x capture
    /// (owner-trial/round2/img18), of which about 2 px is the letter's side bearing.
    static let tileTextGap: CGFloat = 10

    /// The least space between a row's text and its trailing content (a value, a check, a button): System Settings
    /// keeps 16 pt or more; the stack's own 8 pt let a wrapped subtitle end 10 pt from a choice's check (qa1-review).
    static let rowTrailingGap: CGFloat = 16

    /// A tile's or keycap's corner as a share of its side, continuous: an app icon's shape, as System Settings' tiles
    /// (0.22 measured in the owner's capture).
    static let tileCornerRatio: CGFloat = 0.225

    /// The share of a tile that its symbol's larger side fills. Apple's tile glyphs stay within 60-70 % of the tile
    /// whatever their shape (Network's globe 28 of 40 px, Accessibility 26 of 38 px, Screen Time's header hourglass 30
    /// of 50 px in the 2x captures); one point size for every symbol made wide ones (house, chart) fill 80-88 %.
    static let tileGlyphShare: CGFloat = 0.62

    /// A tile's soft ring, as a share of its side: Apple's sidebar tiles sit in a shadow that fades over 2 px above the
    /// tile and 4 px under it, darkest (#cdcccc on #eeedec) at the tile's edge, in the 2x capture
    /// (refs/apple/system-settings-general-sidebar-rows, a 40 px tile). The system shadow's blur radius and its drop;
    /// measured in the sidebar snapshot: 3 px above, 4 px under, #cdcdcd at the side as Apple's.
    static let tileShadowRadiusRatio: CGFloat = 0.05
    static let tileShadowDropRatio: CGFloat = 0.0125

    /// A tile's top and bottom rim: one device pixel about 8 % lighter than the fill (#139aff over #0190ff in the same
    /// capture), the highlight of an app icon's edge.
    static let tileRimOpacity = 0.08

    /// A keycap is as tall as a regular push button, read from AppKit at launch (owner, 2026-10-24: 32 pt keycaps were
    /// "comically huge"), so it follows the system's control metrics.
    @MainActor static let keycapSide: CGFloat = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.bezelStyle = .push
        button.controlSize = .regular
        return button.intrinsicContentSize.height
    }()

    /// A word keycap's inset on each side ("Space"): a quarter of its side. A modifier symbol's keycap stays square.
    @MainActor static var keycapInset: CGFloat { keycapSide / 4 }

    // MARK: Charts

    /// A bar chart's height: Screen Time's daily chart is about 110 pt in the owner's capture; 120 pt is the height of
    /// the 0.4 Insights chart.
    static let chartHeight: CGFloat = 120

    /// A bar's width as a share of its day's slot, as Screen Time's bars (0.57 in the owner's capture).
    static let barWidthRatio: CGFloat = 0.6

    /// A bar's corner, all four as Screen Time's (review-window.md T6): about a quarter of a week bar's width
    /// (`barCornerShare`), and never more.
    static let barCornerRadius: CGFloat = 4
    static let barCornerShare: CGFloat = 0.25

    /// Home's week bar at most this share of its plot's height wide: the plot beside the today headline is about 30 pt
    /// tall, and a bar 0.6 of its day wide (24 pt) read as a square (qa1-review 3). A third keeps the tallest day at least three
    /// times as tall as wide, as Activity's tallest bars are.
    static let weekBarShare: CGFloat = 1 / 3

    /// Home's week: from the bars' base line to the top of a day initial's capitals, as Swift Charts drew it (14 px at 2x
    /// in the 0.5.0 Home snapshot), less the space the text frame keeps above its capitals.
    static let weekLabelGap: CGFloat = 4

    /// A chart's average line and a month's date lines: a hairline of short dashes, as Screen Time's average and
    /// Battery's time lines.
    static let dashedLine = StrokeStyle(lineWidth: 1, dash: [2, 2])

    // MARK: Separate windows

    /// A grouped form's side inset to its sections: the section edge at 40 px in the 2x Fix Last Dictation snapshot.
    /// Content outside a form that lines up with its cards (a window's button row under its form, onboarding's step
    /// heading and footer) takes it.
    static let formInset: CGFloat = 20

    /// The onboarding window: the page column's width and the main window's first height, so it fits a 1280×800 screen
    /// with the menu bar and the Dock.
    static let onboardingWindowSize = CGSize(width: columnWidth, height: defaultWindowSize.height)

    /// The app icon on onboarding's Welcome step: Journal's and Freeform's welcome sheets draw theirs at about 68 pt
    /// (refs/apple/journal-welcome-light, freeform-welcome-light).
    static let welcomeIconSide: CGFloat = 64

    /// The Fix Last Dictation window's width, and the most its form grows before it scrolls (the window fits its
    /// content, so a long dictation with many words to learn does not run off a small screen).
    static let fixWindowWidth: CGFloat = 480
    static let fixFormMaxHeight: CGFloat = 440

    /// The Fix window's text editor at its smallest: about four lines of body text with the editor's insets.
    static let editorMinHeight: CGFloat = 100
}
