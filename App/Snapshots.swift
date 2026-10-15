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
}

/// `make snapshots` launches the app binary with `--snapshots <folder>`. Before the app starts,
/// this renders every registered view offscreen with `cacheDisplay`, writes
/// `<name>-light.png` and `<name>-dark.png` and the sample menus as `menu-<name>.txt`, and exits:
/// no screen capture, no TCC grant.
/// Glass and other backdrop effects do not render offscreen, so a view that relies on them draws
/// a stand-in shape in its snapshot.
@MainActor
enum Snapshots {
    /// Each feature adds one line with its own snapshot list.
    private static let registry: [@MainActor () -> [Snapshot]] = [
        IndicatorPanel.snapshots,
        SettingsPane.dictionarySnapshots,
        SettingsPane.speechSnapshots,
        SettingsPane.microphoneSnapshots,
        SettingsPane.generalSnapshots,
        StatusBarItem.snapshots,
        OnboardingController.snapshots,
        FixLastDictationController.snapshots,
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
            let fitting = view.fittingSize
            if fitting.width > size.width + 0.5 || fitting.height > size.height + 0.5 {
                return "the content needs \(fitting), the window is \(size)"
            }
            return check?(view)
        }
    }

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) else { return }
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
            for (name, model) in MenuModel.samples() {
                try model.text().write(
                    to: folder.appending(path: "menu-\(name).txt"), atomically: true, encoding: .utf8)
                written += 1
            }
        } catch {
            FileHandle.standardError.write(Data("Snapshots failed: \(error)\n".utf8))
            exit(1)
        }
        FileHandle.standardError.write(Data("Wrote \(written) snapshots to \(folder.path)\n".utf8))
        exit(0)
    }

    /// Lays the view out in a borderless window that is never ordered on screen, over the window
    /// background, and returns PNG data.
    private static func render(_ snapshot: Snapshot, in appearance: NSAppearance) throws -> Data {
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
        if let problem = snapshot.check?(view) {
            throw SnapshotError.layout(snapshot.name, problem)
        }
        guard let bitmap = backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds) else {
            throw SnapshotError.noBitmap(snapshot.name)
        }
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.noBitmap(snapshot.name)
        }
        return png
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
