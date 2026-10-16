import AppKit
import KotobaCore
import KotobaProviders
import KotobaStorage
import Observation

/// What the onboarding window shows and does: the step, the key and the actions behind its buttons. Permissions and
/// setup come from the app's one `Readiness`; the other system calls go through `Source`, so snapshots use fixed
/// values. The step order and the footer's buttons come from `OnboardingFlow` (KotobaCore).
@MainActor
@Observable
final class OnboardingModel {
    /// Where the model changes the system: the live Mac, or no-ops for snapshots.
    struct Source {
        var route: @MainActor () -> TranscriptionRoute
        /// The first value of the launch-at-login toggle.
        var opensAtLogin: @MainActor () -> Bool
        var setLaunchAtLogin: @MainActor (Bool) -> LaunchAtLogin.Problem?
        var playsSounds: @MainActor () -> Bool
        var setPlaysSounds: @MainActor (Bool) -> Void
        var openURL: @MainActor (URL) -> Void
        var isWisprInstalled: @MainActor () async -> Bool
        /// The dictionary the Wispr Flow step imports into; nil until it is read at launch, or when it did not open.
        var dictionary: @MainActor () -> DictionaryModel?

        static func live(
            routeSettings: TranscriptionSettings, dictionary: @escaping @MainActor () -> DictionaryModel?
        ) -> Self {
            Self(
                route: { routeSettings.route },
                // Default on (docs/spec.md, phase 2.5) until setup is complete; then the real state. A development
                // build defaults to off, so it does not open at login beside the release app (`InstallYield`).
                opensAtLogin: { OnboardingController.isComplete ? LaunchAtLogin.isOn : Install.isRelease },
                setLaunchAtLogin: { LaunchAtLogin.change(to: $0) },
                playsSounds: { AppDefaults.areSoundCuesOn },
                setPlaysSounds: { AppDefaults.areSoundCuesOn = $0 },
                openURL: { NSWorkspace.shared.open($0) },
                isWisprInstalled: { await WisprFlowImport.isInstalled() },
                dictionary: dictionary
            )
        }
    }

    var step: OnboardingStep
    let readiness: Readiness
    /// Saves and checks the key, and holds the result line's status.
    let keyChecks: KeyChecks
    /// Text that arrived in the Try It field.
    var tryItText = ""
    var opensAtLogin: Bool
    var playsSounds: Bool {
        didSet { source.setPlaysSounds(playsSounds) }
    }
    /// What keeps the launch-at-login choice from taking effect, shown under its toggle.
    private(set) var loginProblem: LaunchAtLogin.Problem?
    /// The steps in order: Wispr Flow's joins once `checkWispr()` finds it and the dictionary is open.
    private(set) var flow = OnboardingFlow(isWisprInstalled: false, isDictionaryOpen: false)
    /// Wispr Flow is on this Mac: `checkWispr()` reads it when the window opens.
    private var isWisprInstalled = false
    /// What the Wispr Flow step imported; empty when Wispr Flow had nothing new. Nil until the owner answers.
    private(set) var wisprImported: DictionaryImport?
    /// Accessibility was asked for once; the next click opens System Settings instead of the prompt again.
    private var hasPromptedAccessibility = false

    @ObservationIgnored private let source: Source
    @ObservationIgnored let openSpeechSettings: @MainActor () -> Void

    init(
        step: OnboardingStep, readiness: Readiness, keyChecks: KeyChecks, source: Source,
        openSpeechSettings: @escaping @MainActor () -> Void
    ) {
        self.step = step
        self.readiness = readiness
        self.keyChecks = keyChecks
        self.source = source
        self.openSpeechSettings = openSpeechSettings
        opensAtLogin = source.opensAtLogin()
        playsSounds = source.playsSounds()
    }

    var route: TranscriptionRoute { source.route() }

    var account: ProviderAccount { route.account }

    var dictionary: DictionaryModel? { source.dictionary() }

    /// The step of the first missing thing, for the Done step's way back.
    var firstMissingStep: OnboardingStep? {
        switch readiness.firstMissing {
        case .microphone: .microphone
        case .accessibility: .accessibility
        case .setup: .key
        case nil: nil
        }
    }

    /// Whether the step's own requirement is met; the window marks it done.
    func isDone(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .tryIt, .done: false
        case .microphone: readiness.microphone == .allowed
        case .accessibility: readiness.isAccessibilityAllowed
        case .key: readiness.missingSetup == nil
        case .wisprImport: wisprImported != nil
        }
    }

    func refresh() {
        readiness.refresh()
    }

    /// Looks for Wispr Flow once, when the window opens.
    func checkWispr() async {
        isWisprInstalled = await source.isWisprInstalled()
        refreshFlow()
    }

    /// The dictionary was read at launch, after the window opened (first launch opens onboarding first).
    func dictionaryOpened() {
        refreshFlow()
    }

    /// A window that resumed on the Wispr Flow step moves to the next step when the flow has none.
    private func refreshFlow() {
        let flow = OnboardingFlow(isWisprInstalled: isWisprInstalled, isDictionaryOpen: dictionary != nil)
        guard flow != self.flow else { return }
        self.flow = flow
        step = flow.resuming(step)
    }

    func goBack() {
        if let previous = flow.previous(before: step) { step = previous }
    }

    func goForward() {
        if let next = flow.next(after: step) { step = next }
    }

    func allowMicrophone() async {
        await readiness.requestMicrophone()
    }

    func allowAccessibility() {
        if hasPromptedAccessibility {
            readiness.openSettings(.accessibility)
        } else {
            hasPromptedAccessibility = true
            readiness.requestAccessibility()
        }
    }

    func openMicrophoneSettings() {
        readiness.openSettings(.microphone)
    }

    /// The Wispr Flow step's button: reads Wispr Flow's dictionary and shows what it would add, as Settings does.
    func previewWisprImport() {
        dictionary?.previewWisprImport()
    }

    func wisprImportAnswered(_ added: DictionaryImport) {
        wisprImported = added
    }

    func open(_ url: URL) {
        source.openURL(url)
    }

    func setOpensAtLogin(_ isOn: Bool) {
        opensAtLogin = isOn
        loginProblem = source.setLaunchAtLogin(isOn)
    }

    func openLoginItemsSettings() {
        LaunchAtLogin.openLoginItemsSettings()
    }

    /// The Done button. The launch-at-login choice is applied when the Done step shows, so its problem text is
    /// read before the window closes.
    func finish() {
        OnboardingController.isComplete = true
    }
}

// MARK: - Snapshots

extension OnboardingModel.Source {
    /// No Keychain, network or setting behind it. `dictionary` stands for the one Wispr Flow imports into.
    static func sample(dictionary: DictionaryModel? = nil) -> Self {
        Self(
            route: { .openRouterMAI },
            opensAtLogin: { true },
            setLaunchAtLogin: { _ in nil },
            playsSounds: { true },
            setPlaysSounds: { _ in },
            openURL: { _ in },
            isWisprInstalled: { dictionary != nil },
            dictionary: { dictionary }
        )
    }
}

extension OnboardingModel {
    /// Wispr Flow shows as installed without a look on disk (`checkWispr()` runs in a task, which a snapshot skips).
    func showsWisprInstalled() {
        isWisprInstalled = true
        refreshFlow()
    }
}
