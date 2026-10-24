import AppKit
import KotobaCore
import KotobaProviders
import KotobaStorage
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The Cleanup page's settings: the per-app modes (story 29; "App styles" on the page): which modes clean every
/// dictation, the installed apps that have a mode, and the mode of every other app; and the cleanup model. Each rules
/// change saves the rules and sends them to the pipeline, so the next dictation uses them. A rule for an app that is not
/// installed (a seed app) stays, with no row.
@MainActor
@Observable
final class ModesModel {
    struct Row: Identifiable, Equatable {
        let bundleID: String
        let name: String
        let mode: AppMode

        var id: String { bundleID }
    }

    /// Where the pane reads and saves the rules and finds apps: the live system, or samples for snapshots.
    struct Source {
        var rules: @MainActor () -> ModeRules
        var save: @MainActor (ModeRules) -> Void
        /// An installed app's name; nil when it is not installed.
        var name: @MainActor (String) -> String?
        var icon: @MainActor (String) -> NSImage?
        /// The apps the owner dictated into lately, most words first, for the Add menu.
        var recentApps: @MainActor () async -> [DictationApp] = { [] }
        /// An app the owner picks in an open panel; nil when they cancel.
        var chooseApp: @MainActor () -> DictationApp? = { nil }
        /// The cleaner's key (OpenRouter) is saved; without it every cleanup pastes the text as spoken.
        var hasCleanupKey: @MainActor () -> Bool = { true }
        /// Opens the pane where the owner adds that key.
        var addKey: @MainActor () -> Void = {}
        /// The cleanup model (`TranscriptionSettings.cleanupModel`).
        var cleanupModel: @MainActor () -> CleanupModel = { .geminiFlashLite }
        var saveCleanupModel: @MainActor (CleanupModel) -> Void = { _ in }

        /// Messages, Mail and Notes in Writing, Terminal in Code, and a seed app that is not installed; TextEdit and
        /// Safari as recent apps. All are system apps, so their icons render on any Mac.
        @MainActor
        static func sample(rules: ModeRules = sampleRules) -> Self {
            var rules = rules
            let names = [
                "com.apple.MobileSMS": "Messages", "com.apple.mail": "Mail", "com.apple.Notes": "Notes",
                "com.apple.Terminal": "Terminal", "com.apple.TextEdit": "TextEdit", "com.apple.Safari": "Safari",
            ]
            var cleanupModel = CleanupModel.geminiFlashLite
            return Self(
                rules: { rules }, save: { rules = $0 }, name: { names[$0] }, icon: InstalledApp.icon(of:),
                recentApps: {
                    ["com.apple.TextEdit", "com.apple.Terminal", "com.apple.Safari"].map {
                        DictationApp(bundleID: $0, name: names[$0])
                    }
                },
                cleanupModel: { cleanupModel }, saveCleanupModel: { cleanupModel = $0 })
        }

        static let sampleRules = ModeRules(
            apps: [
                "com.apple.MobileSMS": .writing, "com.apple.mail": .writing, "com.apple.Notes": .writing,
                "com.apple.Terminal": .code, "com.tinyspeck.slackmacgap": .writing,
            ],
            cleansEveryDictation: [.writing])
    }

    private(set) var rules: ModeRules
    /// Installed apps with a mode, by name.
    private(set) var rows: [Row] = []
    /// Installed recent apps with no mode yet, for the Add menu, with their names.
    private(set) var recent: [DictationApp] = []
    /// Each listed app's icon, looked up once per app, not at each draw or change.
    private(set) var icons: [String: NSImage] = [:]
    private(set) var isCleanupKeyMissing = false
    var cleanupModel: CleanupModel {
        didSet { source.saveCleanupModel(cleanupModel) }
    }
    var isAdvancedShown = false
    /// Observable itself: the shortcut rows follow a new recording.
    @ObservationIgnored let chords: HotkeyChords
    @ObservationIgnored private var recentApps: [DictationApp] = []
    /// Each app's installed name, or nil when it is not installed, looked up once per app.
    @ObservationIgnored private var names: [String: String?] = [:]
    @ObservationIgnored private let source: Source

    /// Reads only the rules: the window builds every pane's model when it opens, and the app lookups (3-9 ms for the
    /// standard lists, measured 2026-10-16) wait until this pane shows (`show()`).
    init(source: Source, chords: HotkeyChords) {
        self.source = source
        self.chords = chords
        rules = source.rules()
        cleanupModel = source.cleanupModel()
    }

