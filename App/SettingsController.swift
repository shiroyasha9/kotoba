import KotobaCore
import KotobaProviders
import KotobaStorage

/// Opens the Settings window with its panes, and owns the dictionary the Dictionary pane edits.
@MainActor
final class SettingsController {
    private let window = SettingsWindow()
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let microphones: MicrophonePreferences
    private let audio: AudioCapture
    private let router: TranscriptionRouter
    /// Builds the General pane's model each time the window builds its panes, so it shows current values.
    private let makeGeneral: @MainActor () -> GeneralModel
    /// The dictionary the Dictionary pane edits; "Fix Last Dictation…" adds to it and the menu counts its suggestions.
    /// Built once the dictionary file is read at launch.
    private(set) var dictionary: DictionaryModel?

    /// `router` checks a saved key in the Speech pane.
    init(
        routeSettings: TranscriptionSettings, vault: KeyVault, router: TranscriptionRouter,
        microphones: MicrophonePreferences, audio: AudioCapture, makeGeneral: @escaping @MainActor () -> GeneralModel
    ) {
        self.routeSettings = routeSettings
        self.vault = vault
        self.router = router
        self.microphones = microphones
        self.audio = audio
        self.makeGeneral = makeGeneral
    }

    /// Reads the personal dictionary (its own file, so its writes never block a dictation save)
    /// and hands it to the pipeline; Settings edits go to the pipeline from then on.
    func loadDictionary(into pipeline: DictationPipeline) async {
        do {
            let store = try DictionaryStore(url: HistoryStore.directory.appending(path: "dictionary.sqlite"))
            let loaded = try await store.load()
            await pipeline.updateDictionary(loaded)
            // The model calls this inside its serial save chain, so edits reach the pipeline in order.
            dictionary = DictionaryModel(dictionary: loaded, store: store) { await pipeline.updateDictionary($0) }
        } catch {
            Log.app.error("Cannot open the dictionary: \(error)")
        }
    }

    /// `pane` opens a given pane, e.g. Speech for the pill's "Add Key…"; nil keeps the pane shown.
    func show(selecting pane: SettingsPaneID? = nil) {
        window.show(panes(), selecting: pane)
    }

    private func panes() -> [SettingsPane] {
        var panes: [SettingsPane] = [.general(makeGeneral())]
        if let dictionary {
            panes.append(.dictionary(dictionary))
        }
        let audio = audio
        panes.append(
            .microphones(
                MicrophoneModel(source: .live(microphones, audio: audio)) { Task { await audio.inputMayHaveChanged() } }
            ))
        panes.append(
            .speech(SpeechSettingsModel(settings: routeSettings, vault: vault, checkKey: router.checkKey(_:for:))))
        return panes
    }
}
