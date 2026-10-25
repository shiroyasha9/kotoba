import AppKit
import KotobaCore
import KotobaProviders
import SwiftUI

/// The first-run window: its steps one at a time. Built when it opens and released when it closes, like Settings,
/// so it costs nothing at idle. The app opens it on first launch and from "Finish Setting Up kotoba…".
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let size = PageMetrics.onboardingWindowSize

    private enum Key {
        static let isComplete = "onboarding.completed"
        static let step = "onboarding.step"
        static let hasTakenWisprShortcuts = "onboarding.wisprShortcutsTaken"
    }

    /// The owner clicked Done once. Setup can still be incomplete (a permission turned off later); the app checks
    /// that separately.
    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: Key.isComplete) }
        set { UserDefaults.standard.set(newValue, forKey: Key.isComplete) }
    }

    /// Welcome took Wispr Flow's shortcuts once (`OnboardingFlow.takesWisprShortcuts`).
    static var hasTakenWisprShortcuts: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasTakenWisprShortcuts) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasTakenWisprShortcuts) }
    }

    private let readiness: Readiness
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let router: TranscriptionRouter
    private let dictionary: @MainActor () -> DictionaryModel?
    private let links: SetupLinks
    private var window: NSWindow?
    private var model: OnboardingModel?

    /// `router` checks a saved key with one free request; `dictionary` is the one the Wispr Flow step imports into;
    /// `links` open the main window: the Speech page's "Advanced…" sheet from the key and Done steps, Home after Done.
    init(
        readiness: Readiness, routeSettings: TranscriptionSettings, vault: KeyVault, router: TranscriptionRouter,
        dictionary: @escaping @MainActor () -> DictionaryModel?, links: SetupLinks
    ) {
        self.readiness = readiness
        self.routeSettings = routeSettings
        self.vault = vault
        self.router = router
        self.dictionary = dictionary
        self.links = links
    }

    /// Shows the window on `step`; nil resumes where the owner closed it, or starts at Welcome.
    func show(step: OnboardingStep? = nil) {
        WindowFront.activate()
        let model =
            model
            ?? OnboardingModel(
                step: step ?? OnboardingStep(saved: UserDefaults.standard.string(forKey: Key.step)),
                readiness: readiness,
                keyChecks: KeyChecks(vault: vault, checkKey: router.checkKey(_:for:)),
                source: .live(routeSettings: routeSettings, dictionary: dictionary),
                openOtherSpeechServices: links.otherSpeechServices)
        if let step {
            model.step = step
        }
        model.refresh()
        let window = window ?? makeWindow(model: model)
        self.model = model
        self.window = window
        WindowFront.show(window)
    }

    /// The dictionary was read at launch: an open window can offer the Wispr Flow step now.
    func dictionaryOpened() {
        model?.dictionaryOpened()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model?.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        if let model {
            if model.step == .done, Self.isComplete {
                UserDefaults.standard.removeObject(forKey: Key.step)
            } else {
                UserDefaults.standard.set(model.step.rawValue, forKey: Key.step)
            }
        }
        window = nil
        model = nil
    }

    private func makeWindow(model: OnboardingModel) -> NSWindow {
        // Done closes the window and opens the app on Home, where the owner starts (owner QA, 2026-10-25).
        let view = OnboardingView(model: model) { [weak self] in
            self?.window?.close()
            self?.links.home()
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Welcome to kotoba"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.size)
        window.delegate = self
        window.center()
        return window
    }
}

// MARK: - Snapshots

