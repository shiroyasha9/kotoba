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

    func showsYield(in state: DictationState) -> Bool {
        yield.showsYield(in: state)
    }

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
        // An app with no process reports -1; it must not keep the build giving way.
        (apps ?? []).filter { $0.bundleIdentifier == Install.releaseBundleID && $0.processIdentifier > 0 }
            .map(\.processIdentifier)
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

// MARK: - A second copy of this install

extension AppDelegate {
    /// True when another copy of this install runs and this one hands over to it (`SingleInstance`): it asks that copy
    /// to show its main window, as a second open from Finder or the Dock does, and quits. Call it first at launch,
    /// before the Dock icon, the history and the hotkey tap. Costs one Launch Services query at launch (about 1 ms, `swiftc -O` probe 2026-10-17); nothing observes later.
    func handOverToRunningCopy() -> Bool {
        let current = NSRunningApplication.current
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Install.bundleID)
            .filter {
                $0.processIdentifier != current.processIdentifier && $0.processIdentifier > 0 && !$0.isTerminated
            }
        guard
            let first = SingleInstance.handOver(from: Self.copy(current), others: others.map(Self.copy)),
            let running = others.first(where: { $0.processIdentifier == first.processID })
        else { return false }
        Log.app.notice("Another copy of this install runs (pid \(running.processIdentifier)); this copy quits")
        // The owner's open gave this copy the activation; the running copy takes it to show its window.
        NSApp.yieldActivation(to: running)
        guard let url = running.bundleURL else {
            running.activate()
            NSApp.terminate(nil)
            return true
        }
        // Opening the running copy's own bundle reaches that process with a reopen (`applicationShouldHandleReopen`).
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.app.error("Cannot bring the running copy to the front: \(error)")
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
        return true
    }

    private static func copy(_ app: NSRunningApplication) -> SingleInstance.Copy {
        SingleInstance.Copy(processID: app.processIdentifier, launchedAt: app.launchDate)
    }
}
