import AppKit
import KotobaCore

/// The screens the indicator pill picks from: the one the owner works on, and the one with the pointer.
extension NSScreen {
    /// The screen that holds most of the frontmost app's front window, else the screen with the pointer.
    static var focused: NSScreen? {
        let screens = Self.screens
        if let window = frontmostWindowFrame(),
            let index = IndicatorPlacement.screenIndex(holding: window, among: screens.map { ScreenRect($0.frame) })
        {
            return screens[index]
        }
        return withPointer
    }

    static var withPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return Self.screens.first { $0.frame.contains(mouse) } ?? Self.main
    }

    private static func frontmostWindowFrame() -> ScreenRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let primary = Self.screens.first,
            let bounds = FrontWindow.info(of: pid)?[kCGWindowBounds as String] as? [String: Any],
            let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        return IndicatorPlacement.screenRect(
            fromWindowServer: ScreenRect(rect), primaryScreenHeight: primary.frame.height)
    }
}

/// An app's front window as the window server lists it (front to back): its number and bounds need no Screen
/// Recording permission. One read: about 0.24 ms p50, 0.44 ms p90 with 14 windows on screen (`swiftc -O` probe,
/// 2026-10-17); the first in a process takes about 20 ms.
enum FrontWindow {
    /// `pid`'s frontmost window at the normal level; nil when it has none on screen.
    static func info(of pid: pid_t) -> [String: Any]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return windows.first {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
        }
    }
}
