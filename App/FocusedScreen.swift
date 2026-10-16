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

    /// The window server lists windows front to back; bounds need no Screen Recording permission.
    private static func frontmostWindowFrame() -> ScreenRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let primary = Self.screens.first,
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                window[kCGWindowLayer as String] as? Int == 0,
                let bounds = window[kCGWindowBounds as String] as? [String: Any],
                let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            return IndicatorPlacement.screenRect(
                fromWindowServer: ScreenRect(rect), primaryScreenHeight: primary.frame.height)
        }
        return nil
    }
}
