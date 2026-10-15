import AppKit

/// One view that `make snapshots` renders to PNG, in light and dark.
struct Snapshot {
    /// The file name without the appearance suffix and extension.
    let name: String
    /// Builds the view at its final size. A view with a zero frame gets its fitting size.
    let make: @MainActor () -> NSView
}

/// `make snapshots` launches the app binary with `--snapshots <folder>`. Before the app starts,
/// this renders every registered view offscreen with `cacheDisplay`, writes
/// `<name>-light.png` and `<name>-dark.png`, and exits: no screen capture, no TCC grant.
/// Glass and other backdrop effects do not render offscreen, so a view that relies on them draws
/// a stand-in shape in its snapshot.
@MainActor
enum Snapshots {
    /// Each feature adds one line with its own snapshot list.
    private static let registry: [@MainActor () -> [Snapshot]] = [
        IndicatorPanel.snapshots,
        SettingsPane.dictionarySnapshots,
        SettingsPane.providerSnapshots,
        SettingsPane.microphoneSnapshots,
    ]

    private static let padding: CGFloat = 16

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshots"), arguments.indices.contains(flag + 1) else { return }
        let folder = URL(filePath: arguments[flag + 1], directoryHint: .isDirectory)
        NSApplication.shared.setActivationPolicy(.prohibited)
        var written = 0
        do {
            let files = FileManager.default
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            // A renamed or removed view leaves no stale PNG behind.
            for old in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where old.pathExtension == "png" {
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
    }

    private final class Backdrop: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }
}
