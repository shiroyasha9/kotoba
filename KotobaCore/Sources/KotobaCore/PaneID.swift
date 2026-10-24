import Foundation

/// The main window's pages, in sidebar order: the app's own pages first, then the settings, where the pages a new user
/// needs first come first (docs/research/ui-redesign.md, "Page map"). Their titles, symbols and tints are the App's
/// (`App/MainWindow.swift`).
///
/// The raw value is stored (the pane the window showed last), so a case keeps its name when its page is renamed: `modes`
/// is the Cleanup page (Cleanup, Rewrite and App styles).
public enum PaneID: String, Hashable, CaseIterable, Sendable {
    case home
    case history
    case activity
    case shortcuts
    case speech
    case dictionary
    case modes
    case microphones
    case general

    /// The page for `saved`, the raw value stored when the window last showed a page; nil when there is none or this
    /// build has no such page. 0.4's Insights and Usage are Activity now (review-upgrade, 2026-10-25).
    public init?(saved: String?) {
        switch saved {
        case "insights", "usage": self = .activity
        default:
            guard let page = saved.flatMap(Self.init(rawValue:)) else { return nil }
            self = page
        }
    }

    /// The sidebar's second group, under the "Settings" header.
    public var isSetting: Bool {
        switch self {
        case .home, .history, .activity: false
        case .shortcuts, .speech, .dictionary, .modes, .microphones, .general: true
        }
    }

    /// The pages with a search field: Edit > Find… (⌘F) puts the cursor in it. In the other pages Find stays off.
    public var hasSearch: Bool { self == .dictionary || self == .history }
}
