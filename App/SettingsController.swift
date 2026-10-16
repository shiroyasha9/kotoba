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
    /// The history whose usage ledger the Usage pane sums; set once the database opens at launch.
    var history: HistoryStore?
    /// Takes the Modes pane's changes; set once it is built at launch.
    var pipeline: DictationPipeline?
    /// The last change sent to the pipeline: each waits for the one before, so the pipeline gets them in order.
    private var modesUpdate: Task<Void, Never>?
    /// The open window's Usage pane model, which reads again after each history write while it is shown.
    private weak var usage: UsageModel?
    /// The open window's General pane model; its History section measures the saved audio again the same way.
    private weak var general: GeneralModel?

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
            let store = try DictionaryStore(url: AppFiles.dictionary)
            let loaded = try await store.load()
            await pipeline.updateDictionary(loaded)
            // The model calls this inside its serial save chain, so edits reach the pipeline in order.
            dictionary = DictionaryModel(dictionary: loaded, store: store) { await pipeline.updateDictionary($0) }
        } catch {
            Log.app.error("Cannot open the dictionary: \(error)")
        }
    }

    /// A history write (from `DictationPipeline.historyChanges`): a shown Usage pane or History section reads again.
    /// Deleted audio changes no usage.
    func historyChanged(_ change: HistoryChange) {
        if case .audioDeleted = change {} else { usage?.historyChanged() }
        general?.audio?.historyChanged()
    }

    /// `pane` opens a given pane, e.g. Speech for the pill's "Add Key…"; nil keeps the pane shown.
    func show(selecting pane: SettingsPaneID? = nil) {
        window.show(panes(), selecting: pane)
    }

    private func panes() -> [SettingsPane] {
        let general = makeGeneral()
        self.general = general
        var panes: [SettingsPane] = [.general(general)]
        if let dictionary {
            panes.append(.dictionary(dictionary))
        }
        panes.append(
            .modes(
                ModesModel(
                    source: .live(
                        history: history, hasCleanupKey: { [vault] in vault.hasKey(for: .openRouter) },
                        addKey: { [weak self] in self?.show(selecting: .speech) },
                        send: { [weak self] in self?.send($0) }))))
        let audio = audio
        panes.append(
            .microphones(
                MicrophoneModel(source: .live(microphones, audio: audio)) { Task { await audio.inputMayHaveChanged() } }
            ))
        panes.append(
            .speech(SpeechSettingsModel(settings: routeSettings, vault: vault, checkKey: router.checkKey(_:for:))))
        if let history {
            let usage = UsageModel { try await history.usage(from: $0, to: .distantFuture) }
            self.usage = usage
            panes.append(.usage(usage))
        }
        return panes
    }

    private func send(_ modes: ModeRules) {
        guard let pipeline else { return }
        modesUpdate = Task { [previous = modesUpdate] in
            await previous?.value
            await pipeline.updateModes(modes)
        }
    }
}
