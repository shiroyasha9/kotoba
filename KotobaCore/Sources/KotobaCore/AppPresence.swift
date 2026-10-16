/// Where kotoba shows itself (story 35): the Dock and the menu bar, which window a launch opens, and the Dock badge.
///
/// "Show in Dock" on (the default, also for an update): always in the Dock. Off (owner, 2026-10-16): in the Dock only
/// while one of kotoba's windows is open, from the click that asks for it until the last one closes; the indicator
/// pill and the menus never count. The menu bar icon has its own setting, and the two cannot both be off, so the owner
/// can always reach kotoba.
public struct AppPresence: Sendable, Equatable {
    public enum Launch: Sendable {
        /// Finder, Spotlight, the Dock, `open`.
        case user
        /// The login item.
        case login
    }

    public enum LaunchWindow: Sendable {
        case onboarding
        case main
    }

    public private(set) var showsInDock: Bool
    public private(set) var showsMenuBarIcon: Bool
    /// kotoba's windows that are shown and not closed yet; a minimized window is open.
    private var openWindows: Set<ObjectIdentifier> = []
    /// A click asked for a window and activated kotoba; the window is not shown yet. AppKit shows the menu bar of a
    /// Dock app only for an activation that comes after the switch, so kotoba enters the Dock at the request.
    private var isWindowRequested = false

    /// Both off (an edit of the defaults by hand) shows the menu bar icon.
    public init(showsInDock: Bool, showsMenuBarIcon: Bool) {
        self.showsInDock = showsInDock
        self.showsMenuBarIcon = showsMenuBarIcon || !showsInDock
    }

    public var isInDock: Bool { showsInDock || isWindowRequested || !openWindows.isEmpty }

    /// The Dock icon can go while the menu bar icon shows, and the other way round.
    public var canHideDockIcon: Bool { showsMenuBarIcon }
    public var canHideMenuBarIcon: Bool { showsInDock }

    /// A change that would leave neither icon is refused.
    public mutating func setShowsInDock(_ isOn: Bool) {
        guard isOn || canHideDockIcon else { return }
        showsInDock = isOn
    }

    public mutating func setShowsMenuBarIcon(_ isOn: Bool) {
        guard isOn || canHideMenuBarIcon else { return }
        showsMenuBarIcon = isOn
    }

    /// The click that opens a window, before the window is built.
    public mutating func windowRequested() {
        isWindowRequested = true
    }

    /// `id` is the window's identity; showing it again changes nothing.
    public mutating func windowOpened(_ id: ObjectIdentifier) {
        isWindowRequested = false
        openWindows.insert(id)
    }

    public mutating func windowClosed(_ id: ObjectIdentifier) {
        openWindows.remove(id)
    }

    /// kotoba is no longer the active app: a request that showed no tracked window (the About panel) ends.
    public mutating func deactivated() {
        isWindowRequested = false
    }

    /// Onboarding at every launch until it is done, as before: kotoba cannot dictate without it. Then the main window
    /// for a launch by the owner, and none at login.
    public static func window(at launch: Launch, needsOnboarding: Bool) -> LaunchWindow? {
        if needsOnboarding { return .onboarding }
        return launch == .user ? .main : nil
    }

    /// The Dock badge: the number of dictations that wait for a retry; none at 0.
    public static func badge(waiting count: Int) -> String? {
        count > 0 ? String(count) : nil
    }
}
