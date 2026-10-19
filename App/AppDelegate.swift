import AVFAudio
import AppKit
import Carbon
import KotobaCore
import KotobaProviders
import KotobaStorage
import Network
import Observation
import os

/// Wires the ports to the pipeline and owns the menu bar item. Windows are built on demand.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotkeys = HotkeyTap(chords: .shared)
    let microphones = MicrophonePreferences()
    lazy var audio = AudioCapture(preferences: microphones)
    /// Read by the provider on every request, so a menu change applies to the next dictation.
    let routeSettings = TranscriptionSettings()
    private let vault = KeyVault()
    lazy var readiness = Readiness(settings: routeSettings, vault: vault)
    /// The provider; onboarding uses it to check a key.
    private lazy var router = TranscriptionRouter(settings: routeSettings, keys: vault.source(for:))
    lazy var setup = SetupFlow(
        readiness: readiness, routeSettings: routeSettings, vault: vault, router: router,
        dictionary: { [weak self] in self?.mainWindow.dictionary },
        openSpeechSettings: { [weak self] in self?.mainWindow.show(selecting: .speech) })
    /// Its audio retention is set once the history opens (`AppDefaults.chooseAudioRetention`).
    private var settings = DictationPipeline.Settings(
        audioDirectory: AppFiles.audio,
        isSubmitPhraseOn: AppDefaults.isSubmitPhraseOn,
        isLineBreakPhraseOn: AppDefaults.isLineBreakPhraseOn,
        modes: AppDefaults.modeRules
    )
    lazy var indicator = IndicatorPanel()
    let cues = SoundCues()
    lazy var fixWindow = FixLastDictationController(
        last: { [weak self] in await self?.lastDictation?.record() },
        dictionary: { [weak self] in self?.mainWindow.dictionary })
    lazy var learner = EditLearner(
        dictionary: { [weak self] in self?.mainWindow.dictionary }, indicator: indicator)
    var statusItem: StatusBarItem?
    var pipeline: DictationPipeline?
    var store: HistoryStore?
    /// What the menu bar icon, the menus, the Dock badge and the cues show (`ShellStatus`).
    var shell = ShellStatus()
    var lastDictation: LastDictation?
    /// The spoken command toggles, in click order, to the pipeline (one consumer, as for the Undo holds).
    let pasteSettingChanges = AsyncStream.makeStream(of: PasteSetting.self)
    /// The History section's retention choices and "Delete Audio Now…", in click order, to the pipeline.
    let audioRequests = AsyncStream.makeStream(of: AudioRequest.self)
    private var isSecureInputOn = false
    let updater = Updater.forThisBuild()
    /// A development build gives way while the release app runs (`InstallYield`).
    let releaseWatcher = ReleaseAppWatcher()
    lazy var mainMenu = MainMenu(target: self) { [weak self] in self?.updates }
    lazy var mainWindow: MainWindowController = MainWindowController(
        routeSettings: routeSettings, vault: vault, router: router, microphones: microphones, audio: audio,
        readiness: readiness, finishSetup: { [weak self] in self?.setup.finishSetup() },
        fixLast: { [weak self] in self?.fixWindow.show() },
        makeGeneral: { [routeSettings, indicator, cues, updater, weak self] in
            GeneralModel(
                settings: routeSettings, indicator: indicator, cues: cues, updater: updater,
                audio: self.flatMap { app in
                    app.store.map { .live(requests: app.audioRequests.continuation, store: $0) }
                }
            ) {
                self?.pasteSettingChanged($0)
            }
        })

    func applicationDidFinishLaunching(_ notification: Notification) {
        // First, so the Dock icon comes before any window (story 35).
        DockAndMenuBar.shared.start()
        let launch = DockAndMenuBar.launch()
        // A recording file made after this is never taken for an orphan (`OrphanAudio`).
        let launchedAt = Date.now
        CGEventPaster.trackKeyboardLayout()
        FrontAppObserver.track()
        // From launch, so a ⌘C in kotoba's windows before the first dictation is known.
        OwnClipboardWrites.shared.start()
        CGEventPaster.warmUp()
        mainMenu.install()
        statusItem = DockAndMenuBar.shared.attach(StatusBarItem(target: self) { [weak self] in self?.menuModel() })
        updater?.onWaitingUpdateChange = { [weak self] in self?.updateIcon() }
        guard let store = openHistory() else { return }
        let cleaner = OpenRouterCleaner(apiKey: vault.source(for: .openRouter), settings: routeSettings)
        let pipeline = DictationPipeline(
            ports: .init(
                audio: audio,
                provider: router,
                paster: CGEventPaster(), pasteboard: SystemPasteboard(), clock: SystemClock(),
                store: store,
                cleaner: cleaner,
                missingSetup: { [vault, routeSettings] in routeSettings.missingSetup(hasKey: vault.hasKey(for:)) },
                readback: learner.readback,
                // The polisher shares the cleanup connection: OpenRouter's chat keeps one URLSession.
                frontApp: { FrontAppObserver.current }, polisher: cleaner.polisher(), selector: AXPastedTextSelector(),
                inputMark: { [hotkeys] in hotkeys.inputMark() },
                isMicrophoneAllowed: { Readiness.Microphone.current == .allowed }
            ),
            settings: settings
        )
        self.pipeline = pipeline
        mainWindow.pipeline = pipeline
        lastDictation = LastDictation(store: store, pipeline: pipeline)
        mainWindow.historyPane = HistoryController(
            store: store, pipeline: pipeline, routes: routeSettings, keys: vault
        ) { [weak self] in self?.fixWindow.show($0) }
        observe(pipeline)
        observeReadiness()
        let dictionaryRead = Task { await mainWindow.loadDictionary(into: pipeline) }
        openWindow(at: launch, after: dictionaryRead)
        setup.watchGrants()
        watchReleaseApp()
        Task {
            await dictionaryRead.value
            // Audio left with no row (a crash during a recording) joins this launch's retry.
            await OrphanAudioRecovery.run(in: AppFiles.audio, store: store, launchedAt: launchedAt)
            await pipeline.retryAtLaunch()
            refreshQueues()
        }
        startHotkeys(feeding: pipeline)
        // With "Show indicator: Always" the idle pill appears after the launch work, so building it (about 50 ms)
        // never delays the hotkey tap.
        Task { indicator.show(shell.dictation, context: statusContext) }
        watchNetwork(for: pipeline)
        AwayWatcher.watch(feeding: pipeline)
    }

    /// Story 22: the pipeline sends failed dictations again when the network returns.
    private func watchNetwork(for pipeline: DictationPipeline) {
        Task.detached {
            for await path in NWPathMonitor() {
                await pipeline.networkChanged(isOnline: path.status == .satisfied)
            }
        }
    }

    /// The history database, and the audio retention it decides on its first open (`AppDefaults.chooseAudioRetention`).
    /// Nil when it does not open; the menu then says so.
    private func openHistory() -> HistoryStore? {
        let store: HistoryStore
        do {
            store = try HistoryStore(url: AppFiles.history, audio: AppFiles.audio)
        } catch {
            Log.app.fault("Cannot open the history database: \(error)")
            shell.isHistoryUnavailable = true
            return nil
        }
        self.store = store
        settings.audioRetention = AppDefaults.chooseAudioRetention(hadDictations: store.hadDictationsAtOpen)
        mainWindow.history = store
        return store
    }

    /// Quit waits until a live recording or an open Undo window is saved, so no audio is lost, and up to 3 s for a
    /// dictation being sent (`DictationPipeline.shutdown`).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let pipeline else { return .terminateNow }
        Task {
            await pipeline.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: Pipeline wiring

    private func observe(_ pipeline: DictationPipeline) {
        indicator.onAction = { [weak self] action in
            self?.perform(action)
        }
        // The pointer on the Undo pill holds the pipeline's Undo window; one consumer keeps the holds in order.
        let (undoHolds, undoHold) = AsyncStream.makeStream(of: Bool.self)
        indicator.onUndoHoldChanged = { undoHold.yield($0) }
        Task {
            for await isHeld in undoHolds {
                await pipeline.holdUndoWindow(isHeld)
            }
        }
        Task { [pasteSettings = pasteSettingChanges.stream] in await PasteSetting.send(pasteSettings, to: pipeline) }
        Task { [audioRequests = audioRequests.stream] in await AudioRequest.send(audioRequests, to: pipeline) }
        // A click on the idle or recording pill is a chord tap; the front app keeps focus, so the paste goes there.
        indicator.onTap = { [hotkeys] in hotkeys.sendTap() }
        Task {
            for await state in pipeline.states {
                render(state)
            }
        }
        Task {
            for await change in pipeline.historyChanges {
                historyChanged(change)
            }
        }
        Task {
            for await activity in pipeline.activity {
                mainWindow.activityChanged(activity)
            }
        }
        Task { [audio, indicator] in
            for await level in audio.levels {
                indicator.showLevel(level)
            }
        }
        // A saved key, endpoint or route can complete the setup; the dictations that waited for it are sent then.
        Task { [vault] in
            for await _ in vault.changes {
                await setupChanged(pipeline)
            }
        }
        Task {
            for await note in NotificationCenter.default.notifications(named: TranscriptionSettings.didChange) {
                let change = note.object as? TranscriptionSettings.Change
                if change == .azureEndpoint || change == .route {
                    await setupChanged(pipeline)
                }
            }
        }
    }

    /// No permission prompt at launch: onboarding asks (O2). The engine is prepared once the mic is allowed,
    /// and the icon follows the setup state.
    private func observeReadiness() {
        let readiness = readiness
        Task {
            for await microphone in Observations({ readiness.microphone }) where microphone == .allowed {
                await audio.prepare()
            }
        }
        Task {
            for await _ in Observations({ readiness.isComplete }) {
                updateIcon()
            }
        }
    }

    private func setupChanged(_ pipeline: DictationPipeline) async {
        readiness.refresh()
        await pipeline.setupChanged()
        refreshQueues()
    }

    private func render(_ newState: DictationState) {
        let reactions = shell.dictationChanged(newState)
        learner.dictationStateChanged(newState)
        // Before the cue: a stopped recording lets Esc and Return through to the front app at once.
        hotkeys.setRecordingShown(reactions.isRecordingShown)
        if reactions.readsSecureInput {
            isSecureInputOn = IsSecureEventInputEnabled()
        }
        if let cue = reactions.cue {
            cues.play(cue)
        }
        if reactions.readsGrants {
            readiness.refresh()
        }
        if reactions.readsQueues {
            refreshQueues()
        }
        updateIcon()
        indicator.show(newState, context: statusContext)
    }

    /// One serial consumer keeps the events in order; it runs off the main actor so a busy UI
    /// does not delay key-down.
    private func startHotkeys(feeding pipeline: DictationPipeline) {
        let hotkeys = hotkeys
        // A click on the pill is a chord tap (`indicator.onTap`), not a click that drops a press.
        hotkeys.mouse.isPillWindow = { [indicator] in indicator.holds($0) }
        Task.detached {
            for await (event, instant) in hotkeys.events {
                await pipeline.handle(event, at: instant)
            }
        }
        Task {
            await setup.startHotkeys(hotkeys)
            Log.app.info("Hotkey tap started")
            // Story 31: launch's turn for audio retention, once dictation works; the pipeline and store do it off main.
            await pipeline.deleteExpiredAudio()
        }
    }
}

