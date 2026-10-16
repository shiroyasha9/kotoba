import AppKit
import KotobaCore

/// A second copy of this install (the installed app and one opened from the DMG or an old download) hands over to the
/// copy that runs (`SingleInstance`) and quits. `main.swift` asks before `AppDelegate` exists, so a copy that hands
/// over starts nothing: no Sparkle, Keychain read, hotkey tap, history or Dock icon. It runs the app only to give the
/// running copy the owner's activation and ask it for its main window, as a second open from Finder or the Dock does.
@MainActor
final class CopyHandOver: NSObject, NSApplicationDelegate {
    private let running: NSRunningApplication

    /// The running copy this launch hands over to, or nil when this copy keeps running. One Launch Services query for
    /// this bundle id and a sysctl per copy: 0.6-2.3 ms cold (`swiftc -O` probe, 2026-10-17; asking NSWorkspace for
    /// every app took 4.5-8.6 ms); nothing observes later.
    static func runningCopy() -> NSRunningApplication? {
        let current = NSRunningApplication.current
        let all = NSRunningApplication.runningApplications(withBundleIdentifier: Install.bundleID)
        let others = ReleaseAppWatcher.running(all, of: Install.bundleID)
            .filter { $0.processIdentifier != current.processIdentifier && !$0.isTerminated }
        guard let first = SingleInstance.handOver(from: copy(current), others: others.map(copy)) else { return nil }
        return others.first { $0.processIdentifier == first.processID }
    }

    init(to running: NSRunningApplication) {
        self.running = running
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("Another copy of this install runs (pid \(self.running.processIdentifier)); this copy quits")
        // The owner's open gave this copy the activation; the running copy takes it to show its window.
        NSApp.yieldActivation(to: running)
        guard let url = running.bundleURL else {
            running.activate()
            NSApp.terminate(nil)
            return
        }
        // Opening the running copy's own bundle reaches that process with a reopen (`applicationShouldHandleReopen`).
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Log.app.error("Cannot bring the running copy to the front: \(error)")
            }
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// The kernel's start time comes first: Launch Services has no `launchDate` for a copy started from a terminal,
    /// and every copy must order the others alike.
    private static func copy(_ app: NSRunningApplication) -> SingleInstance.Copy {
        SingleInstance.Copy(
            processID: app.processIdentifier, launchedAt: startTime(of: app.processIdentifier) ?? app.launchDate)
    }

    private static func startTime(of processID: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
