import AppKit

/// Reports each mouse-down (left, right or other) to the hotkey classifier, so a ⌘-click or ⌥-drag during a press drops
/// that press. AppKit event monitors only observe: no click waits for kotoba, and mouse events need no permission
/// (NSEvent.h: only key events need Accessibility). The global monitor sees clicks in other apps, the local one clicks
/// in kotoba's own windows. A click on the indicator pill is left out: it is a chord tap of its own (`HotkeyTap.sendTap`).
@MainActor
final class MouseDownMonitors {
    /// `HotkeyTap` sets it.
    var onMouseDown: (@Sendable () -> Void)?
    /// A click in another app, which can move the insertion point there; `HotkeyTap` counts it.
    var onOtherAppMouseDown: (@Sendable () -> Void)?
    /// Whether a window is the indicator pill's; the app sets it.
    var isPillWindow: (NSWindow?) -> Bool = { _ in false }
    private var monitors: [Any] = []

    /// On while the hotkey tap runs, is enabled and no shortcut recorder listens.
    func setOn(_ isOn: Bool) {
        guard isOn == monitors.isEmpty else { return }
        guard isOn else {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            return
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onOtherAppMouseDown?()
                self?.onMouseDown?()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let window = event.window
            MainActor.assumeIsolated {
                guard let self, !self.isPillWindow(window) else { return }
                self.onMouseDown?()
            }
            return event
        }
        monitors = [global, local].compactMap(\.self)
    }
}
