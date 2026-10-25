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

    /// A Core Animation animation that has not ended in the window's layers, or nil: the window server would draw it at
    /// its current frame. A repeating one (a spinner) never ends and is left out. SwiftUI animates in process, one
    /// update per frame, so its animations are not listed here.
    static func runningAnimation(in window: NSWindow) -> String? {
        (window.contentView?.superview ?? window.contentView).flatMap(runningAnimation(in:))
    }

    /// Ends every Core Animation animation in the window that has an end, so the capture draws each layer as it rests:
    /// a snapshot run shows no animation. A control that animates in its first value (Microphone's input level gauge,
    /// 250 ms) was still moving when a capture came less than 250 ms after its layout, and failed the run under load.
    /// A repeating one (a spinner) is left as it is.
    static func endAnimations(in window: NSWindow) {
        guard let view = window.contentView?.superview ?? window.contentView else { return }
        endAnimations(in: view)
        CATransaction.flush()
    }

    private static func endAnimations(in view: NSView) {
        guard let layer = view.layer else {
            view.subviews.forEach(endAnimations(in:))
            return
        }
        endAnimations(in: layer)
    }

    private static func endAnimations(in layer: CALayer) {
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key), animation.repeatCount.isFinite,
                animation.repeatDuration.isFinite
            else { continue }
            layer.removeAnimation(forKey: key)
        }
        layer.sublayers?.forEach(endAnimations(in:))
    }

    /// From each top layer-backed view down: a borderless window's frame view has no layer of its own.
    private static func runningAnimation(in view: NSView) -> String? {
        if let layer = view.layer {
            return runningAnimation(in: layer)
        }
        return view.subviews.lazy.compactMap { runningAnimation(in: $0) }.first
    }

    private static func runningAnimation(in layer: CALayer) -> String? {
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key), animation.repeatCount.isFinite,
                animation.repeatDuration.isFinite
            else { continue }
            // The nearest view up the layer tree names where it runs; a plain sublayer has no delegate of its own.
            let owner = sequence(first: layer, next: \.superlayer).lazy.compactMap(\.delegate).first
            let path = (animation as? CAPropertyAnimation)?.keyPath ?? "\(type(of: animation))"
            let left = animation.beginTime + animation.duration - layer.convertTime(CACurrentMediaTime(), from: nil)
            return "\(type(of: layer)) key \(key), \(path), in \(owner.map { "\(type(of: $0))" } ?? "no view"), "
                + "\(Int(animation.duration * 1000)) ms long, \(Int(left * 1000)) ms left"
        }
        return (layer.sublayers ?? []).lazy.compactMap { runningAnimation(in: $0) }.first
    }

    /// Why this run cannot capture, or nil. A missing Screen Recording grant shows as the capture's own error
    /// (`CaptureFailure.noScreenRecording`): `CGPreflightScreenCaptureAccess()` said false in 9 of 20 runs under CPU load
    /// with the grant on (2026-10-25).
    static func problem() -> String? {
        #if DEBUG
            nil
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
    /// (`desktopIndependentWindow`), so nothing shows on screen. With a `shadowMargin`, the image is that much wider
    /// and taller on each side and has the window's shadow: the capture puts the window and its shadow at the image's
    /// top left, the window at `scale` (measured 2026-10-25: a 900 x 560 pt window, its shadow 21 pt on each side,
    /// 16 pt above and 28 pt under it).
    static func image(of window: NSWindow, scale: CGFloat, shadowMargin: CGFloat = 0) throws -> CGImage {
        #if DEBUG
            do {
                return try captureOnce(window, scale: scale, shadowMargin: shadowMargin)
            } catch SCStreamError.userDeclined {
                throw CaptureFailure.noScreenRecording(responsibleApp)
            }
        #else
            throw CaptureFailure.releaseBuild
        #endif
    }

    #if DEBUG
        private static func captureOnce(_ window: NSWindow, scale: CGFloat, shadowMargin: CGFloat) throws -> CGImage {
            window.displayIfNeeded()
            CATransaction.flush()
            let id = CGWindowID(window.windowNumber)
            let size = window.frame.size
            // AppKit sends a window's changes to the window server without waiting, and ScreenCaptureKit reads the
            // window list over another connection: under load it listed a new window with a zero frame, and the
            // capture of that zero size failed with -3812 (invalid parameter). This window list call waits for the
            // window server's answer on the app's own connection, so the window server has applied every earlier
            // change when it returns (2026-10-25 spike: 0 of 120 new windows listed at zero with it under load, 89 of
            // 120 without). Its answer is empty: the list leaves out a window never ordered in.
            _ = CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
            return try wait {
                let content = try await SCShareableContent.currentProcess
                guard let listed = content.windows.first(where: { $0.windowID == id }) else {
                    throw CaptureFailure.notListed(id)
                }
                guard listed.frame.size == size else {
                    throw CaptureFailure.listedFrame(id, listed.frame, size)
                }
                let filter = SCContentFilter(desktopIndependentWindow: listed)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(((filter.contentRect.width + 2 * shadowMargin) * scale).rounded())
                configuration.height = Int(((filter.contentRect.height + 2 * shadowMargin) * scale).rounded())
                // With the cursor, the capture of a window that is not on screen fails (-3811).
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = shadowMargin == 0
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

    private enum CaptureFailure: Error, CustomStringConvertible {
        /// The capture does not list the window: it has no window server window (a window made with `defer: true`).
        case notListed(CGWindowID)
        /// ScreenCaptureKit lists the window at another size than the window server has it.
        case listedFrame(CGWindowID, CGRect, CGSize)
        case timedOut
        case releaseBuild
        /// The capture's error -3801 (the user declined): the app that runs `make` has no Screen Recording grant.
        case noScreenRecording(String)

        var description: String {
            switch self {
            case .notListed(let id): "window \(id) has no window server window"
            case .listedFrame(let id, let frame, let size): "the capture lists window \(id) at \(frame), not \(size)"
            case .timedOut: "the capture did not answer in 10 s"
            case .releaseBuild: "snapshots need a Debug build (make snapshots)"
            case .noScreenRecording(let app):
                "\(app) needs Screen Recording (System Settings > Privacy & Security > Screen Recording); "
                    + "turn it on and run again"
            }
        }
    }
}
