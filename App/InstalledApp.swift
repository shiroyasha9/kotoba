import AppKit

/// An installed app found by its bundle id, for rows that name the app a dictation or a correction came from.
enum InstalledApp {
    /// The app's name as Finder shows it, without ".app"; nil when it is not installed.
    static func name(of bundleID: String) -> String? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            FileManager.default.displayName(atPath: $0.path).replacing(/\.app$/, with: "")
        }
    }

    /// The app's icon; nil when it is not installed.
    static func icon(of bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
    }
}
