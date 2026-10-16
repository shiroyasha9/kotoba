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
    private let hotkeys = HotkeyTap(chords: .shared)
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
        openSpeechSettings: { [weak self] in self?.settingsController.show(selecting: .speech) })
    /// Its audio retention is set once the history opens (`AppDefaults.chooseAudioRetention`).
    private var settings = DictationPipeline.Settings(
        audioDirectory: AppFiles.audio,
        isSubmitPhraseOn: AppDefaults.isSubmitPhraseOn
    )
    private lazy var indicator = IndicatorPanel()
    lazy var fixWindow = FixLastDictationController(
        lastText: { [weak self] in await self?.lastDictation?.record()?.deliveredText },
        dictionary: { [weak self] in self?.settingsController.dictionary })
    lazy var learner = EditLearner(
        dictionary: { [weak self] in self?.settingsController.dictionary }, indicator: indicator)
    var statusItem: StatusBarItem?
    var pipeline: DictationPipeline?
    var store: HistoryStore?
    var state: DictationState = .idle
    var pendingCount = 0
    /// A dictation was pasted or copied, so "Fix Last Dictation…" has something to fix.
    var hasLastDictation = false
    /// The last dictation was cleaned up, so "Paste Last Without Cleanup" has the raw transcript.
    var hasRawLastDictation = false
    var lastDictation: LastDictation?
    /// The History window; built with the store, its window only when it opens.
    var history: HistoryController?
    private var queueRefresh: Task<Void, Never>?
    private var isQueueRefreshDue = false
    /// The submit phrase toggle, in click order, to the pipeline (one consumer, as for the Undo holds).
    let submitPhraseChanges = AsyncStream.makeStream(of: Bool.self)
    /// The History section's retention choices and "Delete Audio Now…", in click order, to the pipeline.
    let audioRequests = AsyncStream.makeStream(of: AudioRequest.self)
    /// Menu previews from the last 24 h, newest first; full transcripts stay in the store until copied.
    var recovered: [MenuChoice] = []
    private var isSecureInputOn = false
    /// Set when the history database does not open; the menu shows it instead of the status.
    var launchIssue: String?
    let updater = Updater.forThisBuild()
    lazy var settingsController = SettingsController(
        routeSettings: routeSettings, vault: vault, router: router, microphones: microphones, audio: audio
    ) { [routeSettings, indicator, updater, weak self] in
        GeneralModel(
            settings: routeSettings, indicator: indicator, updater: updater,
            audio: self.flatMap { app in
                app.store.map { .live(requests: app.audioRequests.continuation, store: $0) }
            }
        ) {
            self?.submitPhraseChanged(isOn: $0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CGEventPaster.trackKeyboardLayout()
        FrontAppObserver.track()
        CGEventPaster.warmUp()
        NSApp.mainMenu = .hiddenMain()
        statusItem = StatusBarItem(target: self) { [weak self] in self?.menuModel() }
        updater?.onWaitingUpdateChange = { [weak self] in self?.updateIcon() }
        guard let store = openHistory() else { return }
        let pipeline = DictationPipeline(
            ports: .init(
                audio: audio,
                provider: router,
                paster: CGEventPaster(),
                pasteboard: SystemPasteboard(),
                clock: SystemClock(),
                store: store,
                cleaner: OpenRouterCleaner(apiKey: vault.source(for: .openRouter), settings: routeSettings),
                missingSetup: { [vault, routeSettings] in routeSettings.missingSetup(hasKey: vault.hasKey(for:)) },
                readback: learner.readback,
                frontApp: { FrontAppObserver.current }
            ),
            settings: settings
        )
        self.pipeline = pipeline
        lastDictation = LastDictation(store: store, pipeline: pipeline)
        history = HistoryController(store: store, pipeline: pipeline)

        observe(pipeline)
        observeReadiness()
        setup.showOnboardingIfNew()
        setup.watchGrants()
        Task {
            await settingsController.loadDictionary(into: pipeline)
            await pipeline.retryPending()
            await refreshQueues()
        }
        startHotkeys(feeding: pipeline)
        // With "Show indicator: Always" the idle pill appears after the launch work, so building it (about 50 ms)
        // never delays the hotkey tap.
        Task { indicator.show(state, context: statusContext) }
        // Story 22: the pipeline sends failed dictations again when the network returns.
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
            launchIssue = StatusText.historyUnavailable
            return nil
        }
        self.store = store
        settings.audioRetention = AppDefaults.chooseAudioRetention(hadDictations: store.hadDictationsAtOpen)
        settingsController.history = store
        return store
    }

    /// Quit waits until a live recording or an open Undo window is saved, so no audio is lost.
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
        Task { [submitPhrases = submitPhraseChanges.stream] in
            for await isOn in submitPhrases {
                await pipeline.updateSubmitPhrase(isOn: isOn)
            }
        }
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
                history?.activityChanged(activity)
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
        await refreshQueues()
    }

    var statusContext: StatusContext {
        StatusContext(
            provider: routeSettings.route.account, microphone: readiness.microphone,
            isPasteAllowed: readiness.isAccessibilityAllowed, isSecureInputOn: isSecureInputOn,
            microphoneName: audio.inputInUse?.name,
            longRecordingMinutes: Int(settings.longRecordingWarning / .seconds(60)), undoWindow: settings.undoWindow)
    }

    private func render(_ newState: DictationState) {
        let wasRecording = if case .recording = state { true } else { false }
        state = newState
        learner.dictationStateChanged(newState)
        if case .recording = newState {
            if !wasRecording {
                isSecureInputOn = IsSecureEventInputEnabled()
                playCue("Tink")
            }
            hotkeys.setRecordingShown(true)
        } else {
            hotkeys.setRecordingShown(false)
            if wasRecording, newState == .transcribing {
                playCue("Pop")
            }
        }
        updateIcon()
        switch newState {
        // Their text and button depend on the mic and Accessibility grants now (I2).
        case .captureFailed, .copied: readiness.refresh()
        default: break
        }
        indicator.show(newState, context: statusContext)
    }

    private func playCue(_ name: String) {
        guard AppDefaults.areSoundCuesOn else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// One serial consumer keeps the events in order; it runs off the main actor so a busy UI
    /// does not delay key-down.
    private func startHotkeys(feeding pipeline: DictationPipeline) {
        let hotkeys = hotkeys
        Task.detached {
            for await (event, instant) in hotkeys.events {
                await pipeline.handle(event, at: instant)
            }
        }
        Task {
            await setup.startHotkeys(hotkeys)
            CGEventPaster.isTrusted = true
            Log.app.info("Hotkey tap started")
            // Story 31: launch's turn for audio retention, once dictation works; the pipeline and store do it off main.
            await pipeline.deleteExpiredAudio()
        }
    }
}

