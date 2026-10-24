import KotobaCore
import Observation
import SwiftUI

extension Pane {
    static func general(_ model: GeneralModel) -> Self {
        Pane(id: .general) {
            AnyView(GeneralPane(model: model))
        }
    }
}

/// The General page's settings: sounds and their voice, the indicator's position and visibility, launch at login, the
/// Dock and menu bar icons, and automatic update checks. Each change applies at once.
@MainActor
@Observable
final class GeneralModel {
    /// Where the page reads and writes launch at login: `LaunchAtLogin`, or a stand-in for snapshots.
    struct LoginItem {
        /// On, or turned on and waiting for approval in System Settings.
        var isOn: @MainActor () -> Bool
        var problem: @MainActor () -> LaunchAtLogin.Problem?
        var change: @MainActor (Bool) -> LaunchAtLogin.Problem?

        static let live = Self(
            isOn: { LaunchAtLogin.isOn || LaunchAtLogin.needsApproval }, problem: { LaunchAtLogin.problem },
            change: { LaunchAtLogin.change(to: $0) })
    }

    /// Where each setting is kept: the app (`live`), or stand-ins for snapshots. A new setting is one field here, one
    /// property below, and one line in `live` and `sample()`.
    struct Backing {
        var loginItem: LoginItem
        var showsInDock: Setting<Bool>
        var showsMenuBarIcon: Setting<Bool>
        var soundCues: Setting<Bool>
        var cueVoice: Setting<CueVoice>
        var indicatorAnchor: Setting<IndicatorAnchor>
        var indicatorVisibility: Setting<IndicatorVisibility>
        /// Nil in a Debug build, which has no updater.
        var checksForUpdates: Setting<Bool>?

        static func live(indicator: IndicatorPanel, cues: SoundCues, updater: Updater?) -> Self {
            Self(
                loginItem: .live,
                showsInDock: Setting(
                    read: { DockAndMenuBar.shared.presence.showsInDock },
                    write: { DockAndMenuBar.shared.setShowsInDock($0) }),
                showsMenuBarIcon: Setting(
                    read: { DockAndMenuBar.shared.presence.showsMenuBarIcon },
                    write: { DockAndMenuBar.shared.setShowsMenuBarIcon($0) }),
                soundCues: Setting(read: { AppDefaults.areSoundCuesOn }, write: { AppDefaults.areSoundCuesOn = $0 }),
                // A new voice plays its start cue once, so the owner hears the choice.
                cueVoice: Setting(
                    read: { cues.voice },
                    write: {
                        cues.voice = $0
                        cues.play(.start)
                    }),
                indicatorAnchor: Setting(read: { indicator.anchor }, write: { indicator.anchor = $0 }),
                indicatorVisibility: Setting(read: { indicator.visibility }, write: { indicator.visibility = $0 }),
                checksForUpdates: updater.map { updater in
                    Setting(read: { updater.checksAutomatically }, write: { updater.checksAutomatically = $0 })
                })
        }
    }

    /// Changed through `setLaunchAtLogin(_:)`, which reads the result back from the system.
    private(set) var isLaunchAtLoginOn: Bool
    /// Shown under the switch when System Settings must approve, or the change failed.
    private(set) var loginProblem: LaunchAtLogin.Problem?

    var showsInDock: Bool {
        didSet { backing.showsInDock.write(showsInDock) }
    }

    var showsMenuBarIcon: Bool {
        didSet { backing.showsMenuBarIcon.write(showsMenuBarIcon) }
    }

    /// The Dock icon and the menu bar icon cannot both be off: the switch of the one that is left is off limits.
    var presence: AppPresence { AppPresence(showsInDock: showsInDock, showsMenuBarIcon: showsMenuBarIcon) }

    var areSoundsOn: Bool {
        didSet { backing.soundCues.write(areSoundsOn) }
    }

    var cueVoice: CueVoice {
        didSet { backing.cueVoice.write(cueVoice) }
    }

    var indicatorAnchor: IndicatorAnchor {
        didSet { backing.indicatorAnchor.write(indicatorAnchor) }
    }

    var indicatorVisibility: IndicatorVisibility {
        didSet { backing.indicatorVisibility.write(indicatorVisibility) }
    }

