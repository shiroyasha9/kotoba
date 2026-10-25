import AppKit
import SwiftUI

/// One view that `make snapshots` renders to PNG, in light and dark.
struct Snapshot {
    /// The file name without the appearance suffix and extension.
    let name: String
    /// Builds the view at its final size. A view with a zero frame gets its fitting size.
    let make: @MainActor () -> NSView
    /// Runs after layout; a message fails the run (content that does not fit, cut-off text).
    var check: (@MainActor (NSView) -> String?)?
    /// Lets the run loop turn once the view is in its window, then lays it out again: a `List` sets each row's
    /// measured height in that turn, so without it a row of two lines draws as one, cut off.
    var settlesInWindow = false
    /// Pixels per point; nil draws at the main screen's scale. The README images are always 2x, whatever screen the
    /// run has.
    var scale: CGFloat?
    /// On for a view that floats over other apps (the pill): it sits on the fixed desktop, which its glass refracts.
    /// Off, it sits on the window background, as a pane in its window.
    var floatsOverDesktop = false
    /// On for a showcase image (`make readme-images`, `Showcase`): a view sits on the colourful stage instead, and a real
    /// window is captured with its shadow and put on the stage.
    var isOnStage = false
    /// Off for a view whose image cannot be trusted: the run lays it out and runs its check, and writes no PNG.
    var hasImage = true
}

/// `make snapshots` launches the app binary with `--snapshots <folder>`. Once the app has started, this lays out every
/// registered view in a window that is never ordered on screen, captures the window as the window server composites
/// it (ScreenCaptureKit), writes `<name>-light.png` and `<name>-dark.png` and the sample menus as `menu-<name>.txt`,
/// and exits. Glass, vibrancy and text on glass draw as on screen, and every window draws as the active app's key
/// window; nothing shows on screen. The capture needs Screen Recording for the app that runs `make` (the terminal):
/// without it the run stops and names that app.
@MainActor
enum Snapshots {
    /// The time every sample shows as now (2027-01-15 08:00 UTC): images change only when the UI changes, and the
    /// public README images carry no render time.
    static let sampleNow = Date(timeIntervalSince1970: 1_800_000_000)

    /// Each feature adds one line with its own snapshot list.
    private static let registry: [@MainActor () -> [Snapshot]] = [
        IndicatorPanel.snapshots,
        Pane.dictionarySnapshots,
        Pane.speechSnapshots,
        Pane.microphoneSnapshots,
        Pane.shortcutsSnapshots,
        Pane.generalSnapshots,
        Pane.activitySnapshots,
        Pane.modesSnapshots,
        ChordRecorder.snapshots,
        StatusBarItem.snapshots,
        OnboardingController.snapshots,
        FixLastDictationController.snapshots,
        Pane.homeSnapshots,
        Pane.historySnapshots,
        Pane.historyArrivalChecks,
        Pane.windowSnapshots,
        Pane.switchSnapshots,
        Pane.emptyWindowSnapshots,
        MainWindow.tileSnapshots,
        MainWindow.pageSystemSnapshots,
        MainWindow.frameChecks,
        MainWindow.pageToolbarSnapshots,
    ]

    private static let padding: CGFloat = 16

    /// A fixed-size window's content at the window's size. The real window does not resize, so the run fails when
    /// the content needs more room than `size`, or when `check` reports a problem after layout.
    static func fixedWindow<Content: View>(
        named name: String, size: NSSize, check: (@MainActor (NSView) -> String?)? = nil,
        _ content: @escaping @MainActor () -> Content
    ) -> Snapshot {
        Snapshot(name: name) {
            let view = NSHostingView(rootView: content())
            view.setFrameSize(size)
            return view
        } check: { view in
            fitProblem(of: view, in: size) ?? check?(view)
        }
    }

    /// A real window, title bar and toolbar included, with its content at `contentSize`. The run fails when the
    /// content needs more room than the window, or when `check` reports a problem in the content view after layout.
    static func window(
        named name: String, contentSize: NSSize, _ make: @escaping @MainActor () -> NSWindow,
        check: (@MainActor (NSView) -> String?)? = nil
    ) -> Snapshot {
        Snapshot(name: name) {
            WindowCarrier(window: make(), contentSize: contentSize)
        } check: { view in
            guard let content = (view as? WindowCarrier)?.shown.contentView else { return nil }
            content.layoutSubtreeIfNeeded()
            return fitProblem(of: content, in: contentSize) ?? check?(content)
        }
    }

