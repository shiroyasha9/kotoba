import AppKit
import KotobaCore

/// Tells a development build when the release app runs (`InstallYield`). NSWorkspace posts no launch or quit
/// notification for an `LSUIElement` app such as kotoba, so this observes `NSWorkspace.runningApplications` with KVO,
/// which changes on the main run loop when any app launches or quits. Nothing runs at idle, and the release install
/// observes nothing.
@MainActor
final class ReleaseAppWatcher {
    private var yield = InstallYield(isRelease: Install.isRelease)
    private var observation: NSKeyValueObservation?

    var isYielding: Bool { yield.isYielding }

    /// Calls `changed` with the new `isYielding` at each change; at once when the release app already runs. The release
    /// never gives way, so it observes nothing.
    func start(_ changed: @escaping @MainActor (Bool) -> Void) {
        guard !Install.isRelease else { return }
        // `.initial` lists every running app; later changes list the apps that launched (new) and quit (old).
        let options: NSKeyValueObservingOptions = [.initial, .new, .old]
        observation = NSWorkspace.shared.observe(\.runningApplications, options: options) { [weak self] _, change in
            let launched = Self.releaseProcesses(change.newValue)
            let quit = Self.releaseProcesses(change.oldValue)
            MainActor.assumeIsolated {
                guard let self, self.yield.releaseChanged(launched: launched, quit: quit) else { return }
                changed(self.yield.isYielding)
            }
        }
    }

    private nonisolated static func releaseProcesses(_ apps: [NSRunningApplication]?) -> [Int32] {
        (apps ?? []).filter { $0.bundleIdentifier == Install.releaseBundleID }.map(\.processIdentifier)
    }
}

extension AppDelegate {
    /// Before the hotkey tap starts, so a development build that launches beside the release app creates it disabled.
    /// At idle the pill says why, after the launch work as the idle pill does; a dictation's pill keeps its timers.
    func watchReleaseApp() {
        releaseWatcher.start { [weak self] isYielding in
            self?.hotkeys.setEnabled(!isYielding)
            Task { [weak self] in
                guard let self, state == .idle else { return }
                if isYielding {
                    indicator.show(.yieldsToRelease)
                }
                indicator.show(state, context: statusContext)
                if !isYielding {
                    indicator.showQuiet()
                }
            }
        }
    }
}