    var checksForUpdates: Bool {
        didSet { backing.checksForUpdates?.write(checksForUpdates) }
    }

    /// False in a Debug build, which has no updater: the Updates section hides.
    var hasUpdater: Bool { backing.checksForUpdates != nil }

    @ObservationIgnored private let backing: Backing

    /// Reads the current values.
    convenience init(indicator: IndicatorPanel, cues: SoundCues, updater: Updater?) {
        self.init(backing: .live(indicator: indicator, cues: cues, updater: updater))
    }

    private init(backing: Backing) {
        self.backing = backing
        isLaunchAtLoginOn = backing.loginItem.isOn()
        loginProblem = backing.loginItem.problem()
        showsInDock = backing.showsInDock.read()
        showsMenuBarIcon = backing.showsMenuBarIcon.read()
        areSoundsOn = backing.soundCues.read()
        cueVoice = backing.cueVoice.read()
        indicatorAnchor = backing.indicatorAnchor.read()
        indicatorVisibility = backing.indicatorVisibility.read()
        checksForUpdates = backing.checksForUpdates?.read() ?? false
    }

    /// One register or unregister call per click; the switch then shows what the system holds.
    func setLaunchAtLogin(_ isOn: Bool) {
        guard isOn != isLaunchAtLoginOn else { return }
        loginProblem = backing.loginItem.change(isOn)
        isLaunchAtLoginOn = backing.loginItem.isOn()
    }

    /// Fixed values for snapshots: no UserDefaults, Login Items, indicator or updater is read. `loginItem` stands
    /// in for the system.
    static func sample(
        loginItem: LoginItem = .init(isOn: { true }, problem: { nil }, change: { _ in nil }), showsInDock: Bool = true
    ) -> GeneralModel {
        GeneralModel(
            backing: Backing(
                loginItem: loginItem, showsInDock: .fixed(showsInDock), showsMenuBarIcon: .fixed(true),
                soundCues: .fixed(true), cueVoice: .fixed(.nylon), indicatorAnchor: .fixed(.bottomCenter),
                indicatorVisibility: .fixed(.whileDictating), checksForUpdates: .fixed(true)))
    }
}

/// How kotoba sounds and shows itself, how it opens and how it updates (docs/research/ui-redesign.md, "Page map").
private struct GeneralPane: View {
    @Bindable var model: GeneralModel

    var body: some View {
        PageForm {
            Section {
                PageHeader(page: .general, summary: "How kotoba sounds and shows itself, opens and updates.")
            }
            Section("Sounds") {
                PageToggle(
                    title: "Play sounds", subtitle: "When a dictation starts and stops.", isOn: $model.areSoundsOn)
                Picker("Sound", selection: $model.cueVoice) {
                    ForEach(CueVoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!model.areSoundsOn)
            }
            Section("Indicator") {
                Picker("Position", selection: $model.indicatorAnchor) {
                    ForEach(IndicatorAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                PageRow(title: "Show", subtitle: "With “Always”, click the indicator to start and stop a dictation.") {
                    Picker("Show", selection: $model.indicatorVisibility) {
                        ForEach(IndicatorVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Section {
                Toggle(
                    "Open at login",
                    isOn: Binding(get: { model.isLaunchAtLoginOn }, set: { model.setLaunchAtLogin($0) }))
                if let problem = model.loginProblem {
                    LabeledContent {
                        Button("Open Login Items…", action: LaunchAtLogin.openLoginItemsSettings)
                    } label: {
                        Text(problem.text).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                PageToggle(
                    title: "Show in Dock",
                    subtitle: "When off, kotoba is in the Dock only while one of its windows is open.",
                    isOn: $model.showsInDock
                )
                .disabled(!model.presence.canHideDockIcon)
                Toggle("Show in menu bar", isOn: $model.showsMenuBarIcon)
                    .disabled(!model.presence.canHideMenuBarIcon)
            } header: {
                Text("Dock and Menu Bar")
            } footer: {
                if !model.presence.canHideDockIcon || !model.presence.canHideMenuBarIcon {
                    Text("kotoba keeps the Dock icon or the menu bar icon, so you can always open it.")
                }
            }
            if model.hasUpdater {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
                }
            }
        }
    }
}