    /// A real window at the size its content asks for (its content view's fitting size), drawn once its layout has
    /// settled: a view that measures itself (`onScrollGeometryChange`) takes its height a run loop turn later. The run
    /// fails when the size still changes after a few rounds.
    static func fittedWindow(named name: String, _ make: @escaping @MainActor () -> NSWindow) -> Snapshot {
        var isSettled = false
        return Snapshot(name: name) {
            let window = make()
            isSettled = false
            // Each round applies the measured height; the next one finds it unchanged.
            // The harness sizes the window itself: the hosting controller applies its size to the window in a later
            // turn that `settle()` does not wait for, so a round could see no change yet and stop at size zero or at
            // a half point (fix-last-dictation-learned came out 408 or 410 pt).
            for _ in 0..<10 where !isSettled {
                let fitting = window.contentView?.fittingSize ?? .zero
                window.setContentSize(fitting)
                settle()
                window.layoutIfNeeded()
                isSettled = window.contentView?.fittingSize == fitting
            }
            return WindowCarrier(window: window, contentSize: window.contentLayoutRect.size)
        } check: { _ in
            isSettled ? nil : "the window's size kept changing"
        }
    }

    /// Runs the main run loop until it has no more work, without waiting: SwiftUI applies a new pane's toolbar, or a
    /// measured height, in later turns. The snapshot pass is one run loop block (`writeSnapshots`), so these nested
    /// turns also run the main queue's work. The bound stops a view that keeps scheduling work.
    static func settle() {
        for _ in 0..<1_000 where CFRunLoopRunInMode(.defaultMode, 0, true) != .handledSource {
            return
        }
    }

    /// Content that needs more room than its fixed window.
    private static func fitProblem(of content: NSView, in size: NSSize) -> String? {
        let fitting = content.fittingSize
        return fitting.width > size.width + 0.5 || fitting.height > size.height + 0.5
            ? "the content needs \(fitting), the window is \(size)" : nil
    }

