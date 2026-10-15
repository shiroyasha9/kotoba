import AVFAudio
import AppKit
import ApplicationServices
import Carbon
import KotobaCore
import KotobaProviders
import KotobaStorage
import os

/// Wires the ports to the pipeline and owns the menu bar item. Windows are built on demand.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hotkeys = HotkeyTap(cleanupChord: CleanupChord.current.modifiers)
    private let microphones = MicrophonePreferences()
    private lazy var audio = AudioCapture(preferences: microphones)
    /// Read by the provider on every request, so a menu change applies to the next dictation.
    private let routeSettings = TranscriptionSettings()
    private let vault = KeyVault()
    private let settings = DictationPipeline.Settings(
        audioDirectory: HistoryStore.directory.appending(path: "audio", directoryHint: .isDirectory)
    )
    private lazy var indicator = IndicatorPanel(longRecordingWarning: settings.longRecordingWarning)
    private var statusItem: NSStatusItem?
    private var pipeline: DictationPipeline?
    private var store: HistoryStore?
    private var state: DictationState = .idle
    private var pendingCount = 0
    /// Retried transcripts from the last 24 h, newest first, for the Recovered submenu.
    private var recovered: [DictationRecord] = []
    private var isSecureInputOn = false
    private var hotkeyIssue: String?
    private lazy var settingsController = SettingsController(
        routeSettings: routeSettings, vault: vault, microphones: microphones, audio: audio)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.registerDefaults()
        CGEventPaster.trackKeyboardLayout()
        CGEventPaster.warmUp()
        NSApp.mainMenu = .editOnlyMain()
        setUpStatusItem()
        let store: HistoryStore
        do {
            store = try HistoryStore()
        } catch {
            Log.app.fault("Cannot open the history database: \(error)")
            hotkeyIssue = "History database unavailable"
            return
        }
        self.store = store
        let pipeline = DictationPipeline(
            ports: .init(
                audio: audio,
                provider: TranscriptionRouter(settings: routeSettings, keys: vault.source(for:)),
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
        Task {
            await settingsController.loadDictionary(into: pipeline)
            await prepareMicrophone()
            await pipeline.retryPending()
            await refreshQueues()
        }
        startHotkeys(feeding: pipeline)
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
        indicator.onUndo = {
            Task { await pipeline.undo() }
        }
        Task {
            for await state in pipeline.states {
                render(state)
            }
        }
        Task { [audio, indicator] in
            for await level in audio.levels {
                indicator.showLevel(level)
            }
        }
        // A saved key, endpoint or route can complete the setup; the dictations that waited for it are sent then.
        Task { [vault] in
            for await _ in vault.saves {
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

    private func setupChanged(_ pipeline: DictationPipeline) async {
        await pipeline.setupChanged()
        await refreshQueues()
    }

    private func render(_ newState: DictationState) {
        let wasRecording = if case .recording = state { true } else { false }
        // The queue counts change only when a dictation ends.
        let changesQueues =
            switch newState {
            case .failed, .needsSetup, .rejected, .recovered, .copied, .cleanupFailed: true
            case .idle: state == .transcribing
            case .recording, .transcribing, .undoable, .captureFailed: false
            }
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
        indicator.show(newState, secureInput: isSecureInputOn, provider: routeSettings.route.account)
        if changesQueues {
            Task { await refreshQueues() }
        }
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
            if await hotkeys.start() {
                CGEventPaster.isTrusted = true
                return
            }
            // The event tap and Cmd-V both need Accessibility. Ask once, then check until it is granted.
            hotkeyIssue = "Waiting for Accessibility permission"
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            while await !hotkeys.start() {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
            CGEventPaster.isTrusted = true
            hotkeyIssue = nil
            Log.app.info("Hotkey tap started")
        }
    }

    private func prepareMicrophone() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else { return }
        default:
            Log.app.error("Microphone access denied")
            return
        }
        await audio.prepare()
    }

    private func refreshQueues() async {
        guard let store, let pipeline else { return }
        recovered = await pipeline.retries.recovered()
        do {
            pendingCount = try await store.pendingCount()
        } catch {
            Log.app.error("Cannot count queued dictations: \(error)")
        }
    }
}

// MARK: - Menu

extension AppDelegate {
    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "kotoba")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let provider = routeSettings.route.account.title
        let status = NSMenuItem(
            title: hotkeyIssue ?? state.menuText(provider: provider), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        let retry = NSMenuItem.action(
            "Retry Failed Dictations (\(pendingCount))", target: self, action: #selector(retryFailed))
        retry.isEnabled = pendingCount > 0
        menu.addItem(retry)
        addRecoveredItems(to: menu)
        menu.addItem(.separator())
        addMicrophoneItems(to: menu)
        addModelItems(to: menu)
        menu.addItem(
            .choices(
                "Cleanup Chord: \(CleanupChord.current.title)",
                CleanupChord.allCases.map { MenuChoice(title: $0.title, value: $0.rawValue) },
                selected: CleanupChord.current.rawValue, target: self, action: #selector(chooseCleanupChord(_:))))
        menu.addItem(.separator())
        menu.addItem(.action("Set API Key…", target: self, action: #selector(openProvidersSettings)))
        menu.addItem(.action("Settings…", target: self, action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(
            .toggle("Sound Cues", isOn: AppDefaults.areSoundCuesOn, target: self, action: #selector(toggleSoundCues)))
        menu.addItem(
            .choices(
                "Indicator Position", IndicatorAnchor.allCases.map { MenuChoice(title: $0.title, value: $0.rawValue) },
                selected: indicator.anchor.rawValue, target: self, action: #selector(selectIndicatorAnchor(_:))))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit kotoba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// The connected mics, the one kotoba records from checked. Picking one moves it to the top of the order.
    private func addMicrophoneItems(to menu: NSMenu) {
        let current = audio.inputInUse
        let inputs = AudioDevices.inputs().map { MenuChoice(title: $0.name, value: $0.uid) }
        menu.addItem(
            .choices(
                "Microphone: \(current?.name ?? "None")", inputs, selected: current?.uid, target: self,
                action: #selector(chooseMicrophone(_:))))
    }

    @objc private func chooseMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        microphones.choose(uid: uid, name: sender.title)
        Task { await audio.inputMayHaveChanged() }
    }

    private func addModelItems(to menu: NSMenu) {
        let current = routeSettings.route
        let routes = TranscriptionRoute.allCases.map {
            MenuChoice(title: $0.title, value: $0.rawValue, subtitle: $0.note)
        }
        menu.addItem(
            .choices(
                "Model: \(current.title)", subtitle: current.note, routes, selected: current.rawValue, target: self,
                action: #selector(selectRoute(_:))))
        guard current.isGrok else { return }
        menu.addItem(
            .toggle(
                "Format Numbers (format)", isOn: routeSettings.isGrokFormatOn, target: self,
                action: #selector(toggleGrokFormat), indentationLevel: 1))
        menu.addItem(
            .toggle(
                "Keep Filler Words", isOn: routeSettings.keepsGrokFillerWords, target: self,
                action: #selector(toggleGrokFillerWords), indentationLevel: 1))
    }

    private func addRecoveredItems(to menu: NSMenu) {
        guard !recovered.isEmpty else { return }
        let items = recovered.map { record in
            let text = record.cleanedText ?? record.transcript ?? ""
            let title = text.count > 40 ? String(text.prefix(40)) + "…" : text
            return MenuChoice(title: title, value: record.id.rawValue.uuidString)
        }
        menu.addItem(
            .choices(
                "Recovered (\(recovered.count))", items, selected: nil, target: self,
                action: #selector(copyRecovered(_:))))
    }

    @objc private func copyRecovered(_ sender: NSMenuItem) {
        guard let pipeline, let id = sender.representedObject as? String,
            let record = recovered.first(where: { $0.id.rawValue.uuidString == id })
        else { return }
        Task {
            await pipeline.retries.copy(record)
            await refreshQueues()
        }
    }

    @objc private func selectRoute(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let route = TranscriptionRoute(rawValue: raw) else {
            return
        }
        routeSettings.route = route
    }

    @objc private func toggleGrokFormat() {
        routeSettings.isGrokFormatOn.toggle()
    }

    @objc private func toggleGrokFillerWords() {
        routeSettings.keepsGrokFillerWords.toggle()
    }

    @objc private func retryFailed() {
        guard let pipeline else { return }
        Task {
            await pipeline.retryPending()
            await refreshQueues()
        }
    }

    @objc private func toggleSoundCues() {
        AppDefaults.areSoundCuesOn.toggle()
    }

    @objc private func selectIndicatorAnchor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let anchor = IndicatorAnchor(rawValue: raw) else { return }
        indicator.anchor = anchor
    }

    @objc private func chooseCleanupChord(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let chord = CleanupChord(rawValue: raw) else { return }
        CleanupChord.current = chord
        hotkeys.setCleanupChord(chord.modifiers)
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    /// The Providers pane holds one key field per provider.
    @objc private func openProvidersSettings() {
        settingsController.show(selecting: .providers)
    }
}
