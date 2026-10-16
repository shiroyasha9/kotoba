import KotobaCore
import KotobaProviders
import Observation
import SwiftUI

extension Pane {
    static func general(_ model: GeneralModel) -> Self {
        Pane(id: .general) {
            AnyView(GeneralPane(model: model))
        }
    }
}

/// The General pane's settings: the dictation, cleanup and Paste Last shortcuts and the cleanup model, the spoken
/// Return phrase, launch at login, the Dock and menu bar icons, sounds and their voice, the indicator's position and
/// visibility, how long audio is kept, and automatic update checks. Each change applies at once.
@MainActor
@Observable
final class GeneralModel {
    /// One setting as the pane sees it: where its value comes from and where a change goes.
    struct Setting<Value> {
        var read: @MainActor () -> Value
        var write: @MainActor (Value) -> Void

        /// A stand-in for snapshots: always `value`, and a change goes nowhere.
        static func fixed(_ value: Value) -> Self where Value: Sendable { Self(read: { value }, write: { _ in }) }
    }

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

    /// Where each setting outside `TranscriptionSettings` is kept: the app (`live`), or stand-ins for snapshots.
    /// A new setting is one field here, one property below, and one line in `live` and `sample()`.
    struct Backing {
        var loginItem: LoginItem
        var showsInDock: Setting<Bool>
        var showsMenuBarIcon: Setting<Bool>
        var soundCues: Setting<Bool>
        var cueVoice: Setting<CueVoice>
        var indicatorAnchor: Setting<IndicatorAnchor>
        var indicatorVisibility: Setting<IndicatorVisibility>
        var submitPhrase: Setting<Bool>
        /// Nil in a Debug build, which has no updater.
        var checksForUpdates: Setting<Bool>?

        /// `submitPhraseChanged` hands a new submit phrase setting to the pipeline.
        static func live(
            indicator: IndicatorPanel, cues: SoundCues, updater: Updater?,
            submitPhraseChanged: @escaping @MainActor (Bool) -> Void
        ) -> Self {
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
                submitPhrase: Setting(
                    read: { AppDefaults.isSubmitPhraseOn },
                    write: {
                        AppDefaults.isSubmitPhraseOn = $0
                        submitPhraseChanged($0)
                    }),
                checksForUpdates: updater.map { updater in
                    Setting(read: { updater.checksAutomatically }, write: { updater.checksAutomatically = $0 })
                })
        }
    }

    var cleanupModel: CleanupModel {
        didSet { settings.cleanupModel = cleanupModel }
    }

    /// Changed through `setLaunchAtLogin(_:)`, which reads the result back from the system.
    private(set) var isLaunchAtLoginOn: Bool
    /// Shown under the toggle when System Settings must approve, or the change failed.
    private(set) var loginProblem: LaunchAtLogin.Problem?

    var showsInDock: Bool {
        didSet { backing.showsInDock.write(showsInDock) }
    }

    var showsMenuBarIcon: Bool {
        didSet { backing.showsMenuBarIcon.write(showsMenuBarIcon) }
    }

    /// The Dock icon and the menu bar icon cannot both be off: the toggle of the one that is left is disabled.
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

    var isSubmitPhraseOn: Bool {
        didSet { backing.submitPhrase.write(isSubmitPhraseOn) }
    }

    var checksForUpdates: Bool {
        didSet { backing.checksForUpdates?.write(checksForUpdates) }
    }

    /// False in a Debug build, which has no updater: the Updates section hides.
    var hasUpdater: Bool { backing.checksForUpdates != nil }

    @ObservationIgnored private let settings: TranscriptionSettings
    @ObservationIgnored private let backing: Backing
    /// Observable itself: the rows and the cleanup model follow a new recording.
    @ObservationIgnored let chords: HotkeyChords
    /// The History section; nil when the history database did not open.
    @ObservationIgnored let audio: AudioRetentionModel?

    /// Reads the current values. `submitPhraseChanged` hands a new submit phrase setting to the pipeline.
    convenience init(
        settings: TranscriptionSettings, indicator: IndicatorPanel, cues: SoundCues, updater: Updater?,
        audio: AudioRetentionModel?, submitPhraseChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.init(
            settings: settings, chords: .shared, audio: audio,
            backing: .live(
                indicator: indicator, cues: cues, updater: updater, submitPhraseChanged: submitPhraseChanged))
    }

    private init(
        settings: TranscriptionSettings, chords: HotkeyChords, audio: AudioRetentionModel?, backing: Backing
    ) {
        self.settings = settings
        self.chords = chords
        self.audio = audio
        self.backing = backing
        cleanupModel = settings.cleanupModel
        isLaunchAtLoginOn = backing.loginItem.isOn()
        loginProblem = backing.loginItem.problem()
        showsInDock = backing.showsInDock.read()
        showsMenuBarIcon = backing.showsMenuBarIcon.read()
        areSoundsOn = backing.soundCues.read()
        cueVoice = backing.cueVoice.read()
        indicatorAnchor = backing.indicatorAnchor.read()
        indicatorVisibility = backing.indicatorVisibility.read()
        isSubmitPhraseOn = backing.submitPhrase.read()
        checksForUpdates = backing.checksForUpdates?.read() ?? false
    }

    /// One register or unregister call per click; the toggle then shows what the system holds.
    func setLaunchAtLogin(_ isOn: Bool) {
        guard isOn != isLaunchAtLoginOn else { return }
        loginProblem = backing.loginItem.change(isOn)
        isLaunchAtLoginOn = backing.loginItem.isOn()
    }

    /// Fixed values for snapshots: no UserDefaults, Login Items, indicator or updater is read. `loginItem` stands
    /// in for the system.
    static func sample(
        loginItem: LoginItem = .init(isOn: { true }, problem: { nil }, change: { _ in nil }), showsInDock: Bool = true,
        chords: HotkeyChords = HotkeyChords(defaults: nil)
    ) -> GeneralModel {
        GeneralModel(
            settings: .inMemory(), chords: chords, audio: .sample(),
            backing: Backing(
                loginItem: loginItem, showsInDock: .fixed(showsInDock), showsMenuBarIcon: .fixed(true),
                soundCues: .fixed(true), cueVoice: .fixed(.nylon), indicatorAnchor: .fixed(.bottomCenter),
                indicatorVisibility: .fixed(.whileDictating), submitPhrase: .fixed(true),
                checksForUpdates: .fixed(true)))
    }
}