    var otherApps: AppMode {
        get { rules.otherApps }
        set { change { $0.otherApps = newValue } }
    }

    func cleansEveryDictation(_ mode: AppMode) -> Bool {
        rules.cleansEveryDictation.contains(mode)
    }

    func setCleansEveryDictation(_ mode: AppMode, _ isOn: Bool) {
        change { rules in
            if isOn {
                rules.cleansEveryDictation.insert(mode)
            } else {
                rules.cleansEveryDictation.remove(mode)
            }
        }
    }

    func setMode(_ mode: AppMode, of bundleID: String) {
        change { $0.apps[bundleID] = mode }
    }

    /// Adds `app` in the mode other apps do not use: that difference is why the owner adds it. An app already in the
    /// list keeps its mode, and kotoba itself is never added.
    func add(_ app: DictationApp) {
        guard app.bundleID != Bundle.main.bundleIdentifier else { return }
        change { rules in
            if rules.apps[app.bundleID] == nil {
                rules.apps[app.bundleID] = rules.otherApps == .code ? .writing : .code
            }
        }
    }

    /// Opens the panel to pick an app from the disk.
    func chooseApp() {
        if let app = source.chooseApp() {
            add(app)
        }
    }

    /// The removed apps use the mode of other apps again.
    func remove(_ bundleIDs: Set<Row.ID>) {
        change { rules in
            for id in bundleIDs {
                rules.apps[id] = nil
            }
        }
    }

    /// The pane shows: the listed apps' names and icons, and whether cleanup has its key (the owner may have added it in
    /// the Speech pane since).
    func show() {
        isCleanupKeyMissing = !source.hasCleanupKey()
        reload()
    }

    func addKey() {
        source.addKey()
    }

    /// Reads the recent apps once the pane shows (a usage ledger read), never at idle.
    func readRecentApps() async {
        recentApps = await source.recentApps()
        reload()
    }

    /// Saves and sends the rules only when the edit changed them.
    private func change(_ edit: (inout ModeRules) -> Void) {
        var changed = rules
        edit(&changed)
        guard changed != rules else { return }
        rules = changed
        source.save(rules)
        reload()
    }

    private func reload() {
        rows = rules.apps.compactMap { id, mode in name(of: id).map { Row(bundleID: id, name: $0, mode: mode) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let own = Bundle.main.bundleIdentifier
        recent = recentApps.filter { rules.apps[$0.bundleID] == nil && $0.bundleID != own }.compactMap { app in
            name(of: app.bundleID).map { DictationApp(bundleID: app.bundleID, name: $0) }
        }
        for id in rows.map(\.bundleID) where icons[id] == nil {
            icons[id] = source.icon(id)
        }
    }

    private func name(of bundleID: String) -> String? {
        if let known = names[bundleID] { return known }
        let found = source.name(bundleID)
        names[bundleID] = found
        return found
    }
}

extension ModesModel.Source {
    /// The rules in UserDefaults, the installed apps, the apps of the last 30 days in the usage ledger, and an open
    /// panel. `send` gives saved rules to the pipeline.
    static func live(
        history: HistoryStore?, settings: TranscriptionSettings, hasCleanupKey: @escaping @MainActor () -> Bool,
        addKey: @escaping @MainActor () -> Void, send: @escaping @MainActor (ModeRules) -> Void
    ) -> Self {
        Self(
            rules: { AppDefaults.modeRules },
            save: { rules in
                AppDefaults.modeRules = rules
                send(rules)
            },
            name: InstalledApp.name(of:),
            icon: InstalledApp.icon(of:),
            recentApps: {
                guard let history else { return [] }
                do {
                    // The apps of the last 30 days.
                    let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
                    return try await history.recentApps(since: since, limit: 20)
                } catch {
                    Log.app.error("Cannot read the recent apps: \(error)")
                    return []
                }
            },
            chooseApp: chooseFromDisk,
            hasCleanupKey: hasCleanupKey,
            addKey: addKey,
            cleanupModel: { settings.cleanupModel },
            saveCleanupModel: { settings.cleanupModel = $0 })
    }

    /// The system's open panel in /Applications, for apps the owner has not dictated into yet.
    @MainActor
    private static func chooseFromDisk() -> DictationApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.prompt = "Add"
        panel.message = "Choose an app to give it a style."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        return DictationApp(bundleID: id, name: InstalledApp.name(of: id))
    }
}
