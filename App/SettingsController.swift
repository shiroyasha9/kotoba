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
    /// Built once the dictionary file is read at launch.
    private var dictionary: DictionaryModel?

    init(routeSettings: TranscriptionSettings, vault: KeyVault, microphones: MicrophonePreferences, audio: AudioCapture)
    {
        self.routeSettings = routeSettings
        self.vault = vault
        self.microphones = microphones
        self.audio = audio
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

    /// `pane` opens a given pane, e.g. Providers for "Set API Key…"; nil keeps the pane shown.
    func show(selecting pane: SettingsPaneID? = nil) {
        window.show(panes(), selecting: pane)
    }

    private func panes() -> [SettingsPane] {
        var panes: [SettingsPane] = []
        if let dictionary {
            panes.append(.dictionary(dictionary))
        }
        let audio = audio
        panes.append(
            .microphones(
                MicrophoneModel(source: .live(microphones, audio: audio)) { Task { await audio.inputMayHaveChanged() } }
            ))
        panes.append(.providers(ProvidersModel(settings: routeSettings, vault: vault)))
        return panes
    }
}
