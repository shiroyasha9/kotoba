import AppKit
import KotobaProviders
import Observation

/// The six first-run steps, in order (docs/research/ux-polish.md, section 3).
enum OnboardingStep: String, CaseIterable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case key
    case tryIt
    case done

    var id: Self { self }

    /// The position in `allCases`, from 0.
    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var next: Self? {
        Self.allCases.indices.contains(index + 1) ? Self.allCases[index + 1] : nil
    }

    var previous: Self? {
        index > 0 ? Self.allCases[index - 1] : nil
    }
}

/// What the onboarding window shows and does: the step, the key and the actions behind its buttons. Permissions and
/// setup come from the app's one `Readiness`; the other system calls go through `Source`, so snapshots use fixed
/// values.
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

        static func live(routeSettings: TranscriptionSettings) -> Self {
            Self(
                route: { routeSettings.route },
                // Default on (docs/spec.md, phase 2.5) until setup is complete; then the real state.
                opensAtLogin: { OnboardingController.isComplete ? LaunchAtLogin.isOn : true },
                setLaunchAtLogin: { LaunchAtLogin.change(to: $0) },
                playsSounds: { AppDefaults.areSoundCuesOn },
                setPlaysSounds: { AppDefaults.areSoundCuesOn = $0 },
                openURL: { NSWorkspace.shared.open($0) }
            )
        }
    }

    var step: OnboardingStep {
        didSet { isShownStepDoneOnEntry = isDone(step) }
    }
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
    /// The shown step was already done when it appeared (the owner went Back), so a grant does not move on.
    private var isShownStepDoneOnEntry: Bool
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
        isShownStepDoneOnEntry = false
        isShownStepDoneOnEntry = isDone(step)
    }

    var route: TranscriptionRoute { source.route() }

    var account: ProviderAccount { route.account }

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
        }
    }

    /// A permission step that showed undone and is now granted: the window moves on by itself.
    var isGrantNew: Bool {
        (step == .microphone || step == .accessibility) && !isShownStepDoneOnEntry && isDone(step)
    }

    func refresh() {
        readiness.refresh()
    }

    func goBack() {
        if let previous = step.previous { step = previous }
    }

    func goForward() {
        if let next = step.next { step = next }
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

    func saveKey(_ draft: String) async {
        await keyChecks.save(draft, for: account)
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
    /// No Keychain, network or setting behind it.
    static var sample: Self {
        Self(
            route: { .openRouterMAI },
            opensAtLogin: { true },
            setLaunchAtLogin: { _ in nil },
            playsSounds: { true },
            setPlaysSounds: { _ in },
            openURL: { _ in }
        )
    }
}