// MARK: - Status

extension AppDelegate {
    /// What the pill and the menu status line read besides the state.
    var statusContext: StatusContext {
        StatusContext(
            provider: routeSettings.route.account, microphone: readiness.microphone,
            isPasteAllowed: readiness.isAccessibilityAllowed, isSecureInputOn: isSecureInputOn,
            microphoneName: audio.inputInUse?.name,
            longRecordingMinutes: Int(settings.longRecordingWarning / .seconds(60)), undoWindow: settings.undoWindow,
            isYielding: releaseWatcher.isYielding)
    }

    /// What the shell reads from the other owners at each draw.
    var shellFacts: ShellStatus.Facts<Readiness.Missing> {
        ShellStatus.Facts(
            firstMissing: readiness.firstMissing, isYielding: releaseWatcher.isYielding,
            hasWaitingUpdate: updater?.hasWaitingUpdate == true)
    }
}

// MARK: - History writes

extension AppDelegate {
    /// Each history write can change the Retry count, the Recovered list, "Fix Last Dictation…" and the open main
    /// window's panes.
    private func historyChanged(_ change: HistoryChange) {
        mainWindow.historyChanged(change)
        if change.isRowChanged { refreshQueues() }
    }

    /// Reads the menu's counts, or once more after the read in progress (`ShellStatus.queueReadRequested`).
    func refreshQueues() {
        guard shell.queueReadRequested() else { return }
        Task {
            var isDue = true
            while isDue {
                let queues = await readQueues()
                isDue = shell.queueRead(queues)
                DockAndMenuBar.shared.waitingCount = shell.queues.waitingCount
                updateIcon()
            }
        }
    }

    /// A count the history cannot read keeps its last value.
    private func readQueues() async -> ShellStatus.Queues {
        guard let store, let pipeline else { return shell.queues }
        let recovered = await pipeline.retries.recovered()
        var waitingCount = shell.queues.waitingCount
        do {
            waitingCount = try await store.pendingCount()
        } catch {
            Log.app.error("Cannot read the dictation history: \(error)")
        }
        let last = await lastDictation?.record()
        return ShellStatus.Queues(
            waitingCount: waitingCount, recovered: recovered, hasLastDictation: last != nil,
            hasRawLastDictation: last.flatMap(LastDictation.rawText) != nil)
    }
}
