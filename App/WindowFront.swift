import AppKit

/// The one way kotoba brings one of its windows to the front: `activate()` first in the handler of the owner's click,
/// then `show(_:)` when the window is built.
///
/// Since macOS 14, `NSApp.activate()` is a request (cooperative activation). WindowServer grants it only while kotoba
/// holds an activation from the owner: a click on a menu item usually gives one, but not always (2026-10-16: some
/// Settings and History clicks got no activation; at launch WindowServer logs "CPS: Rejecting the request … due to
/// the activation count being 0"). Every refused request on 2026-10-16 came 90-213 ms after the click, once the window
/// was built; requests about 10 ms after the click were all granted. So kotoba asks before it builds or awaits.
///
/// An inactive app's `makeKeyAndOrderFront` puts the window behind the active app's key window, so a refused request
/// left the window behind the app the owner works in. `orderFrontRegardless` puts it in front of every app whatever
/// WindowServer decides, at the normal level: the next click in another app covers it as usual. When the request is
/// granted the window is also key; when it is refused, the owner's first click in it makes kotoba active.
///
/// Every window shown here counts as open for "Show in Dock" off (`DockAndMenuBar`): the main window, onboarding and
/// Fix Dictation. The indicator pill, the menus and the About panel do not.
@MainActor
enum WindowFront {
    /// Asks macOS to make kotoba the active app. Call it first in the handler of the click that opens a window, before
    /// the window is built and before any `await`.
    static func activate() {
        DockAndMenuBar.shared.windowRequested()
        NSApp.activate()
    }

    /// The About panel: AppKit builds and orders it, so there is no window to give `show(_:)`. It does not count as a
    /// window for "Show in Dock" off.
    static func activateForAboutPanel() {
        NSApp.activate()
    }

    /// Shows `window` in front of every app as kotoba's key window. `activate()` must come first.
    static func show(_ window: NSWindow) {
        DockAndMenuBar.shared.opened(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
