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
}

/// `make snapshots` launches the app binary with `--snapshots <folder>`. Before the app starts,
/// this renders every registered view offscreen with `cacheDisplay`, writes
/// `<name>-light.png` and `<name>-dark.png` and the sample menus as `menu-<name>.txt`, and exits:
/// no screen capture, no TCC grant.
/// Glass and other backdrop effects do not render offscreen, so a view that relies on them draws
/// a stand-in shape in its snapshot. Text that SwiftUI or AppKit draws on glass with a system style
/// (`.primary`, `.secondary`, a `.glass` button title, the macOS 26 sidebar labels) draws near
/// black in the dark images: the window server applies its glass tint, `cacheDisplay` does not.
/// An explicit color or an AppKit label on the same glass draws right (docs/research/native-ui.md).
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
        Pane.generalSnapshots,
        Pane.usageSnapshots,
        Pane.insightsSnapshots,
        Pane.modesSnapshots,
        ChordRecorder.snapshots,
        StatusBarItem.snapshots,
        OnboardingController.snapshots,
        FixLastDictationController.snapshots,
        Pane.homeSnapshots,
        Pane.historySnapshots,
        Pane.windowSnapshots,
        Pane.switchSnapshots,
        Pane.emptyWindowSnapshots,
        Pane.readmeSnapshots,
    ]

    private static let padding: CGFloat = 16

    /// The hosting view for a SwiftUI snapshot. Offscreen no window is key, so prominent and default buttons
    /// and toggles would draw grey as in a background window; this draws them as in the key window. A list
    /// selection still draws grey (it also needs the first responder).
    static func hostingView(_ root: some View) -> NSHostingView<some View> {
        NSHostingView(rootView: root.environment(\.controlActiveState, .key))
    }

    /// A fixed-size window's content at the window's size. The real window does not resize, so the run fails when
    /// the content needs more room than `size`, or when `check` reports a problem after layout.
    static func fixedWindow<Content: View>(
        named name: String, size: NSSize, check: (@MainActor (NSView) -> String?)? = nil,
        _ content: @escaping @MainActor () -> Content
    ) -> Snapshot {
        Snapshot(name: name) {
            let view = hostingView(content())
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
            WindowImage(window: make(), contentSize: contentSize)
        } check: { view in
            guard let content = (view as? WindowImage)?.shown.contentView else { return nil }
            content.layoutSubtreeIfNeeded()
            return fitProblem(of: content, in: contentSize) ?? check?(content)
        }
    }

    /// A real window at the size its content asks for (the hosting controller's size constraints), drawn once its
    /// layout has settled: a view that measures itself (`onScrollGeometryChange`) takes its height a run loop turn
    /// later. The run fails when the size still changes after a few rounds.
    static func fittedWindow(named name: String, _ make: @escaping @MainActor () -> NSWindow) -> Snapshot {
        var isSettled = false
        return Snapshot(name: name) {
            let window = make()
            isSettled = false
            // Each round applies the measured height; the next one finds it unchanged.
            for _ in 0..<10 where !isSettled {
                let size = window.contentLayoutRect.size
                settle()
                window.layoutIfNeeded()
                isSettled = window.contentLayoutRect.size == size
            }
            return WindowImage(window: window, contentSize: window.contentLayoutRect.size)
        } check: { _ in
            isSettled ? nil : "the window's size kept changing"
        }
    }

    /// Runs the main run loop until it has no more work, without waiting: SwiftUI applies a new pane's toolbar, or a
    /// measured height, in later turns. The snapshot run happens before the app's run loop starts. The bound stops a
    /// view that keeps scheduling work.
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
        guard let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) else { return }
        isRunning = true
        let folder = URL(filePath: arguments[flag + 1], directoryHint: .isDirectory)
        NSApplication.shared.setActivationPolicy(.prohibited)
        var written = 0
        do {
            let files = FileManager.default
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            // A renamed or removed view leaves no stale file behind.
            for old in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where ["png", "txt"].contains(old.pathExtension) {
                try files.removeItem(at: old)
            }
            for snapshot in registry.flatMap({ $0() }) {
                for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    guard let appearance = NSAppearance(named: name) else { continue }
                    let file = folder.appending(path: "\(snapshot.name)-\(suffix).png")
                    try render(snapshot, in: appearance).write(to: file)
                    written += 1
                }
            }
            // The menu as text, one line per item, so a review can diff its words.
            // The Dock icon's menu is the ready menu bar menu without Quit; the main menu is the release's, also with an update
            // waiting.
            let menus =
                MenuModel.samples().map { ($0.name, $0.model.text()) }
                + MenuModel.samples().filter { $0.name == "ready" }.map { ("dock", $0.model.text(for: .dock)) }
                + [
                    ("main", MainMenu(target: nil) { MenuModel.Updates() }.menu.outline()),
                    (
                        "main-update-waiting",
                        MainMenu(target: nil) { MenuModel.Updates(hasWaitingUpdate: true) }.menu.outline()
                    ),
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
    /// run (about 18 s). A window-fit bug reached the owner on 2026-10-15.
    private static func runChecks() {
        isRunning = true
        NSApplication.shared.setActivationPolicy(.prohibited)
        let snapshots = registry.flatMap { $0() }
        do {
            for snapshot in snapshots {
                _ = try layOut(snapshot, in: NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing())
            }
        } catch {
            FileHandle.standardError.write(Data("Snapshot checks failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Checked \(snapshots.count) views\n".utf8))
        exit(0)
    }

    /// Lays the view out in a borderless window that is never ordered on screen, over the window
    /// background, and returns PNG data.
    private static func render(_ snapshot: Snapshot, in appearance: NSAppearance) throws -> Data {
        // The window holds the backdrop's appearance while it draws, so it lives until the image is made.
        let window = try layOut(snapshot, in: appearance)
        guard let backdrop = window.contentView,
            let bitmap = snapshot.scale.map({ bitmap(of: backdrop, scale: $0) })
                ?? backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds)
        else {
            throw SnapshotError.noBitmap(snapshot.name)
        }
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.noBitmap(snapshot.name)
        }
        return png
    }

    /// A bitmap of `view`'s bounds at `scale` pixels per point, in sRGB as the screen's bitmaps are.
    private static func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        let size = view.bounds.size
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB)
        bitmap?.size = size
        return bitmap
    }

    /// Builds the snapshot's view and lays it out in a borderless window that is never ordered on screen, over the window
    /// background, then runs its check. Returns the window; its content view is the backdrop.
    private static func layOut(_ snapshot: Snapshot, in appearance: NSAppearance) throws -> NSWindow {
        let view = snapshot.make()
        if view.frame.size == .zero {
            view.setFrameSize(view.fittingSize)
        }
        let size = NSSize(width: view.frame.width + 2 * padding, height: view.frame.height + 2 * padding)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        let backdrop = Backdrop(frame: NSRect(origin: .zero, size: size))
        window.contentView = backdrop
        view.setFrameOrigin(NSPoint(x: padding, y: padding))
        backdrop.addSubview(view)
        backdrop.layoutSubtreeIfNeeded()
        if snapshot.settlesInWindow {
            settle()
            backdrop.layoutSubtreeIfNeeded()
        }
        if let problem = snapshot.check?(view) {
            throw SnapshotError.layout(snapshot.name, problem)
        }
        return window
    }

    enum SnapshotError: Error {
        case noBitmap(String)
        case layout(String, String)
    }

    private final class Backdrop: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}

/// Draws a real window, frame and toolbar included, which `Snapshots` cannot host as a subview. The window is never
/// ordered on screen; it takes the snapshot's appearance when drawn. Custom: AppKit has no offscreen window image.
private final class WindowImage: NSView {
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

    override func draw(_ dirtyRect: NSRect) {
        shown.appearance = effectiveAppearance
        guard let frameView = shown.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        bitmap.draw(in: bounds)
    }
}
