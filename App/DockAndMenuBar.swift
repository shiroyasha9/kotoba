import AppKit
import KotobaCore

/// Applies `AppPresence` (KotobaCore) to AppKit: the activation policy, the menu bar icon and the Dock badge. The only
/// caller of `setActivationPolicy` besides the snapshot run (lint `activation_policy`).
///
/// The Info.plist keeps `LSUIElement`, so every launch starts out of the Dock; `start()`, the first step of
/// `applicationDidFinishLaunching`, enters it. Switching there costs 0.5 ms and 0.25 MB, and a launch with "Show in
/// Dock" off never shows the icon (docs/research/dock-app.md). Each later change waits on its event: a setting, the
/// click that asks for a window (`WindowFront.activate`), a window shown (`WindowFront.show`) or closed, kotoba no
/// longer active. Nothing runs at idle.
@MainActor
final class DockAndMenuBar {
    static let shared = DockAndMenuBar()

    private(set) var presence = AppDefaults.presence
    private weak var statusItem: StatusBarItem?
    /// One per open window, removed when it closes.
    private var closeObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]
    private var resignObserver: (any NSObjectProtocol)?

    /// Dictations that wait for a retry, as the Dock badge. Set on each read of the queue; the tile changes only when
    /// the count does, and out of the Dock it shows nowhere: it takes the count as kotoba enters.
    var waitingCount = 0 {
        didSet {
            if waitingCount != oldValue, isInDock { showBadge() }
        }
    }

    private var isInDock: Bool { NSApp.activationPolicy() == .regular }

    private init() {}

    /// The first step of the launch, before anything builds a window or the menu bar icon.
    func start() {
        apply()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.presence.deactivated()
                self?.apply()
            }
        }
    }

    /// A login item's launch carries `keyAELaunchedAsLogInItem` in its open-application event; any other launch is the
    /// owner's (Finder, Spotlight, the Dock, `open`). Read it in `applicationDidFinishLaunching`: the event is gone
    /// after it.
    static func launch() -> AppPresence.Launch {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let isLogin =
            event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
        Log.app.info("Launched \(isLogin ? "at login" : "by the owner", privacy: .public)")
        return isLogin ? .login : .user
    }

    /// The menu bar icon, once it is built at launch: shown or hidden by the setting.
    func attach(_ item: StatusBarItem) -> StatusBarItem {
        statusItem = item
        item.isShown = presence.showsMenuBarIcon
        return item
    }

    /// "Show in Dock". Refused when the menu bar icon is hidden too.
    func setShowsInDock(_ isOn: Bool) {
        presence.setShowsInDock(isOn)
        save()
    }

    /// "Show in menu bar". Refused when the Dock icon is off too.
    func setShowsMenuBarIcon(_ isOn: Bool) {
        presence.setShowsMenuBarIcon(isOn)
        statusItem?.isShown = presence.showsMenuBarIcon
        save()
    }

    /// The click that opens a window, before `NSApp.activate()`: macOS shows a Dock app's menu bar for an activation
    /// that comes after the switch.
    func windowRequested() {
        presence.windowRequested()
        apply()
    }

    /// A kotoba window is shown; it counts until it closes.
    func opened(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        presence.windowOpened(id)
        if closeObservers[id] == nil {
            closeObservers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.closed(id) }
            }
        }
        apply()
    }

    private func closed(_ id: ObjectIdentifier) {
        if let observer = closeObservers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(observer)
        }
        presence.windowClosed(id)
        apply()
    }

    private func save() {
        AppDefaults.presence = presence
        apply()
    }

    private func apply() {
        let isInDock = presence.isInDock
        guard isInDock != self.isInDock else { return }
        NSApp.setActivationPolicy(isInDock ? .regular : .accessory)
        Log.app.info("Dock icon \(isInDock ? "shown" : "hidden", privacy: .public)")
        if isInDock { showBadge() }
    }

    private func showBadge() {
        NSApp.dockTile.badgeLabel = AppPresence.badge(waiting: waitingCount)
    }
}
