import KotobaCore
import KotobaProviders
import KotobaStorage

/// Opens the main window with its panes (Home, History, Activity and the settings), and owns the dictionary the
/// Dictionary pane edits.
@MainActor
final class MainWindowController {
    private let window = MainWindow()
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let microphones: MicrophonePreferences
    private let audio: AudioCapture
    private let router: TranscriptionRouter
    /// Build the General and Shortcuts pages' models each time the window builds its panes, so they show current
    /// values.
    private let makeGeneral: @MainActor () -> GeneralModel
    private let makeShortcuts: @MainActor () -> ShortcutsModel
    /// The dictionary the Dictionary pane edits; "Fix Last Dictation…" adds to it and the menu counts its suggestions.
    /// Built once the dictionary file is read at launch.
    private(set) var dictionary: DictionaryModel?
    /// The dictionary's file, whose learned words the Activity page counts.
    private var dictionaryStore: DictionaryStore?
    /// The history whose usage ledger Activity sums; set once the database opens at launch.
    var history: HistoryStore?
    /// Takes the Modes pane's changes and Home's Copy; set once it is built at launch.
    var pipeline: DictationPipeline?
    /// Builds the History pane; set once the history and the pipeline exist at launch.
    var historyPane: HistoryController?
    /// Home's setup problem and its fix.
    private let readiness: Readiness
    private let finishSetup: @MainActor () -> Void
    private let tryIt: @MainActor () -> Void
    private let fixLast: @MainActor () -> Void
    /// The last change sent to the pipeline: each waits for the one before, so the pipeline gets them in order.
    private var modesUpdate: Task<Void, Never>?
    /// Counts each delivered dictation's dictionary words for the app's lifetime (`DictationPipeline.termReports`).
    private var termReports: Task<Void, Never>?
    /// The open window's Activity page model, which reads again after each usage ledger, insights or dictionary write
    /// while shown.
    private weak var activity: ActivityModel?
    /// The open window's General pane model; its History section measures the saved audio again the same way.
    private weak var general: GeneralModel?
    /// The pipeline's newest activity, kept while the window is closed so Home opens with it.
    private var pipelineActivity = PipelineActivity(isQuiet: true, inFlight: [])
    /// The open window's Home, which reads again after each history write while shown.
    private weak var home: HomeModel?
    /// The open window's Speech page model, whose "Advanced…" sheet another window can open.
    private weak var speech: SpeechSettingsModel?

