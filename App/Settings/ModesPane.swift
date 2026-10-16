import AppKit
import KotobaCore
import KotobaStorage
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension SettingsPane {
    static func modes(_ model: ModesModel) -> Self {
        SettingsPane(id: .modes) {
            AnyView(ModesPane(model: model))
        }
    }
}

extension AppMode {
    /// The mode's name in the pane's pickers.
    var title: String {
        switch self {
        case .code: "Code"
        case .writing: "Writing"
        }
    }

    /// What the mode's apps are and what its cleanup does, under its toggle.
    var summary: String {
        switch self {
        case .code: "Terminals, editors and coding agents. Cleanup keeps commands, paths and flags as you said them."
        case .writing: "Messages, mail and notes. Cleanup writes clear sentences in your words."
        }
    }
}

/// The per-app modes as the Modes pane shows them (story 29): which modes clean every dictation, the installed apps
/// that have a mode, and the mode of every other app. Each change saves the rules and sends them to the pipeline, so the
/// next dictation uses them. A rule for an app that is not installed (a seed app) stays, with no row.
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

        /// Messages, Mail and Notes in Writing, Terminal in Code, and a seed app that is not installed; TextEdit and
        /// Safari as recent apps. All are system apps, so their icons render on any Mac.
        @MainActor
        static func sample(rules: ModeRules = sampleRules) -> Self {
            var rules = rules
            let names = [
                "com.apple.MobileSMS": "Messages", "com.apple.mail": "Mail", "com.apple.Notes": "Notes",
                "com.apple.Terminal": "Terminal", "com.apple.TextEdit": "TextEdit", "com.apple.Safari": "Safari",
            ]
            return Self(
                rules: { rules }, save: { rules = $0 }, name: { names[$0] }, icon: InstalledApp.icon(of:),
                recentApps: {
                    ["com.apple.TextEdit", "com.apple.Terminal", "com.apple.Safari"].map {
                        DictationApp(bundleID: $0, name: names[$0])
                    }
                })
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
    /// Each shown app's icon, looked up once per app, not at each draw or change.
    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private var recentApps: [DictationApp] = []
    /// Each app's installed name, or nil when it is not installed, looked up once per app.
    @ObservationIgnored private var names: [String: String?] = [:]
    @ObservationIgnored private let source: Source

    init(source: Source) {
        self.source = source
        rules = source.rules()
        reload()
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

    /// Reads the recent apps once the pane shows (a usage ledger read), never at idle.
    func appear() async {
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
        for id in rows.map(\.bundleID) + recent.map(\.bundleID) where icons[id] == nil {
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
    static func live(history: HistoryStore?, send: @escaping @MainActor (ModeRules) -> Void) -> Self {
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
                    return try await history.recentApps(
                        since: UsageModel.Period.last30Days.start(at: .now), limit: 20)
                } catch {
                    Log.app.error("Cannot read the recent apps: \(error)")
                    return []
                }
            },
            chooseApp: chooseFromDisk)
    }

    /// The system's open panel in /Applications, for apps the owner has not dictated into yet.
    @MainActor
    private static func chooseFromDisk() -> DictationApp? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.prompt = "Add"
        panel.message = "Choose an app to give it a mode."
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        return DictationApp(bundleID: id, name: InstalledApp.name(of: id))
    }
}

private struct ModesPane: View {
    @Bindable var model: ModesModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .modes)
            }
            Section {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Toggle(isOn: cleansEveryDictation(mode)) {
                        Text("\(mode.title) apps")
                        Text(mode.summary)
                    }
                }
            } header: {
                Text("Clean Up Every Dictation")
            } footer: {
                Text(
                    "When off, only the dictations you start with the cleanup shortcut are cleaned up. "
                        + "Each cleanup takes a second or two longer.")
            }
            Section {
                EditableList(
                    rows: model.rows, emptyText: "No apps in the list: every app uses the mode below.",
                    addTitle: "Add App", addHelp: "Give an app its own mode", removeTitle: "Remove from List",
                    remove: model.remove
                ) { row in
                    LabeledContent {
                        Picker(row.name, selection: mode(of: row)) {
                            modeChoices
                        }
                        .labelsHidden()
                        .fixedSize()
                    } label: {
                        Label {
                            Text(row.name)
                        } icon: {
                            icon(of: row.bundleID)
                        }
                    }
                } addItems: {
                    if !model.recent.isEmpty {
                        Section("Recent Apps") {
                            ForEach(model.recent, id: \.bundleID) { app in
                                Button {
                                    model.add(app)
                                } label: {
                                    Label {
                                        Text(app.name ?? app.bundleID)
                                    } icon: {
                                        icon(of: app.bundleID)
                                    }
                                }
                            }
                        }
                    }
                    Button("Choose App…", action: model.chooseApp)
                }
            } header: {
                Text("Apps")
            } footer: {
                Text("The app in front when you stop a dictation picks its mode.")
            }
            Section {
                Picker("Other apps", selection: $model.otherApps) {
                    modeChoices
                }
            } footer: {
                Text("The mode of every app that is not in the list.")
            }
        }
        .formStyle(.grouped)
        .task { await model.appear() }
    }

    private var modeChoices: some View {
        ForEach(AppMode.allCases, id: \.self) { Text($0.title).tag($0) }
    }

    /// Decoration: the row's name says which app it is (as in the History window).
    private func icon(of bundleID: String) -> some View {
        Group {
            if let image = model.icons[bundleID] {
                Image(nsImage: image).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    private func mode(of row: ModesModel.Row) -> Binding<AppMode> {
        Binding(get: { row.mode }, set: { model.setMode($0, of: row.bundleID) })
    }

    private func cleansEveryDictation(_ mode: AppMode) -> Binding<Bool> {
        Binding(get: { model.cleansEveryDictation(mode) }, set: { model.setCleansEveryDictation(mode, $0) })
    }
}

@MainActor
extension SettingsPane {
    static func modesSnapshots() -> [Snapshot] {
        [
            SettingsWindow.snapshot(of: .modes(ModesModel(source: .sample())), named: "settings-modes", height: 700),
            SettingsWindow.snapshot(
                of: .modes(ModesModel(source: .sample(rules: ModeRules()))), named: "settings-modes-empty",
                height: 600),
        ]
    }
}
