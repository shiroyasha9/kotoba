import KotobaCore
import KotobaProviders
import Observation
import SwiftUI

extension SettingsPane {
    static func general(_ model: GeneralModel) -> Self {
        SettingsPane(id: .general, title: "General", systemImage: "gearshape") {
            AnyView(GeneralPane(model: model))
        }
    }
}

/// The settings that used to live only in the menu (ux-polish G1): the cleanup chord and model, launch at
/// login, sounds and the indicator position. Each change applies at once.
@MainActor
@Observable
final class GeneralModel {
    /// Where the pane reads and writes launch at login: `LaunchAtLogin`, or a stand-in for snapshots.
    struct LoginItem {
        /// On, or turned on and waiting for approval in System Settings.
        var isOn: @MainActor () -> Bool
        var problem: @MainActor () -> LaunchAtLogin.Problem?
        var change: @MainActor (Bool) -> LaunchAtLogin.Problem?

        static let live = Self(
            isOn: { LaunchAtLogin.isOn || LaunchAtLogin.needsApproval }, problem: { LaunchAtLogin.problem },
            change: { LaunchAtLogin.change(to: $0) })
    }

    var cleanupChord: CleanupChord {
        didSet {
            CleanupChord.current = cleanupChord
            setCleanupChord(cleanupChord.modifiers)
        }
    }

    var cleanupModel: CleanupModel {
        didSet { settings.cleanupModel = cleanupModel }
    }

    /// Changed through `setLaunchAtLogin(_:)`, which reads the result back from the system.
    private(set) var isLaunchAtLoginOn: Bool
    /// Shown under the toggle when System Settings must approve, or the change failed.
    private(set) var loginProblem: LaunchAtLogin.Problem?

    var areSoundsOn: Bool {
        didSet { AppDefaults.areSoundCuesOn = areSoundsOn }
    }

    var indicatorAnchor: IndicatorAnchor {
        didSet { setAnchor(indicatorAnchor) }
    }

    @ObservationIgnored private let settings: TranscriptionSettings
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let setAnchor: @MainActor (IndicatorAnchor) -> Void
    @ObservationIgnored private let setCleanupChord: @MainActor (ModifierKeys?) -> Void

    /// Reads the current values. `setCleanupChord` tells the hotkey tap about a new chord.
    convenience init(
        settings: TranscriptionSettings, indicator: IndicatorPanel,
        setCleanupChord: @escaping @MainActor (ModifierKeys?) -> Void
    ) {
        self.init(
            settings: settings, loginItem: .live, cleanupChord: .current, areSoundsOn: AppDefaults.areSoundCuesOn,
            indicatorAnchor: indicator.anchor, setAnchor: { indicator.anchor = $0 }, setCleanupChord: setCleanupChord)
    }

    private init(
        settings: TranscriptionSettings, loginItem: LoginItem, cleanupChord: CleanupChord, areSoundsOn: Bool,
        indicatorAnchor: IndicatorAnchor, setAnchor: @escaping @MainActor (IndicatorAnchor) -> Void,
        setCleanupChord: @escaping @MainActor (ModifierKeys?) -> Void
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.setAnchor = setAnchor
        self.setCleanupChord = setCleanupChord
        self.cleanupChord = cleanupChord
        cleanupModel = settings.cleanupModel
        isLaunchAtLoginOn = loginItem.isOn()
        loginProblem = loginItem.problem()
        self.areSoundsOn = areSoundsOn
        self.indicatorAnchor = indicatorAnchor
    }

    /// One register or unregister call per click; the toggle then shows what the system holds.
    func setLaunchAtLogin(_ isOn: Bool) {
        guard isOn != isLaunchAtLoginOn else { return }
        loginProblem = loginItem.change(isOn)
        isLaunchAtLoginOn = loginItem.isOn()
    }

    /// Fixed values for snapshots: no UserDefaults, Login Items or indicator is read. `loginItem` stands in for
    /// the system.
    static func sample(loginItem: LoginItem = .init(isOn: { true }, problem: { nil }, change: { _ in nil }))
        -> GeneralModel
    {
        GeneralModel(
            settings: .inMemory(), loginItem: loginItem, cleanupChord: .shift, areSoundsOn: true,
            indicatorAnchor: .bottomCenter, setAnchor: { _ in }, setCleanupChord: { _ in })
    }
}

private struct GeneralPane: View {
    @Bindable var model: GeneralModel

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent {
                    Text(StatusText.dictationChord)
                } label: {
                    Text("Dictate")
                    Text("Tap to start and stop, or hold while you speak.")
                }
                Picker(selection: $model.cleanupChord) {
                    ForEach(CleanupChord.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Clean up")
                    Text("Removes filler words and fixes punctuation. Takes a moment longer.")
                }
                Picker("Cleanup model", selection: $model.cleanupModel) {
                    ForEach(CleanupModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.cleanupChord == .off)
            }
            Section("Startup") {
                Toggle(
                    "Open kotoba when you log in",
                    isOn: Binding(get: { model.isLaunchAtLoginOn }, set: { model.setLaunchAtLogin($0) }))
                if let problem = model.loginProblem {
                    HStack {
                        Text(problem.text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…", action: LaunchAtLogin.openLoginItemsSettings)
                    }
                }
            }
            Section("Feedback") {
                Toggle("Play a sound when dictation starts and stops", isOn: $model.areSoundsOn)
                Picker("Indicator position", selection: $model.indicatorAnchor) {
                    ForEach(IndicatorAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
extension SettingsPane {
    static func generalSnapshots() -> [Snapshot] {
        [
            SettingsWindow.snapshot(of: .general(.sample()), named: "settings-general", height: 520),
            loginFailureSnapshot(),
        ]
    }

    /// Review B1: a failed launch-at-login change makes one system call and keeps its note. The toggle stays
    /// off, and the run fails if a second call (the old didSet loop) clears the note.
    private static func loginFailureSnapshot() -> Snapshot {
        var changes = 0
        let model = GeneralModel.sample(
            loginItem: .init(
                isOn: { false }, problem: { nil },
                change: { _ in
                    changes += 1
                    return .failed
                }))
        model.setLaunchAtLogin(true)
        var snapshot = SettingsWindow.snapshot(of: .general(model), named: "settings-general-login-failed", height: 560)
        snapshot.check = { _ in
            guard changes == 1, model.loginProblem == .failed, !model.isLaunchAtLoginOn else {
                return "A failed launch-at-login change made \(changes) calls and kept no note"
            }
            return nil
        }
        return snapshot
    }
}
