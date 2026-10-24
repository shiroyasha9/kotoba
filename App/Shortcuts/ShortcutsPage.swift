import KotobaCore
import KotobaProviders
import Observation
import SwiftUI

extension Pane {
    static func shortcuts(_ model: ShortcutsModel) -> Self {
        Pane(id: .shortcuts) {
            AnyView(ShortcutsPage(model: model))
        }
    }
}

/// The Shortcuts page's settings: every chord, the cleanup model, and the spoken Return and line break commands. A chord
/// is saved by its recorder (`HotkeyChords`); each other change applies at once.
@MainActor
@Observable
final class ShortcutsModel {
    var cleanupModel: CleanupModel {
        didSet { settings.cleanupModel = cleanupModel }
    }

    var isSubmitPhraseOn: Bool {
        didSet { submitPhrase.write(isSubmitPhraseOn) }
    }

    var isLineBreakPhraseOn: Bool {
        didSet { lineBreakPhrase.write(isLineBreakPhraseOn) }
    }

    /// Observable itself: the rows and the cleanup model follow a new recording.
    @ObservationIgnored let chords: HotkeyChords
    @ObservationIgnored private let settings: TranscriptionSettings
    @ObservationIgnored private let submitPhrase: Setting<Bool>
    @ObservationIgnored private let lineBreakPhrase: Setting<Bool>

    init(
        settings: TranscriptionSettings, chords: HotkeyChords, submitPhrase: Setting<Bool>,
        lineBreakPhrase: Setting<Bool>
    ) {
        self.settings = settings
        self.chords = chords
        self.submitPhrase = submitPhrase
        self.lineBreakPhrase = lineBreakPhrase
        cleanupModel = settings.cleanupModel
        isSubmitPhraseOn = submitPhrase.read()
        isLineBreakPhraseOn = lineBreakPhrase.read()
    }

    /// The app's chords and saved commands; `pasteSettingChanged` hands a new spoken command setting to the pipeline.
    static func live(
        settings: TranscriptionSettings, pasteSettingChanged: @escaping @MainActor (PasteSetting) -> Void
    ) -> ShortcutsModel {
        ShortcutsModel(
            settings: settings, chords: .shared,
            submitPhrase: Setting(
                read: { AppDefaults.isSubmitPhraseOn },
                write: {
                    AppDefaults.isSubmitPhraseOn = $0
                    pasteSettingChanged(.submitPhrase($0))
                }),
            lineBreakPhrase: Setting(
                read: { AppDefaults.isLineBreakPhraseOn },
                write: {
                    AppDefaults.isLineBreakPhraseOn = $0
                    pasteSettingChanged(.lineBreakPhrase($0))
                }))
    }

    /// Fixed values for snapshots: no UserDefaults or settings file is read or written.
    static func sample(chords: HotkeyChords = HotkeyChords(defaults: nil)) -> ShortcutsModel {
        ShortcutsModel(
            settings: .inMemory(), chords: chords, submitPhrase: .fixed(true), lineBreakPhrase: .fixed(false))
    }
}

/// Every way to dictate and to act on the last dictation, each with its recorder, then the spoken commands
/// (docs/research/ui-redesign.md, "Page map"). The rows say how each shortcut works, so the page is also the "How to
/// Dictate" card that 0.4's Home had.
private struct ShortcutsPage: View {
    @Bindable var model: ShortcutsModel

    var body: some View {
        PageForm {
            Section {
                PageHeader(
                    page: .shortcuts, summary: "Start a dictation in any app with a shortcut, and press keys by voice.")
            }
            Section("Dictate") {
                recorder(.handsFree, StatusText.shortcutHelp(.handsFree))
                recorder(.pushToTalk, StatusText.pushToTalkHelp(model.chords))
                recorder(.cleanup, StatusText.shortcutHelp(.cleanup))
                Picker("Cleanup model", selection: $model.cleanupModel) {
                    ForEach(CleanupModel.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(model.chords.cleanup == nil)
                PageRow(title: StatusText.cancelLabel, subtitle: StatusText.cancelHelp) {
                    Keycaps(keys: ["Esc"])
                }
            }
            Section("Last Dictation") {
                recorder(.pasteLast, StatusText.shortcutHelp(.pasteLast) + " Off until you record a shortcut.")
                recorder(.copyLast, StatusText.shortcutHelp(.copyLast))
                recorder(.polishLast, StatusText.shortcutHelp(.polishLast) + " Off until you record a shortcut.")
            }
            Section {
                Toggle(isOn: $model.isSubmitPhraseOn) {
                    Text("Press Return when you say “press enter”")
                    Text("Also “press return”. Say it last; kotoba leaves it out of the text.")
                }
                Toggle(isOn: $model.isLineBreakPhraseOn) {
                    Text("Start a new line when you say “new line”")
                    Text("“New paragraph” adds an empty line. Some terminals run each line as a command.")
                }
            } header: {
                Text("Voice Commands")
            } footer: {
                Text("Press Return while you dictate to stop: kotoba pastes the text, then presses Return.")
            }
        }
    }

    /// A chord's row: its name, how it works, and its recorder.
    private func recorder(_ role: HotkeyChords.Role, _ help: String) -> some View {
        PageRow(title: StatusText.shortcutTitle(role), subtitle: help) {
            ChordRecorder(chords: model.chords, role: role)
        }
    }
}

/// A spoken command setting the owner changed on the Shortcuts page.
enum PasteSetting: Sendable {
    case submitPhrase(Bool)
    case lineBreakPhrase(Bool)

    /// The one consumer: each change reaches the pipeline after the one before it.
    static func send(_ changes: AsyncStream<Self>, to pipeline: DictationPipeline) async {
        for await change in changes {
            switch change {
            case .submitPhrase(let isOn): await pipeline.updateSubmitPhrase(isOn: isOn)
            case .lineBreakPhrase(let isOn): await pipeline.updateLineBreakPhrase(isOn: isOn)
            }
        }
    }
}
