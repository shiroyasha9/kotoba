import AppKit

// Debug builds only: the release never takes snapshots, and linking ScreenCaptureKit there would load 25 more images
// (about 0.2 MB) at every launch.
#if DEBUG
    import ScreenCaptureKit
#endif

/// How `Snapshots` gets its images: the window server's own image of a window that is never ordered on screen, drawn as
/// the active app's key window.
@MainActor
enum SnapshotCapture {
    /// Gives the sidebar list the focus, as in the open window: its selected row draws in the accent color, not grey.
    static func focusSidebar(in window: NSWindow) {
        if let list = sidebarList(in: window.contentView) {
            window.makeFirstResponder(list)
        }
    }

    private static func sidebarList(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let list = view as? NSTableView, list.effectiveStyle == .sourceList {
            return list
        }
        return view.subviews.lazy.compactMap { sidebarList(in: $0) }.first
    }

    /// Why this run cannot capture, or nil. Checked before the first capture, so a run never writes a flat image instead.
    static func problem() -> String? {
        #if DEBUG
            CGPreflightScreenCaptureAccess()
                ? nil
                : "\(responsibleApp) needs Screen Recording (System Settings > Privacy & Security > Screen Recording); "
                    + "turn it on and run again"
        #else
            "snapshots need a Debug build (make snapshots)"
        #endif
    }

    /// The app that macOS asks Screen Recording of for this run: the first app among the parent processes, the terminal
    /// that runs `make`.
    private static var responsibleApp: String {
        var pid = getppid()
        while pid > 1 {
            if let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
                return name
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var query = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&query, u_int(query.count), &info, &size, nil, 0) == 0 else { break }
            pid = info.kp_eproc.e_ppid
        }
        return "The app that runs make"
    }

    /// Every window draws as the active app's key window (colored traffic lights, "on" switches, default buttons and
    /// sidebar labels as in use), not as AppKit draws a window that never became key. Custom: AppKit has no public API
    /// for it; these are AppKit's own two getters (not in its headers), replaced for the snapshot run only. Returns a
    /// problem when AppKit no longer has one, so the images never go back to inactive unnoticed. Debug builds only, as
    /// the capture; `Snapshots` calls it only in a `--snapshots` run.
    static func drawWindowsAsActive() -> String? {
        #if DEBUG
            let isActive: @convention(block) (NSWindow) -> Bool = { _ in true }
            for name in ["hasKeyAppearance", "_hasActiveAppearanceIgnoringKeyFocus"] {
                guard let method = class_getInstanceMethod(NSWindow.self, NSSelectorFromString(name)),
                    let types = method_getTypeEncoding(method), String(cString: types).hasPrefix("B")
                else {
                    return "AppKit has no Bool -[NSWindow \(name)], so windows cannot draw as active"
                }
                method_setImplementation(method, imp_implementationWithBlock(isActive))
            }
            return nil
        #else
            "snapshots need a Debug build (make snapshots)"
        #endif
    }

    /// The window as the window server composites it. A window that is never ordered in is captured on its own
    /// (`desktopIndependentWindow`), so nothing shows on screen. About half of new windows are not yet known to the
    /// capture at the first try (error -3812, invalid parameter); a run loop turn before the next try is mostly
    /// enough, but a full run also saw two failures in a row, so it tries up to 5 times.
    static func image(of window: NSWindow, scale: CGFloat) throws -> CGImage {
        #if DEBUG
            for _ in 1..<5 {
                do {
                    return try captureOnce(window, scale: scale)
                } catch SCStreamError.invalidParameter {
                    CFRunLoopRunInMode(.defaultMode, 0.01, true)
                }
            }
            return try captureOnce(window, scale: scale)
        #else
            throw CaptureFailure.releaseBuild
        #endif
    }

    #if DEBUG
        private static func captureOnce(_ window: NSWindow, scale: CGFloat) throws -> CGImage {
            window.displayIfNeeded()
            CATransaction.flush()
            let id = CGWindowID(window.windowNumber)
            return try wait {
                let content = try await SCShareableContent.currentProcess
                guard let listed = content.windows.first(where: { $0.windowID == id }) else {
                    throw CaptureFailure.notListed(id)
                }
                let filter = SCContentFilter(desktopIndependentWindow: listed)
                let configuration = SCStreamConfiguration()
                configuration.width = Int((filter.contentRect.width * scale).rounded())
                configuration.height = Int((filter.contentRect.height * scale).rounded())
                // With the cursor, the capture of a window that is not on screen fails (-3811).
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                configuration.colorSpaceName = CGColorSpace.sRGB
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            }
        }

        /// Runs `operation` and turns the main run loop until it ends, so the pass stays synchronous and `settle()`
        /// still works inside it. The operation's end stops the run loop turn that waits for it; the bound stops a
        /// capture that never answers.
        private static func wait<T>(for operation: @escaping @MainActor () async throws -> T) throws -> T {
            let outcome = Outcome<T>()
            Task {
                do {
                    outcome.result = .success(try await operation())
                } catch {
                    outcome.result = .failure(error)
                }
                CFRunLoopStop(CFRunLoopGetMain())
            }
            let deadline = Date.now.addingTimeInterval(10)
            while outcome.result == nil, Date.now < deadline {
                CFRunLoopRunInMode(.defaultMode, deadline.timeIntervalSinceNow, false)
            }
            guard let result = outcome.result else { throw CaptureFailure.timedOut }
            return try result.get()
        }

        @MainActor private final class Outcome<T> {
            var result: Result<T, any Error>?
        }
    #endif

    private enum CaptureFailure: Error {
        /// The capture does not list the window: it has no window server window (a window made with `defer: true`).
        case notListed(CGWindowID)
        case timedOut
        case releaseBuild
    }
}
