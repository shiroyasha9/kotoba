import AppKit
import KotobaCore

/// Tells a development build when the release app runs (`InstallYield`). NSWorkspace posts no launch or quit
/// notification for an `LSUIElement` app, and kotoba launches as one (and stays one with "Show in Dock" off), so this
/// observes `NSWorkspace.runningApplications` with KVO, which changes on the main run loop when any app launches or
/// quits. Nothing runs at idle, and the release install observes nothing.
@MainActor
final class ReleaseAppWatcher {
    private var yield = InstallYield(isRelease: Install.isRelease)
    private var observation: NSKeyValueObservation?

    var isYielding: Bool { yield.isYielding }

    /// Calls `changed` with the new `isYielding` at each change; at once when the release app already runs. The release
    /// never gives way, so it observes nothing.
    func start(_ changed: @escaping @MainActor (Bool) -> Void) {
        guard !Install.isRelease else { return }
        observation = Self.watch(Install.releaseBundleID) { [weak self] launched, quit in
            guard let self, self.yield.releaseChanged(launched: launched, quit: quit) else { return }
            changed(self.yield.isYielding)
        }
    }

    /// Calls `changed` with the processes of `bundleID` that launched and quit: at once with the ones running, then at
    /// each change of the running apps (mostly empty lists), until the observation is released. Onboarding follows
    /// Wispr Flow with it too.
    static func watch(
        _ bundleID: String, _ changed: @escaping @MainActor (_ launched: [Int32], _ quit: [Int32]) -> Void
    ) -> NSKeyValueObservation {
        // `.initial` lists every running app; later changes list the apps that launched (new) and quit (old).
        let options: NSKeyValueObservingOptions = [.initial, .new, .old]
        return NSWorkspace.shared.observe(\.runningApplications, options: options) { _, change in
            let launched = running(change.newValue ?? [], of: bundleID).map(\.processIdentifier)
            let quit = running(change.oldValue ?? [], of: bundleID).map(\.processIdentifier)
            MainActor.assumeIsolated { changed(launched, quit) }
        }
    }

    /// The apps of `bundleID` with a process: an app with no process reports -1, and it must not count as running.
    nonisolated static func running(_ apps: [NSRunningApplication], of bundleID: String) -> [NSRunningApplication] {
        apps.filter { $0.bundleIdentifier == bundleID && $0.processIdentifier > 0 }
    }
}

extension AppDelegate {
    /// Before the hotkey tap starts, so a development build that launches beside the release app creates it disabled.
    /// The pill says why when it is quiet, after the launch work as the idle pill does; a dictation's pill and another
    /// notice keep their text and timers, and the idle pill reads the new context when they end.
    func watchReleaseApp() {
        releaseWatcher.start { [weak self] isYielding in
            self?.hotkeys.setEnabled(!isYielding)
            Task { [weak self] in
                guard let self else { return }
                if isYielding {
                    indicator.showWhenQuiet(.yieldsToRelease)
                }
                indicator.contextChanged(statusContext)
                if !isYielding {
                    indicator.end(.yieldsToRelease)
                }
            }
        }
    }
}
