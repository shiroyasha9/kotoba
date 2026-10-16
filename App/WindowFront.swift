import AppKit

/// The one way kotoba brings one of its windows to the front.
///
/// Since macOS 14, `NSApp.activate()` is a request (cooperative activation). WindowServer grants it only while kotoba
/// holds an activation from the owner: a click on a menu item usually gives one, but not always (2026-10-16: some
/// Settings and History clicks got no activation; at launch WindowServer logs "CPS: Rejecting the request … due to
/// the activation count being 0"). An inactive app's `makeKeyAndOrderFront` puts the window behind the active app's key
/// window, so a refused request left the window behind the app the owner works in. `orderFrontRegardless` puts it in
/// front of every app whatever WindowServer decides, at the normal level: the next click in another app covers it as
/// usual. When the request is granted the window is also key; when it is refused, the owner's first click in it makes
/// kotoba active.
@MainActor
enum WindowFront {
    /// Shows `window` in front of every app as kotoba's key window, and asks macOS to make kotoba the active app.
    static func show(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