    /// Set for the whole of a snapshot run: `AppFiles` refuses to name the owner's files then.
    private(set) static var isRunning = false

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        if arguments.contains("--snapshot-checks") {
            runChecks()
        }
        if arguments.contains("--window-memory") {
            isRunning = true
            NSApplication.shared.setActivationPolicy(.prohibited)
            Pane.measureWindowMemory()
        }
        // `--showcase <folder>` renders the showcase images (`make readme-images`) instead of the registered views.
        let showcase = arguments.firstIndex(of: "--showcase")
        guard let flag = showcase ?? arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1)
        else { return }
        isRunning = true
        let folder = URL(filePath: arguments[flag + 1], directoryHint: .isDirectory)
        NSApplication.shared.setActivationPolicy(.prohibited)
        // A run loop block, not a main queue task: `settle()` and the capture turn the run loop inside the pass, and a
        // nested turn runs the main queue's work only outside a main queue task.
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue) {
            MainActor.assumeIsolated { writeSnapshots(to: folder, isShowcase: showcase != nil) }
        }
        // The capture asks the window server, so the pass runs once the app has started. It exits when done.
        NSApplication.shared.run()
    }

    private static func writeSnapshots(to folder: URL, isShowcase: Bool) -> Never {
        if let problem = SnapshotCapture.problem() {
            FileHandle.standardError.write(Data("Snapshots failed: \(problem)\n".utf8))
            exit(1)
        }
        if let problem = SnapshotCapture.drawWindowsAsActive() {
            FileHandle.standardError.write(Data("Snapshots failed: \(problem)\n".utf8))
            exit(1)
        }
        var written = 0
        do {
            let files = FileManager.default
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            // A renamed or removed view leaves no stale file behind.
            for old in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where ["png", "txt"].contains(old.pathExtension) {
                try files.removeItem(at: old)
            }
            for snapshot in isShowcase ? Showcase.snapshots() : registry.flatMap({ $0() }) {
                guard snapshot.hasImage else {
                    _ = try layOut(snapshot, in: NSAppearance(named: .aqua) ?? .currentDrawing(), isCaptured: false)
                    continue
                }
                for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    guard let appearance = NSAppearance(named: name) else { continue }
                    // Before the view is built: a window that takes its appearance after its first layout animates the
                    // change (a chart's axis labels fade from one color to the other), and the capture catches it.
                    NSApp.appearance = appearance
                    let file = folder.appending(path: "\(snapshot.name)-\(suffix).png")
                    // The pass is one run loop block, so without a pool each image's window and data live to the end.
                    try autoreleasepool { try render(snapshot, in: appearance).write(to: file) }
                    written += 1
                }
            }
            // The menu as text, one line per item, so a review can diff its words.
            // The Dock icon's menu is the ready menu bar menu without Quit; the main menu is the release's, also with an update
            // waiting.
            let menus =
                isShowcase
                ? []
                : MenuModel.samples().map { ($0.name, $0.model.text()) }
                    + MenuModel.samples().filter { $0.name == "ready" }.map { ("dock", $0.model.text(for: .dock)) }
                    + [
                        ("main", MainMenu.outline(MenuModel.Updates())),
                        ("main-update-waiting", MainMenu.outline(MenuModel.Updates(hasWaitingUpdate: true))),
                    ]
            for (name, text) in menus {
                try text.write(to: folder.appending(path: "menu-\(name).txt"), atomically: true, encoding: .utf8)
                written += 1
            }
        } catch {
            FileHandle.standardError.write(Data("Snapshots failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Wrote \(written) snapshots to \(folder.path)\n".utf8))
        exit(0)
    }

    /// `make check` launches the app binary with `--snapshot-checks`: every registered view's checks (window fit, cut-off
    /// pill text, the pills' VoiceOver buttons) in light, with no image written, in about 6 s instead of a full snapshot
    /// run (about 30 s). A window-fit bug reached the owner on 2026-10-15.
    private static func runChecks() {
        isRunning = true
        NSApplication.shared.setActivationPolicy(.prohibited)
        let snapshots = registry.flatMap { $0() }
        do {
            for snapshot in snapshots {
                _ = try layOut(
                    snapshot, in: NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing(), isCaptured: false)
            }
        } catch {
            FileHandle.standardError.write(Data("Snapshot checks failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Checked \(snapshots.count) views\n".utf8))
        exit(0)
    }

    /// Lays the snapshot out in a window that is never ordered on screen, captures the window and returns PNG data.
    private static func render(_ snapshot: Snapshot, in appearance: NSAppearance) throws -> Data {
        let window = try layOut(snapshot, in: appearance, isCaptured: true)
        SnapshotCapture.focusSidebar(in: window)
        SnapshotCapture.endAnimations(in: window)
        // An animation that the end above did not stop (one added again at once) would be captured at its current frame.
        if let animation = SnapshotCapture.runningAnimation(in: window) {
            throw SnapshotError.layout(snapshot.name, "an animation still runs at the capture (\(animation))")
        }
        let image: CGImage
        let scale = snapshot.scale ?? window.backingScaleFactor
        do {
            image =
                snapshot.isOnStage && window.styleMask.contains(.titled)
                ? try Showcase.windowOnStage(window, scale: scale, appearance: appearance)
                : try SnapshotCapture.image(of: window, scale: scale)
        } catch {
            throw SnapshotError.capture(snapshot.name, "\(error)")
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw SnapshotError.noBitmap(snapshot.name)
        }
        return png
    }

    /// Builds the snapshot's view and lays it out in a borderless window that is never ordered on screen, on its
    /// backdrop, then runs its check. A real window (`window`, `fittedWindow`) is laid out as it is. Returns the window
    /// to capture; a captured window gets its window server window at once (`defer: false`).
    private static func layOut(_ snapshot: Snapshot, in appearance: NSAppearance, isCaptured: Bool) throws -> NSWindow {
        let view = snapshot.make()
        let window: NSWindow
        if let carrier = view as? WindowCarrier {
            window = carrier.shown
        } else {
            if view.frame.size == .zero {
                view.setFrameSize(view.fittingSize)
            }
            let size = NSSize(width: view.frame.width + 2 * padding, height: view.frame.height + 2 * padding)
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
                defer: !isCaptured)
            window.isReleasedWhenClosed = false
            let backdrop = Backdrop(
                frame: NSRect(origin: .zero, size: size),
                surface: snapshot.isOnStage ? .stage : snapshot.floatsOverDesktop ? .desktop : .window)
            window.contentView = backdrop
            view.setFrameOrigin(NSPoint(x: padding, y: padding))
            backdrop.addSubview(view)
        }
        window.appearance = appearance
        window.layoutIfNeeded()
        if snapshot.settlesInWindow {
            settle()
            window.layoutIfNeeded()
        }
        if let problem = snapshot.check?(view) {
            throw SnapshotError.layout(snapshot.name, problem)
        }
        return window
    }

    enum SnapshotError: Error {
        case noBitmap(String)
        case layout(String, String)
        case capture(String, String)
    }
}

/// Carries a real window, frame and toolbar included, which `Snapshots` captures on its own instead of hosting it as a
/// subview. The window is never ordered on screen.
private final class WindowCarrier: NSView {
    let shown: NSWindow

    init(window: NSWindow, contentSize: NSSize) {
        shown = window
        shown.setContentSize(contentSize)
        super.init(frame: NSRect(origin: .zero, size: shown.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }
}