private struct GeneralPane: View {
    @Bindable var model: GeneralModel

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .handsFree)
                } label: {
                    Text(StatusText.shortcutTitle(.handsFree))
                    Text(StatusText.shortcutHelp(.handsFree))
                }
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .pushToTalk)
                } label: {
                    Text(StatusText.shortcutTitle(.pushToTalk))
                    Text(StatusText.pushToTalkHelp(model.chords))
                }
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .cleanup)
                } label: {
                    Text(StatusText.shortcutTitle(.cleanup))
                    Text(StatusText.shortcutHelp(.cleanup))
                }
                Picker("Cleanup model", selection: $model.cleanupModel) {
                    ForEach(CleanupModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.chords.cleanup == nil)
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .pasteLast)
                } label: {
                    Text(StatusText.shortcutTitle(.pasteLast))
                    Text(StatusText.shortcutHelp(.pasteLast) + " Off until you record a shortcut.")
                }
                LabeledContent {
                    ChordRecorder(chords: model.chords, role: .copyLast)
                } label: {
                    Text(StatusText.shortcutTitle(.copyLast))
                    Text(StatusText.shortcutHelp(.copyLast))
                }
            }
            Section {
                Toggle(isOn: $model.isSubmitPhraseOn) {
                    Text("Press Return when you say “press enter”")
                    Text("Also “press return”. Say it last; kotoba leaves it out of the text.")
                }
            } header: {
                Text("Paste")
            } footer: {
                Text("Press Return while you dictate to stop: kotoba pastes the text, then presses Return.")
            }
            Section("Feedback") {
                Toggle("Play a sound when dictation starts and stops", isOn: $model.areSoundsOn)
                Picker("Sound", selection: $model.cueVoice) {
                    ForEach(CueVoice.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!model.areSoundsOn)
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
            if let audio = model.audio {
                AudioSection(model: audio)
            }
            // How kotoba starts, shows itself and updates, in one box after the dictation settings.
            Section {
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
                Toggle(isOn: $model.showsInDock) {
                    Text("Show in Dock")
                    Text("When off, kotoba is in the Dock only while one of its windows is open.")
                }
                .disabled(!model.presence.canHideDockIcon)
                Toggle("Show in menu bar", isOn: $model.showsMenuBarIcon)
                    .disabled(!model.presence.canHideMenuBarIcon)
                if model.hasUpdater {
                    Toggle("Check for updates automatically", isOn: $model.checksForUpdates)
                }
            } header: {
                Text("App")
            } footer: {
                if !model.presence.canHideDockIcon || !model.presence.canHideMenuBarIcon {
                    Text("kotoba keeps the Dock icon or the menu bar icon, so you can always open it.")
                }
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
extension Pane {
    static func generalSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .general(.sample()), named: "settings-general", height: 1_200),
            MainWindow.snapshot(
                of: .general(.sample(showsInDock: false)), named: "settings-general-dock-off", height: 1_240),
            loginFailureSnapshot(),
            // Push to talk on its own chord: its line adds the double tap.
            MainWindow.snapshot(
                of: .general(.sample(chords: HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option)))),
                named: "settings-general-push-to-talk", height: 1_200),
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
        var snapshot = MainWindow.snapshot(
            of: .general(model), named: "settings-general-login-failed", height: 1_260)
        snapshot.check = { _ in
            guard changes == 1, model.loginProblem == .failed, !model.isLaunchAtLoginOn else {
                return "A failed launch-at-login change made \(changes) calls and kept no note"
            }
            return nil
        }
        return snapshot
    }
}
