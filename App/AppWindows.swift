import AppKit
import KotobaCore

/// The app delegate's windows and Dock icon (story 35): the launch window, reopen and the Dock menu.
extension AppDelegate {
    /// The launch's window: onboarding at once; the main window once `dictionaryRead` ends, so it has its Dictionary
    /// pane; none at login.
    func openWindow(at launch: AppPresence.Launch, after dictionaryRead: Task<Void, Never>) {
        switch AppPresence.window(at: launch, needsOnboarding: setup.needsOnboarding) {
        case .onboarding:
            setup.showOnboarding()
            // The Wispr Flow step needs the dictionary, which is read after the window opens.
            Task {
                await dictionaryRead.value
                setup.dictionaryOpened()
            }
        case .main:
            Task {
                await dictionaryRead.value
                mainWindow.show()
            }
        case nil:
            break
        }
    }

    /// A Dock click or opening kotoba again while it runs (Spotlight, Raycast, Finder, `open -a`) shows the main window
    /// in front, or onboarding while it goes on, minimised too (`AppPresence.reopenWindow`). macOS sends the reopen with
    /// an activation, and with no window kotoba would be active and show nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showApp()
        return false
    }

    /// A reopen, "Open kotoba…" (the menu bar and Dock menus) and "Settings…" (`settings`, the app menu): onboarding
    /// while it goes on (owner QA 2, R5), else the main window.
    func showApp(settings: Bool = false) {
        switch setup.reopenWindow {
        case .onboarding: setup.showOnboarding()
        case .main where settings: mainWindow.showSettings()
        case .main: mainWindow.show()
        }
    }

    /// The Dock icon's right-click menu: the menu bar menu's items, built from the same model on each click.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menuModel().build(into: menu, target: self, for: .dock)
        return menu
    }
}