extension OnboardingController {
    /// Every step as the whole window, plus the states a step changes into (microphone off, one grant, both grants,
    /// key saved, Wispr Flow imported, all done). Wispr Flow shows as installed, so Done has its row.
    static func snapshots() -> [Snapshot] {
        let ready = Readiness.sample()
        let first = OnboardingStep.allCases.map { step in
            window("onboarding-\(step.rawValue)") {
                model(
                    step,
                    .sample(microphone: .notAsked, isAccessibilityAllowed: false, missingSetup: (.key, .openRouter)))
            }
        }
        return first + [
            window("onboarding-permissions-denied") {
                model(.permissions, .sample(microphone: .denied, isAccessibilityAllowed: false))
            },
            window("onboarding-permissions-microphone-allowed") {
                model(.permissions, .sample(microphone: .allowed, isAccessibilityAllowed: false))
            },
            window("onboarding-permissions-allowed") { model(.permissions, ready) },
            window("onboarding-key-works") { model(.key, ready, keys: [.openRouter: .checked(.valid)], hasKey: true) },
            window("onboarding-key-no-credit") {
                model(.key, ready, keys: [.openRouter: .checked(.noCredit)], hasKey: true)
            },
            window("onboarding-key-saved-earlier") { model(.key, ready, hasKey: true) },
            window("onboarding-tryIt-works") {
                let model = model(.tryIt, ready)
                model.tryItText = "Hello from kotoba."
                return model
            },
            window("onboarding-done-ready") { model(.done, ready) },
            // The owner turned the login switch on and macOS refused: the switch goes back off, the footnote under it.
            window("onboarding-done-login-problem") {
                let model = model(.done, ready, opensAtLogin: false, loginProblem: .failed)
                model.setOpensAtLogin(true)
                return model
            },
            window("onboarding-done-imported") {
                let model = model(.done, ready)
                let (incoming, _) = Pane.sampleWisprImport
                model.wisprImportAnswered(PersonalDictionary().importPreview(of: incoming))
                return model
            },
        ] + welcomeSnapshots(ready)
    }

    /// Welcome as it takes Wispr Flow's shortcuts: one mode (the other is one kotoba cannot take), both, one equal to
    /// kotoba's default, none; while Wispr Flow runs; after the owner changed a taken chord; with no Wispr Flow; and
    /// Change…'s sheet.
    private static func welcomeSnapshots(_ ready: Readiness) -> [Snapshot] {
        let both = ["62+61": "popo", "49+58": "ptt"]
        return [
            window("onboarding-welcome-wispr-running") { model(.welcome, ready, wisprRuns: true) },
            window("onboarding-welcome-no-wispr-shortcuts") { model(.welcome, ready, wisprKeys: nil) },
            window("onboarding-welcome-wispr-both") { model(.welcome, ready, wisprKeys: both) },
            // The tallest Welcome: the Wispr Flow row, a line under each shortcut row and the footnote.
            window("onboarding-welcome-wispr-both-running") {
                model(.welcome, ready, wisprKeys: both, wisprRuns: true)
            },
            window("onboarding-welcome-wispr-default") { model(.welcome, ready, wisprKeys: ["55+58+59": "popo"]) },
            window("onboarding-welcome-wispr-changed") {
                let model = model(.welcome, ready, wisprKeys: both, wisprRuns: true)
                _ = model.chords.save(Chord(modifiers: .function), as: .handsFree)
                return model
            },
            window("onboarding-welcome-no-wispr") { model(.welcome, ready, isWisprInstalled: false) },
            MainWindow.sheetSnapshot(named: "onboarding-change-shortcut") {
                ShortcutSheet(chords: HotkeyChords(defaults: nil), role: .handsFree)
            },
        ]
    }

    /// `hasKey`: an OpenRouter key is saved; `wisprRuns`: Wispr Flow is open. Wispr Flow shows as installed, with
    /// made-up shortcuts.
    private static func model(
        _ step: OnboardingStep, _ readiness: Readiness, keys: [ProviderAccount: KeyStatus] = [:], hasKey: Bool = false,
        opensAtLogin: Bool = true, loginProblem: LaunchAtLogin.Problem? = nil,
        wisprKeys: [String: String]? = OnboardingModel.Source.sampleWisprKeys,
        wisprRuns: Bool = false, isWisprInstalled: Bool = true
    ) -> OnboardingModel {
        let model = OnboardingModel(
            step: step, readiness: readiness, keyChecks: .sample(keys, savedKeys: hasKey ? [.openRouter] : []),
            source: .sample(
                dictionary: isWisprInstalled ? Pane.sampleModel(PersonalDictionary()) : nil,
                opensAtLogin: opensAtLogin, loginProblem: loginProblem, wisprKeys: wisprKeys,
                wisprRuns: wisprRuns),
            openOtherSpeechServices: {})
        if isWisprInstalled {
            model.showsWisprInstalled(keys: wisprKeys)
        }
        return model
    }

    private static func window(_ name: String, _ model: @escaping @MainActor () -> OnboardingModel) -> Snapshot {
        Snapshots.fixedWindow(named: name, size: size) { OnboardingView(model: model()) {} }
    }
}
