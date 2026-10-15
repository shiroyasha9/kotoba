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
    private let hotkeys = HotkeyTap(cleanupChord: CleanupChord.current.modifiers)
    private let microphones = MicrophonePreferences()
    private lazy var audio = AudioCapture(preferences: microphones)
    /// Read by the provider on every request, so a menu change applies to the next dictation.
    private let routeSettings = TranscriptionSettings()
    private let vault = KeyVault()
    private lazy var readiness = Readiness(settings: routeSettings, vault: vault)
    /// The provider; onboarding uses it to check a key.
    private lazy var router = TranscriptionRouter(settings: routeSettings, keys: vault.source(for:))
    private lazy var setup = SetupFlow(
        readiness: readiness, routeSettings: routeSettings, vault: vault, router: router,
        openSpeechSettings: { [weak self] in self?.settingsController.show(selecting: .speech) })
    private let settings = DictationPipeline.Settings(
        audioDirectory: HistoryStore.directory.appending(path: "audio", directoryHint: .isDirectory)
    )
    private lazy var indicator = IndicatorPanel()
    private lazy var fixWindow = FixLastDictationController(
        lastText: { [weak self] in await self?.lastDeliveredText() },
        dictionary: { [weak self] in self?.settingsController.dictionary })
    private var statusItem: StatusBarItem?
    private var pipeline: DictationPipeline?
    private var store: HistoryStore?
    private var state: DictationState = .idle
    private var pendingCount = 0
    /// A dictation was pasted or copied, so "Fix Last Dictation…" has something to fix.
    private var hasLastDictation = false
    /// Menu previews from the last 24 h, newest first; full transcripts stay in the store until copied.
    private var recovered: [MenuChoice] = []
    private var isSecureInputOn = false
    /// Set when the history database does not open; the menu shows it instead of the status.
    private var launchIssue: String?
    private lazy var settingsController = SettingsController(
        routeSettings: routeSettings, vault: vault, router: router, microphones: microphones, audio: audio
    ) { [routeSettings, indicator, hotkeys] in
        GeneralModel(settings: routeSettings, indicator: indicator, setCleanupChord: hotkeys.setCleanupChord)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        CGEventPaster.trackKeyboardLayout()
        CGEventPaster.warmUp()
        NSApp.mainMenu = .editOnlyMain()
        statusItem = StatusBarItem(target: self) { [weak self] in self?.menuModel() }
        let store: HistoryStore
        do {
            store = try HistoryStore()
        } catch {
            Log.app.fault("Cannot open the history database: \(error)")
            launchIssue = StatusText.historyUnavailable
            return
        }
        self.store = store
        let pipeline = DictationPipeline(
            ports: .init(
                audio: audio,
                provider: router,
                paster: CGEventPaster(),
                pasteboard: SystemPasteboard(),
                clock: SystemClock(),
                store: store,
                cleaner: OpenRouterCleaner(apiKey: vault.source(for: .openRouter), settings: routeSettings),
                missingSetup: { [vault, routeSettings] in routeSettings.missingSetup(hasKey: vault.hasKey(for:)) }
            ),
            settings: settings
        )
        self.pipeline = pipeline

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
        // Story 22: the pipeline sends failed dictations again when the network returns.
        Task.detached {
            for await path in NWPathMonitor() {
                await pipeline.networkChanged(isOnline: path.status == .satisfied)
            }
        }
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
        Task {
            for await state in pipeline.states {
                render(state)
            }
        }
        // Each history write can change the Retry count, the Recovered list and "Fix Last Dictation…".
        Task {
            for await _ in pipeline.historyChanges {
                await refreshQueues()
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

    private var statusContext: StatusContext {
        StatusContext(
            provider: routeSettings.route.account, microphone: readiness.microphone,
            isPasteAllowed: readiness.isAccessibilityAllowed, isSecureInputOn: isSecureInputOn,
            longRecordingMinutes: Int(settings.longRecordingWarning / .seconds(60)))
    }

    private func render(_ newState: DictationState) {
        let wasRecording = if case .recording = state { true } else { false }
        state = newState
        if case .recording = newState {
            if !wasRecording {
                isSecureInputOn = IsSecureEventInputEnabled()
                playCue("Tink")
            }
            hotkeys.setSwallowsEscape(true)
        } else {
            hotkeys.setSwallowsEscape(false)
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
        }
    }

    private func refreshQueues() async {
        guard let store, let pipeline else { return }
        recovered = await pipeline.retries.recovered().map { record in
            let preview = (record.deliveredText ?? "").prefix(41)
            let title = preview.count > 40 ? String(preview.prefix(40)) + "…" : String(preview)
            return MenuChoice(title: title, value: record.id.rawValue.uuidString)
        }
        do {
            pendingCount = try await store.pendingCount()
            hasLastDictation = try await store.lastDelivered() != nil
        } catch {
            Log.app.error("Cannot read the dictation history: \(error)")
        }
        updateIcon()
    }

    // MARK: Pill actions

    private func perform(_ action: PillAction) {
        switch action {
        case .undo:
            guard let pipeline else { return }
            Task { await pipeline.undo() }
        case .retry:
            retryFailed()
        case .addKey, .openSpeechSettings:
            settingsController.show(selecting: .speech)
        case .addCredit:
            NSWorkspace.shared.open(routeSettings.route.account.creditsPage)
        case .copy:
            guard case .recovered(let id) = state else { return }
            copyRecovered(id)
        case .allowPasting:
            setup.allowPasting()
        case .openMicrophoneSettings:
            readiness.openSettings(.microphone)
        }
    }

    /// The text kotoba pasted or copied last, for "Fix Last Dictation…"; nil shows the window's empty state.
    private func lastDeliveredText() async -> String? {
        guard let store else { return nil }
        do {
            return try await store.lastDelivered()?.deliveredText
        } catch {
            Log.app.error("Cannot read the last dictation: \(error)")
            return nil
        }
    }

    private func copyRecovered(_ id: DictationID) {
        guard let pipeline else { return }
        Task {
            guard let record = await pipeline.retries.recovered().first(where: { $0.id == id }) else { return }
            await pipeline.retries.copy(record)
        }
    }
}

// MARK: - Menu

extension AppDelegate: StatusMenuActions {
    private func updateIcon() {
        statusItem?.icon =
            if case .recording = state {
                .listening
            } else if !readiness.isComplete || pendingCount > 0 {
                .needsAttention
            } else {
                .ready
            }
    }

    private func menuModel() -> MenuModel {
        readiness.refresh()
        let status: MenuModel.Status =
            if let launchIssue {
                .text(launchIssue)
            } else if state == .idle {
                readiness.firstMissing.map { .finishSetup($0.setupText) } ?? .text(StatusText.ready)
            } else {
                .text(state.statusText(statusContext) ?? "")
            }
        let route = routeSettings.route
        let input = audio.inputInUse
        return MenuModel(
            status: status,
            pendingCount: pendingCount,
            recovered: recovered,
            microphones: AudioDevices.inputs().map { MenuChoice(title: $0.name, value: $0.uid) },
            microphoneInUse: input.map { ($0.uid, $0.name) },
            routes: MenuModel.routes(current: route),
            route: MenuChoice(title: route.menuTitle, value: route.rawValue),
            grok: route.isGrok
                ? MenuModel.Grok(
                    isFormatOn: routeSettings.isGrokFormatOn, keepsFillerWords: routeSettings.keepsGrokFillerWords)
                : nil,
            hasLastDictation: hasLastDictation,
            suggestionCount: settingsController.dictionary?.suggestions.count ?? 0
        )
    }

    func finishSetup() {
        setup.finishSetup()
    }

    func retryFailed() {
        guard let pipeline else { return }
        Task {
            await pipeline.retryPending()
            await refreshQueues()
        }
    }

    func copyRecovered(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let uuid = UUID(uuidString: raw) else { return }
        copyRecovered(DictationID(rawValue: uuid))
    }

    /// Picking a mic moves it to the top of the order.
    func chooseMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        microphones.choose(uid: uid, name: sender.title)
        Task { await audio.inputMayHaveChanged() }
    }

    func selectRoute(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let route = TranscriptionRoute(rawValue: raw) else {
            return
        }
        routeSettings.route = route
    }

    func toggleGrokFormat() {
        routeSettings.isGrokFormatOn.toggle()
    }

    func toggleGrokFillerWords() {
        routeSettings.keepsGrokFillerWords.toggle()
    }

    func fixLastDictation() {
        fixWindow.show()
    }

    func openSuggestions() {
        settingsController.show(selecting: .dictionary)
    }

    func openSettings() {
        settingsController.show()
    }

    func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