// MARK: - History writes

extension AppDelegate {
    /// Each history write can change the Retry count, the Recovered list, "Fix Last Dictation…", an open History window
    /// and a shown Usage pane.
    private func historyChanged(_ change: HistoryChange) {
        history?.historyChanged(change)
        settingsController.historyChanged(change)
        scheduleQueueRefresh()
    }

    /// A dictation writes the history two or three times; the menu reads its counts once for such a burst: one
    /// refresh runs, and one more when a write came during it.
    private func scheduleQueueRefresh() {
        isQueueRefreshDue = true
        guard queueRefresh == nil else { return }
        queueRefresh = Task {
            while isQueueRefreshDue {
                isQueueRefreshDue = false
                await refreshQueues()
            }
            queueRefresh = nil
        }
    }

    func refreshQueues() async {
        guard let store, let pipeline else { return }
        recovered = await pipeline.retries.recovered().map { record in
            let preview = (record.deliveredText ?? "").prefix(41)
            let title = preview.count > 40 ? String(preview.prefix(40)) + "…" : String(preview)
            return MenuChoice(title: title, value: record.id.rawValue.uuidString)
        }
        do {
            pendingCount = try await store.pendingCount()
        } catch {
            Log.app.error("Cannot read the dictation history: \(error)")
        }
        let last = await lastDictation?.record()
        hasLastDictation = last != nil
        hasRawLastDictation = last.flatMap(LastDictation.rawText) != nil
        updateIcon()
    }
}