    /// `router` checks a saved key in the Speech pane. Home's buttons call `finishSetup` (onboarding on a missing
    /// permission), `tryIt` (onboarding's Try It step) and `fixLast` (the Fix window).
    init(
        routeSettings: TranscriptionSettings, vault: KeyVault, router: TranscriptionRouter,
        microphones: MicrophonePreferences, audio: AudioCapture, readiness: Readiness,
        finishSetup: @escaping @MainActor () -> Void, tryIt: @escaping @MainActor () -> Void,
        fixLast: @escaping @MainActor () -> Void, makeGeneral: @escaping @MainActor () -> GeneralModel,
        makeShortcuts: @escaping @MainActor () -> ShortcutsModel
    ) {
        self.readiness = readiness
        self.finishSetup = finishSetup
        self.tryIt = tryIt
        self.fixLast = fixLast
        self.routeSettings = routeSettings
        self.vault = vault
        self.router = router
        self.microphones = microphones
        self.audio = audio
        self.makeGeneral = makeGeneral
        self.makeShortcuts = makeShortcuts
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
            // The model calls these inside its serial save chain, so edits reach the pipeline in order, and Activity
            // reads the learned words after they are on disk.
            dictionary = DictionaryModel(
                dictionary: loaded, termUse: use, store: store,
                onSaved: { [weak self] in self?.activity?.storeChanged() },
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
    /// shown pane reads again only when the write changed what it shows. Home shows rows and ledger figures; Activity
    /// only ledger figures, so each dictation's pending save at upload start changes none of its. Activity also takes
    /// each answered dictation's recorded length, which a later row write keeps and a delete takes away (it falls back
    /// to the billed length). The History section measures the kept audio, which a ledger write leaves
    /// alone.
    func historyChanged(_ change: HistoryChange) {
        historyPane?.historyChanged(change)
        home?.historyChanged(change)
        if change.isUsageAdded || change.isInsightsChanged {
            activity?.storeChanged()
        }
        if change.isKeptAudioChanged {
            general?.audio?.keptAudioChanged()
        }
    }

    /// From `DictationPipeline.activity`: which dictations are being sent, and whether Paste Again can paste.
    func activityChanged(_ activity: PipelineActivity) {
        self.pipelineActivity = activity
        historyPane?.activityChanged(activity)
        home?.activity = activity
    }

    /// `pane` opens a given pane, e.g. Speech for the pill's "Add Key…"; nil keeps the pane shown, or opens the window
    /// at the pane it showed last (Home the first time).
    func show(selecting pane: PaneID? = nil) {
        window.show(panes(), selecting: pane)
    }

    /// The Speech page with its "Advanced…" sheet open, where the xAI and Azure routes are: onboarding's “Use xAI or
    /// Azure Instead…”.
    func showOtherSpeechServices() {
        show(selecting: .speech)
        speech?.isAdvancedShown = true
    }

    /// "Settings…": the settings pane the window shows, else General.
    func showSettings() {
        show(selecting: window.shownPane?.isSetting == true ? nil : .general)
    }

    private func panes() -> [Pane] {
        let home = HomeModel(readiness: readiness, chords: .shared, source: homeSource, activity: pipelineActivity)
        self.home = home
        var panes: [Pane] = [.home(home)]
        if let historyPane {
            panes.append(historyPane.pane())
        }
        let general = makeGeneral()
        self.general = general
        panes.append(.general(general))
        panes.append(.shortcuts(makeShortcuts()))
        if let dictionary {
            panes.append(.dictionary(dictionary))
        }
        panes.append(
            .modes(
                ModesModel(
                    source: .live(
                        history: history, settings: routeSettings,
                        hasCleanupKey: { [vault] in vault.hasKey(for: .openRouter) },
                        addKey: { [weak self] in self?.show(selecting: .speech) },
                        send: { [weak self] in self?.send($0) }),
                    chords: .shared)))
        let audio = audio
        panes.append(
            .microphones(
                MicrophoneModel(source: .live(microphones, audio: audio, readiness: readiness)) {
                    Task { await audio.inputMayHaveChanged() }
                }
            ))
        let speech = SpeechSettingsModel(settings: routeSettings, vault: vault, checkKey: router.checkKey(_:for:))
        self.speech = speech
        panes.append(.speech(speech))
        if let history {
            // The dictionary at the read: the main window can open before it is read at launch.
            let activity = ActivityModel { [weak self] now in
                let dictionary = self?.dictionaryStore
                async let learned = dictionary?.learnedWords() ?? [:]
                async let month = history.usage(from: ActivityModel.monthStart(at: now), to: .distantFuture)
                // No all-time top apps: Activity shows this month's (`UsageSummary.apps`).
                return .init(
                    insights: try await history.insights(at: now, in: .current, apps: 0), learned: try await learned,
                    month: try await month)
            }
            self.activity = activity
            panes.append(.activity(activity))
        }
        return panes
    }

    private var homeSource: HomeModel.Source {
        HomeModel.Source(
            readInsights: { [weak self] now in
                guard let history = self?.history else { throw NoHistory() }
                // No top apps: Home does not show them.
                return try await history.insights(at: now, in: .current, apps: 0)
            },
            readRows: { [weak self] in
                guard let history = self?.history else { throw NoHistory() }
                async let recent = history.page(limit: HomeModel.recentCount)
                async let last = history.lastDelivered()
                return (try await recent, try await last?.id)
            },
            copy: { [weak self] in await self?.pipeline?.copyAgain($0) },
            paste: { [weak self] text, id in
                guard let pipeline = self?.pipeline else { return true }
                return await PasteAgain(pipeline: pipeline)(text, of: id)
            },
            fixLast: fixLast, finishSetup: finishSetup, tryIt: tryIt)
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
