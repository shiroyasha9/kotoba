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
        /// What the system holds after a change: on, or waiting for approval.
        var isLaunchAtLoginOn: @MainActor () -> Bool
        var playsSounds: @MainActor () -> Bool
        var setPlaysSounds: @MainActor (Bool) -> Void
        var openURL: @MainActor (URL) -> Void
        var isWisprInstalled: @MainActor () async -> Bool
        /// Wispr Flow's `prefs.user.shortcuts`; nil when it has none or its file cannot be read.
        var wisprShortcutKeys: @MainActor () async -> [String: String]?
        var isWisprRunning: @MainActor () -> Bool
        /// The chords Welcome shows and changes.
        var chords: HotkeyChords
        /// The dictionary that the Done step's Wispr Flow row imports into; nil until it is read at launch, or when it
        /// did not open.
        var dictionary: @MainActor () -> DictionaryModel?

        @MainActor static func live(
            routeSettings: TranscriptionSettings, dictionary: @escaping @MainActor () -> DictionaryModel?
        ) -> Self {
            Self(
                route: { routeSettings.route },
                // Default on (docs/spec.md, phase 2.5) until setup is complete; then the real state. A development
                // build defaults to off, so it does not open at login beside the release app (`InstallYield`).
                opensAtLogin: { OnboardingController.isComplete ? LaunchAtLogin.isOn : Install.isRelease },
                setLaunchAtLogin: { LaunchAtLogin.change(to: $0) },
                isLaunchAtLoginOn: { LaunchAtLogin.isOn || LaunchAtLogin.needsApproval },
                playsSounds: { AppDefaults.areSoundCuesOn },
                setPlaysSounds: { AppDefaults.areSoundCuesOn = $0 },
                openURL: { NSWorkspace.shared.open($0) },
                isWisprInstalled: { await WisprFlowImport.isInstalled() },
                wisprShortcutKeys: { await WisprShortcutsRow.readKeys() },
                isWisprRunning: { WisprShortcutsRow.isWisprRunning },
                chords: .shared,
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
    /// The "Open at login" switch: what it shows, and what Done applies (`LoginItemChoice`).
    private(set) var loginChoice: LoginItemChoice
    var playsSounds: Bool {
        didSet { source.setPlaysSounds(playsSounds) }
    }
    /// What keeps the owner's launch-at-login change from taking effect, shown under its toggle; only after the owner
    /// turns the switch, never for the default.
    private(set) var loginProblem: LaunchAtLogin.Problem?
    /// The Done step offers the Wispr Flow import (`OnboardingFlow.offersWisprImport`).
    private(set) var offersWisprImport = false
    /// Wispr Flow is on this Mac: `checkWispr()` reads it when the window opens.
    private var isWisprInstalled = false
    /// Wispr Flow's shortcuts as it keeps them, read with the install check; kotoba's chords are measured against them
    /// each time Welcome draws, so a chord changed with Change… counts.
    private var wisprShortcutKeys: [String: String]?
    /// Wispr Flow ran when the owner took its shortcuts: both apps would start on the same keys.
    private(set) var wisprRunsWithSameKeys = false
    /// What the Wispr Flow row imported; empty when Wispr Flow had nothing new. Nil until the owner answers.
    private(set) var wisprImported: DictionaryImport?
    /// Accessibility was asked for once; the next click opens System Settings instead of the prompt again.
    private var hasPromptedAccessibility = false

    @ObservationIgnored private let source: Source
    /// The Speech page with its "Advanced…" sheet open, where the xAI and Azure routes and the Azure endpoint are: the
    /// key step's "Use xAI or Azure Instead…" and Done's "Add Your Azure Endpoint…".
    @ObservationIgnored let openOtherSpeechServices: @MainActor () -> Void

    init(
        step: OnboardingStep, readiness: Readiness, keyChecks: KeyChecks, source: Source,
        openOtherSpeechServices: @escaping @MainActor () -> Void
    ) {
        self.step = step
        self.readiness = readiness
        self.keyChecks = keyChecks
        self.source = source
        self.openOtherSpeechServices = openOtherSpeechServices
        loginChoice = LoginItemChoice(isOn: source.opensAtLogin())
        playsSounds = source.playsSounds()
    }

    var chords: HotkeyChords { source.chords }

    var opensAtLogin: Bool { loginChoice.isOn }

    var route: TranscriptionRoute { source.route() }

    var account: ProviderAccount { route.account }

    var dictionary: DictionaryModel? { source.dictionary() }

    /// The step of the first missing thing, for the Done step's way back.
    var firstMissingStep: OnboardingStep? {
        switch readiness.firstMissing {
        case .microphone, .accessibility: .permissions
        case .setup: .key
        case nil: nil
        }
    }

    /// Whether the step's own requirement is met; the window marks it done.
    func isDone(_ step: OnboardingStep) -> Bool {
        switch step {
        case .welcome, .done: false
        case .tryIt: !tryItText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .permissions: readiness.microphone == .allowed && readiness.isAccessibilityAllowed
        case .key: readiness.missingSetup == nil
        }
    }

    func refresh() {
        readiness.refresh()
    }

    /// Looks for Wispr Flow once, when the window opens, and reads its shortcuts when it is there.
    func checkWispr() async {
        isWisprInstalled = await source.isWisprInstalled()
        dictionaryOpened()
        if isWisprInstalled {
            wisprShortcutKeys = await source.wisprShortcutKeys()
        }
    }

    /// Wispr Flow's two ways to dictate as kotoba can take them now; nil when Wispr Flow is not here or has neither.
    var wisprShortcuts: WisprShortcuts? {
        guard let keys = wisprShortcutKeys else { return nil }
        let found = WisprShortcuts(
            shortcuts: keys, handsFree: chords.handsFree, pushToTalk: chords.savedPushToTalk, cleanup: chords.cleanup,
            pasteLast: chords.pasteLast, polishLast: chords.polishLast)
        return found.handsFree == nil && found.pushToTalk == nil ? nil : found
    }

    /// kotoba's chords are Wispr Flow's usable ones already.
    var usesWisprShortcuts: Bool {
        guard let found = wisprShortcuts, !found.chords.isEmpty else { return false }
        return found.chords.allSatisfy { role, chord in chords.chord(role) == chord }
    }

    /// "Use Your Wispr Flow Shortcuts": saves each chord kotoba can take; the other mode keeps kotoba's own.
    func useWisprShortcuts() {
        for (role, chord) in wisprShortcuts?.chords ?? [] {
            if let problem = chords.save(chord, as: role) {
                Log.app.error(
                    "Cannot use the Wispr Flow chord for \(String(describing: role)): \(String(describing: problem))")
            }
        }
        wisprRunsWithSameKeys = source.isWisprRunning()
    }

    /// The dictionary was read at launch, after the window opened (first launch opens onboarding first).
    func dictionaryOpened() {
        offersWisprImport = OnboardingFlow.offersWisprImport(
            isWisprInstalled: isWisprInstalled, isDictionaryOpen: dictionary != nil)
    }

    func goBack() {
        if let previous = OnboardingFlow.previous(before: step) { step = previous }
    }

    func goForward() {
        if let next = OnboardingFlow.next(after: step) { step = next }
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

    /// The Done step's Wispr Flow button: reads Wispr Flow's dictionary and shows what it would add, as Settings does.
    func previewWisprImport() {
        dictionary?.previewWisprImport()
    }

    func wisprImportAnswered(_ added: DictionaryImport) {
        wisprImported = added
    }

    func open(_ url: URL) {
        source.openURL(url)
    }

    /// The owner turned the switch: the change applies at once, and the switch then shows what the system holds, so
    /// a change that failed puts it back, as System Settings does.
    func setOpensAtLogin(_ isOn: Bool) {
        loginProblem = source.setLaunchAtLogin(isOn)
        loginChoice.ownerTurned(systemIsOn: source.isLaunchAtLoginOn())
    }

    func openLoginItemsSettings() {
        LaunchAtLogin.openLoginItemsSettings()
    }

    /// The Done button. It applies the launch-at-login default the owner left as it was (on for a release build); a
    /// switch the owner turned took effect then, and is not applied again. A problem with the default shows on the
    /// General page.
    func finish() {
        if loginChoice.isAppliedAtDone {
            _ = source.setLaunchAtLogin(loginChoice.isOn)
        }
        OnboardingController.isComplete = true
    }
}

// MARK: - Snapshots

extension OnboardingModel.Source {
    /// No Keychain, network or setting behind it. `dictionary` stands for the one Wispr Flow imports into.
    /// `loginProblem` is what turning the login switch answers; `wisprKeys` are Wispr Flow's shortcuts; `wisprRuns`
    /// says Wispr Flow is open.
    @MainActor static func sample(
        dictionary: DictionaryModel? = nil, loginProblem: LaunchAtLogin.Problem? = nil,
        wisprKeys: [String: String]? = sampleWisprKeys, wisprRuns: Bool = false
    ) -> Self {
        // What the system holds: a change it refuses leaves it as it was.
        let loginItem = SampleLoginItem()
        return Self(
            route: { .openRouterMAI },
            opensAtLogin: { loginItem.isOn },
            setLaunchAtLogin: { isOn in
                if loginProblem != .failed { loginItem.isOn = isOn }
                return loginProblem
            },
            isLaunchAtLoginOn: { loginItem.isOn },
            playsSounds: { true },
            setPlaysSounds: { _ in },
            openURL: { _ in },
            isWisprInstalled: { dictionary != nil },
            wisprShortcutKeys: { wisprKeys },
            isWisprRunning: { wisprRuns },
            chords: HotkeyChords(defaults: nil),
            dictionary: { dictionary }
        )
    }

    @MainActor private final class SampleLoginItem {
        var isOn = true
    }

    /// Made-up Wispr Flow shortcuts, not anyone's file: hands-free on right ⌥, push to talk on ⌥ and a double fn
    /// press, which kotoba cannot take.
    static let sampleWisprKeys = ["61": "popo", "179": "ptt", "55+59+9": "paste_last_text"]
}

extension OnboardingModel {
    /// Wispr Flow shows as installed, with `keys` as its shortcuts, without a look on disk (`checkWispr()` runs in a
    /// task, which a snapshot skips).
    func showsWisprInstalled(keys: [String: String]? = OnboardingModel.Source.sampleWisprKeys) {
        isWisprInstalled = true
        wisprShortcutKeys = keys
        dictionaryOpened()
    }
}
