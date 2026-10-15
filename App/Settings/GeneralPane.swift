import KotobaCore
import KotobaProviders
import Observation
import SwiftUI

extension SettingsPane {
    static func general(_ model: GeneralModel) -> Self {
        SettingsPane(id: .general) {
            AnyView(GeneralPane(model: model))
        }
    }
}

/// The General pane's settings: the dictation and cleanup shortcuts and the cleanup model, the spoken Return phrase,
/// launch at login, sounds, the indicator's position and visibility, and automatic update checks. Each change applies
/// at once.
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

    var indicatorVisibility: IndicatorVisibility {
        didSet { setVisibility(indicatorVisibility) }
    }

    var isSubmitPhraseOn: Bool {
        didSet { setSubmitPhrase(isSubmitPhraseOn) }
    }

    var checksForUpdates: Bool {
        didSet { setChecksForUpdates?(checksForUpdates) }
    }

    /// False in a Debug build, which has no updater: the Updates section hides.
    var hasUpdater: Bool { setChecksForUpdates != nil }

    @ObservationIgnored private let settings: TranscriptionSettings
    @ObservationIgnored private let loginItem: LoginItem
    @ObservationIgnored private let setAnchor: @MainActor (IndicatorAnchor) -> Void
    @ObservationIgnored private let setVisibility: @MainActor (IndicatorVisibility) -> Void
    @ObservationIgnored private let setSubmitPhrase: @MainActor (Bool) -> Void
    @ObservationIgnored private let setChecksForUpdates: (@MainActor (Bool) -> Void)?
    /// Observable itself: the rows and the cleanup model follow a new recording.
    @ObservationIgnored let chords: HotkeyChords

    /// Reads the current values. `submitPhraseChanged` hands a new submit phrase setting to the pipeline.
    convenience init(
        settings: TranscriptionSettings, indicator: IndicatorPanel, updater: Updater?,
        submitPhraseChanged: @escaping @MainActor (Bool) -> Void
    ) {
        var setChecksForUpdates: (@MainActor (Bool) -> Void)?
        if let updater {
            setChecksForUpdates = { updater.checksAutomatically = $0 }
        }
        self.init(
            settings: settings, loginItem: .live, chords: .shared, areSoundsOn: AppDefaults.areSoundCuesOn,
            indicatorAnchor: indicator.anchor, setAnchor: { indicator.anchor = $0 },
            indicatorVisibility: indicator.visibility, setVisibility: { indicator.visibility = $0 },
            isSubmitPhraseOn: AppDefaults.isSubmitPhraseOn,
            setSubmitPhrase: {
                AppDefaults.isSubmitPhraseOn = $0
                submitPhraseChanged($0)
            }, checksForUpdates: updater?.checksAutomatically ?? false, setChecksForUpdates: setChecksForUpdates)
    }

    private init(
        settings: TranscriptionSettings, loginItem: LoginItem, chords: HotkeyChords, areSoundsOn: Bool,
        indicatorAnchor: IndicatorAnchor, setAnchor: @escaping @MainActor (IndicatorAnchor) -> Void,
        indicatorVisibility: IndicatorVisibility, setVisibility: @escaping @MainActor (IndicatorVisibility) -> Void,
        isSubmitPhraseOn: Bool, setSubmitPhrase: @escaping @MainActor (Bool) -> Void,
        checksForUpdates: Bool, setChecksForUpdates: (@MainActor (Bool) -> Void)?
    ) {
        self.settings = settings
        self.loginItem = loginItem
        self.setAnchor = setAnchor
        self.setVisibility = setVisibility
        self.setSubmitPhrase = setSubmitPhrase
        self.setChecksForUpdates = setChecksForUpdates
        self.chords = chords
        cleanupModel = settings.cleanupModel
        isLaunchAtLoginOn = loginItem.isOn()
        loginProblem = loginItem.problem()
        self.areSoundsOn = areSoundsOn
        self.indicatorAnchor = indicatorAnchor
        self.indicatorVisibility = indicatorVisibility
        self.isSubmitPhraseOn = isSubmitPhraseOn
        self.checksForUpdates = checksForUpdates
    }

    /// One register or unregister call per click; the toggle then shows what the system holds.
    func setLaunchAtLogin(_ isOn: Bool) {
        guard isOn != isLaunchAtLoginOn else { return }
        loginProblem = loginItem.change(isOn)
        isLaunchAtLoginOn = loginItem.isOn()
    }

    /// Fixed values for snapshots: no UserDefaults, Login Items, indicator or updater is read. `loginItem` stands
    /// in for the system.
    static func sample(loginItem: LoginItem = .init(isOn: { true }, problem: { nil }, change: { _ in nil }))
        -> GeneralModel
    {
        GeneralModel(
            settings: .inMemory(), loginItem: loginItem, chords: HotkeyChords(defaults: nil), areSoundsOn: true,
            indicatorAnchor: .bottomCenter, setAnchor: { _ in }, indicatorVisibility: .whileDictating,
            setVisibility: { _ in }, isSubmitPhraseOn: true, setSubmitPhrase: { _ in }, checksForUpdates: true,
            setChecksForUpdates: { _ in })
    }
}

private struct GeneralPane: View {
    @Bindable var model: GeneralModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .general)
            }
            Section("Shortcut") {
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .dictation)
                } label: {
                    Text("Dictate")
                    Text("Tap to start and stop, or hold while you speak.")
                }
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .cleanup)
                } label: {
                    Text("Clean up")
                    Text("Removes filler words and fixes punctuation. Takes a moment longer.")
                }
                Picker("Cleanup model", selection: $model.cleanupModel) {
                    ForEach(CleanupModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.chords.cleanup == nil)
            }
            Section {
                Toggle(isOn: $model.isSubmitPhraseOn) {
                    Text("Press Return when you say “press enter”")
                    Text("Also “press return”. Say it last: kotoba pastes the text without it, then presses Return.")
                }
            } header: {
                Text("Paste")
            } footer: {
                Text("While you dictate, press Return to stop. kotoba pastes the text, then presses Return.")
            }
            Section("Startup") {
                Toggle(
                    "Open kotoba when you log in",
                    isOn: Binding(get: { model.isLaunchAtLoginOn }, set: { model.setLaunchAtLogin($0) }))
                if let problem = model.loginProblem {
                    LabeledContent {
                        Button("Open Login Items…", action: LaunchAtLogin.openLoginItemsSettings)
                    } label: {
                        Text(problem.text).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Feedback") {
                Toggle("Play a sound when dictation starts and stops", isOn: $model.areSoundsOn)
                Picker("Indicator position", selection: $model.indicatorAnchor) {
                    ForEach(IndicatorAnchor.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(selection: $model.indicatorVisibility) {
                    ForEach(IndicatorVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                } label: {
                    Text("Show indicator")
                    Text("With “Always”, click the indicator to start and stop dictating.")
                }
            }
            if model.hasUpdater {
                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
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
            SettingsWindow.snapshot(of: .general(.sample()), named: "settings-general", height: 860),
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
        var snapshot = SettingsWindow.snapshot(of: .general(model), named: "settings-general-login-failed", height: 840)
        snapshot.check = { _ in
            guard changes == 1, model.loginProblem == .failed, !model.isLaunchAtLoginOn else {
                return "A failed launch-at-login change made \(changes) calls and kept no note"
            }
            return nil
        }
        return snapshot
    }
}
