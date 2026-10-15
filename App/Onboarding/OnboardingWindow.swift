import AppKit
import KotobaProviders
import SwiftUI

/// The first-run window: six steps, one at a time. Built when it opens and released when it closes, like Settings,
/// so it costs nothing at idle. The app opens it on first launch and from "Finish Setting Up kotoba…".
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 560, height: 460)

    private enum Key {
        static let isComplete = "onboarding.completed"
        static let step = "onboarding.step"
    }

    /// The owner clicked Done once. Setup can still be incomplete (a permission turned off later); the app checks
    /// that separately.
    static var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: Key.isComplete) }
        set { UserDefaults.standard.set(newValue, forKey: Key.isComplete) }
    }

    private let readiness: Readiness
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let router: TranscriptionRouter
    private let openSpeechSettings: @MainActor () -> Void
    private var window: NSWindow?
    private var model: OnboardingModel?

    /// `router` checks a saved key with one free request; `openSpeechSettings` opens Settings on the Speech pane.
    init(
        readiness: Readiness, routeSettings: TranscriptionSettings, vault: KeyVault, router: TranscriptionRouter,
        openSpeechSettings: @escaping @MainActor () -> Void
    ) {
        self.readiness = readiness
        self.routeSettings = routeSettings
        self.vault = vault
        self.router = router
        self.openSpeechSettings = openSpeechSettings
    }

    /// Shows the window on `step`; nil resumes where the owner closed it, or starts at Welcome.
    func show(step: OnboardingStep? = nil) {
        let resumed = UserDefaults.standard.string(forKey: Key.step).flatMap(OnboardingStep.init)
        let model =
            model
            ?? OnboardingModel(
                step: step ?? resumed ?? .welcome, readiness: readiness,
                keyChecks: KeyChecks(vault: vault, checkKey: router.checkKey(_:for:)),
                source: .live(routeSettings: routeSettings),
                openSpeechSettings: openSpeechSettings)
        if let step {
            model.step = step
        }
        model.refresh()
        let window = window ?? makeWindow(model: model)
        self.model = model
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
        let view = OnboardingView(model: model) { [weak self] in self?.window?.close() }
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
    /// Every step as the whole window, plus the states a step changes into (mic off, key checked, all done).
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
            window("onboarding-microphone-denied") { model(.microphone, .sample(microphone: .denied)) },
            window("onboarding-microphone-allowed") { model(.microphone, ready) },
            window("onboarding-accessibility-allowed") { model(.accessibility, ready) },
            window("onboarding-key-works") { model(.key, ready, keys: [.openRouter: .checked(.valid)]) },
            window("onboarding-key-no-credit") { model(.key, ready, keys: [.openRouter: .checked(.noCredit)]) },
            window("onboarding-tryIt-works") {
                let model = model(.tryIt, ready)
                model.tryItText = "Hello from kotoba."
                return model
            },
            window("onboarding-done-ready") { model(.done, ready) },
        ]
    }

    private static func model(
        _ step: OnboardingStep, _ readiness: Readiness, keys: [ProviderAccount: KeyStatus] = [:]
    ) -> OnboardingModel {
        OnboardingModel(
            step: step, readiness: readiness, keyChecks: .sample(keys), source: .sample, openSpeechSettings: {})
    }

    private static func window(_ name: String, _ model: @escaping @MainActor () -> OnboardingModel) -> Snapshot {
        Snapshots.fixedWindow(named: name, size: size) { OnboardingView(model: model()) {} }
    }
}
