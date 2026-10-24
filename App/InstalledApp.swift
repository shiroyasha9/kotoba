import AppKit
import KotobaCore
import KotobaStorage

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

/// The names and icons of the apps a window's rows show, looked up once per app for the window's life, not at each
/// draw. A pane model keeps one and drops it with the window.
@MainActor
final class InstalledApps {
    private var names: [String: String?] = [:]
    private var icons: [String: NSImage?] = [:]

    /// The name saved with the dictation, else the installed app's; nil when neither is known.
    func name(of app: DictationApp) -> String? {
        if let name = app.name { return name }
        if let known = names[app.bundleID] { return known }
        let name = InstalledApp.name(of: app.bundleID)
        names[app.bundleID] = name
        return name
    }

    /// Nil when the app is unknown or not installed.
    func icon(of app: DictationApp?) -> NSImage? {
        guard let app else { return nil }
        if let known = icons[app.bundleID] { return known }
        let icon = InstalledApp.icon(of: app.bundleID)
        icons[app.bundleID] = icon
        return icon
    }
}
