import KotobaCore
import KotobaProviders
import KotobaStorage

/// Opens the main window with its panes (Home, History, Insights, Usage and the settings), and owns the dictionary the
/// Dictionary pane edits.
@MainActor
final class MainWindowController {
    private let window = MainWindow()
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
    /// The dictionary's file, whose learned words the Insights pane counts.
    private var dictionaryStore: DictionaryStore?
    /// The history whose usage ledger the Usage pane sums; set once the database opens at launch.
    var history: HistoryStore?
    /// Takes the Modes pane's changes and Home's Copy; set once it is built at launch.
    var pipeline: DictationPipeline?
    /// Builds the History pane; set once the history and the pipeline exist at launch.
    var historyPane: HistoryController?
    /// Home's status line and its fixes.
    private let readiness: Readiness
    private let finishSetup: @MainActor () -> Void
    private let fixLast: @MainActor () -> Void
    /// The last change sent to the pipeline: each waits for the one before, so the pipeline gets them in order.
    private var modesUpdate: Task<Void, Never>?
    /// Counts each delivered dictation's dictionary words for the app's lifetime (`DictationPipeline.termReports`).
    private var termReports: Task<Void, Never>?
    /// The open window's Usage and Insights pane models, which read again after each usage ledger write while shown;
    /// Insights also after each dictionary write.
    private weak var usage: UsageModel?
    private weak var insights: InsightsModel?
    /// The open window's General pane model; its History section measures the saved audio again the same way.
    private weak var general: GeneralModel?
    /// The open window's Home, which reads again after each history write while shown.
    private weak var home: HomeModel?

    /// `router` checks a saved key in the Speech pane. Home's buttons call `finishSetup` (onboarding on a missing
    /// permission) and `fixLast` (the Fix window).
    init(
        routeSettings: TranscriptionSettings, vault: KeyVault, router: TranscriptionRouter,
        microphones: MicrophonePreferences, audio: AudioCapture, readiness: Readiness,
        finishSetup: @escaping @MainActor () -> Void, fixLast: @escaping @MainActor () -> Void,
        makeGeneral: @escaping @MainActor () -> GeneralModel
    ) {
        self.readiness = readiness
        self.finishSetup = finishSetup
        self.fixLast = fixLast
        self.routeSettings = routeSettings
        self.vault = vault
        self.router = router
        self.microphones = microphones
        self.audio = audio
        self.makeGeneral = makeGeneral
        window.onClose = { [weak self] in self?.historyPane?.windowClosed() }
    }

    /// Reads the personal dictionary (its own file, so its writes never block a dictation save)
    /// and hands it to the pipeline; the Dictionary pane's edits go to the pipeline from then on.
    func loadDictionary(into pipeline: DictationPipeline) async {
        do {
            let store = try DictionaryStore(url: AppFiles.dictionary)
            let loaded = try await store.load()
            let use = try await store.termUse()
            dictionaryStore = store
            await pipeline.updateDictionary(loaded)
            await pipeline.updateTermUse(use)
            // The model calls these inside its serial save chain, so edits reach the pipeline in order, and Insights
            // reads the learned words after they are on disk.
            dictionary = DictionaryModel(
                dictionary: loaded, termUse: use, store: store,
                onSaved: { [weak self] in self?.insights?.storeChanged() },
                onTermUse: { await pipeline.updateTermUse($0) }, onChange: { await pipeline.updateDictionary($0) })
        } catch {
            Log.app.error("Cannot open the dictionary: \(error)")
        }
        termReports = Task { [weak self] in
            for await report in pipeline.termReports {
                self?.dictionary?.delivered(report)
            }
        }
    }

    /// A history write (from `DictationPipeline.historyChanges`): an open History pane reads the row it names, and each
    /// shown pane reads again only when the write changed what it shows. Home shows rows and ledger figures; Usage and
    /// Insights only ledger figures, so each dictation's pending save at upload start changes none of theirs. Insights
    /// also takes each answered dictation's recorded length, which a later row write keeps and a delete takes away (it
    /// falls back to the billed length). The History section measures the kept audio, which a ledger write leaves
    /// alone.
    func historyChanged(_ change: HistoryChange) {
        historyPane?.historyChanged(change)
        if change.isRowChanged || change.isUsageAdded {
            home?.historyChanged()
        }
        if change.isUsageAdded {
            usage?.ledgerChanged()
        }
        let isDeleted = if case .deleted = change { true } else { false }
        if change.isUsageAdded || isDeleted {
            insights?.storeChanged()
        }
        if change.isKeptAudioChanged {
            general?.audio?.keptAudioChanged()
        }
    }

    /// From `DictationPipeline.activity`: which dictations are being sent, and whether Paste Again can paste.
    func activityChanged(_ activity: PipelineActivity) {
        historyPane?.activityChanged(activity)
    }

    /// `pane` opens a given pane, e.g. Speech for the pill's "Add Key…"; nil keeps the pane shown, or opens the window
    /// at the pane it showed last (Home the first time).
    func show(selecting pane: PaneID? = nil) {
        window.show(panes(), selecting: pane)
    }

    /// "Settings…": the settings pane the window shows, else General.
    func showSettings() {
        show(selecting: window.shownPane?.isSetting == true ? nil : .general)
    }

    private func panes() -> [Pane] {
        let home = HomeModel(readiness: readiness, chords: .shared, source: homeSource)
        self.home = home
        var panes: [Pane] = [.home(home)]
        if let historyPane {
            panes.append(historyPane.pane())
        }
        let general = makeGeneral()
        self.general = general
        panes.append(.general(general))
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
                MicrophoneModel(source: .live(microphones, audio: audio, readiness: readiness)) {
                    Task { await audio.inputMayHaveChanged() }
                }
            ))
        panes.append(
            .speech(SpeechSettingsModel(settings: routeSettings, vault: vault, checkKey: router.checkKey(_:for:))))
        if let history {
            let usage = UsageModel { try await history.usage(from: $0, to: .distantFuture) }
            self.usage = usage
            panes.append(.usage(usage))
            // The dictionary at the read: the main window can open before it is read at launch.
            let insights = InsightsModel { [weak self] now in
                let dictionary = self?.dictionaryStore
                async let learned = dictionary?.learnedWords() ?? [:]
                return .init(history: try await history.insights(at: now, in: .current), learned: try await learned)
            }
            self.insights = insights
            panes.append(.insights(insights))
        }
        return panes
    }

    private var homeSource: HomeModel.Source {
        HomeModel.Source(
            read: { [weak self] now in
                guard let history = self?.history else { throw NoHistory() }
                // No top apps: Home does not show them.
                async let insights = history.insights(at: now, in: .current, apps: 0)
                async let recent = history.page(limit: HomeModel.recentCount)
                async let last = history.lastDelivered()
                let rows = try await recent
                return .init(
                    insights: try await insights, recent: rows, hasLastDictation: try await last != nil,
                    retryable: HistoryModel.kept(rows))
            },
            copy: { [weak self] in await self?.pipeline?.copyAgain($0) },
            fixLast: fixLast, finishSetup: finishSetup)
    }

    /// The history database did not open at launch: Home says it cannot read it.
    private struct NoHistory: Error {}

    private func send(_ modes: ModeRules) {
        guard let pipeline else { return }
        modesUpdate = Task { [previous = modesUpdate] in
            await previous?.value
            await pipeline.updateModes(modes)
        }
    }
}
