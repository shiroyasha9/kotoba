import AVFAudio
import AppKit
import KotobaCore
import KotobaProviders
import Observation

/// What kotoba still needs before a dictation works end to end: the mic, Accessibility, the key or endpoint of the
/// current speech model, and credit on its account. One value for the menu status line, the menu bar icon, Home and
/// onboarding. `refresh()` reads everything again; each read is cheap (`KeyVault` caches `hasKey`, `AccountCredit` is
/// in memory), so call it freely.
@MainActor
@Observable
final class Readiness {
    enum Microphone: Sendable {
        case allowed
        /// macOS has not asked yet; onboarding asks.
        case notAsked
        case denied

        /// The grant now, from any thread: Readiness, the mic test and the pipeline's stop read it.
        static var current: Self {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: .allowed
            case .undetermined: .notAsked
            default: .denied
            }
        }
    }

    /// One missing thing, in the order onboarding asks for them.
    enum Missing: Sendable, Equatable {
        case microphone
        case accessibility
        case setup(SetupItem, ProviderAccount)
    }

    /// Where `Readiness` reads its facts: the system, or fixed values for snapshots.
    struct Reader {
        var microphone: @MainActor () -> Microphone
        var isAccessibilityAllowed: @MainActor () -> Bool
        var missingSetup: @MainActor () -> (item: SetupItem, account: ProviderAccount)?
        /// The current speech model's account, when its last request found no credit.
        var outOfCredit: @MainActor () -> ProviderAccount?

        static func live(settings: TranscriptionSettings, vault: KeyVault, credit: AccountCredit) -> Self {
            Self(
                microphone: { .current },
                isAccessibilityAllowed: { AXIsProcessTrusted() },
                missingSetup: {
                    settings.missingSetup(hasKey: vault.hasKey(for:)).map { ($0, settings.route.account) }
                },
                outOfCredit: {
                    let account = settings.route.account
                    return credit.isOut(account) ? account : nil
                }
            )
        }
    }

    private(set) var microphone: Microphone
    private(set) var isAccessibilityAllowed: Bool
    /// The key or endpoint the current speech model still needs, and whose.
    private(set) var missingSetup: (item: SetupItem, account: ProviderAccount)?
    /// The current speech model's account, when its last request found no credit. Apart from `missingSetup`: the
    /// shortcut still records and saves, and onboarding's key step is done with a key saved.
    private var outOfCredit: ProviderAccount?

    @ObservationIgnored private let reader: Reader

    /// The first thing to set up, or nil when kotoba is ready.
    var firstMissing: Missing? {
        if microphone != .allowed { return .microphone }
        if !isAccessibilityAllowed { return .accessibility }
        if let missingSetup { return .setup(missingSetup.item, missingSetup.account) }
        return outOfCredit.map { .setup(.credit, $0) }
    }

    var isComplete: Bool { firstMissing == nil }

    init(reader: Reader) {
        self.reader = reader
        microphone = reader.microphone()
        isAccessibilityAllowed = reader.isAccessibilityAllowed()
        missingSetup = reader.missingSetup()
        outOfCredit = reader.outOfCredit()
    }

    convenience init(settings: TranscriptionSettings, vault: KeyVault, credit: AccountCredit) {
        self.init(reader: .live(settings: settings, vault: vault, credit: credit))
    }

    /// Fixed values, for snapshots: reads no permission, Keychain or setting.
    static func sample(
        microphone: Microphone = .allowed, isAccessibilityAllowed: Bool = true,
        missingSetup: (item: SetupItem, account: ProviderAccount)? = nil, outOfCredit: ProviderAccount? = nil
    ) -> Readiness {
        Readiness(
            reader: Reader(
                microphone: { microphone }, isAccessibilityAllowed: { isAccessibilityAllowed },
                missingSetup: { missingSetup }, outOfCredit: { outOfCredit }))
    }

    /// Reads every check again. Only a changed value is set, so observers wake only on a change.
    func refresh() {
        let microphone = reader.microphone()
        if microphone != self.microphone { self.microphone = microphone }
        let isAccessibilityAllowed = reader.isAccessibilityAllowed()
        if isAccessibilityAllowed != self.isAccessibilityAllowed {
            self.isAccessibilityAllowed = isAccessibilityAllowed
        }
        let missingSetup = reader.missingSetup()
        if missingSetup?.item != self.missingSetup?.item || missingSetup?.account != self.missingSetup?.account {
            self.missingSetup = missingSetup
        }
        let outOfCredit = reader.outOfCredit()
        if outOfCredit != self.outOfCredit { self.outOfCredit = outOfCredit }
    }

    /// Shows the system Microphone prompt when macOS has not asked yet, then refreshes.
    func requestMicrophone() async {
        if microphone == .notAsked {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        refresh()
    }

    /// Shows the system Accessibility prompt, which offers to open System Settings. The grant arrives later;
    /// the caller refreshes while it waits.
    func requestAccessibility() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// A page of System Settings > Privacy & Security, where a denied permission is turned on.
    enum PrivacyPane: String {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"

        var url: URL? { URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)") }
    }

    func openSettings(_ pane: PrivacyPane) {
        guard let url = pane.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The main window's places that setup opens, each a closure, so the setup flow and onboarding never hold the window.
struct SetupLinks {
    /// The Speech page with its "Advanced…" sheet: the xAI and Azure routes and the Azure endpoint.
    var otherSpeechServices: @MainActor () -> Void
    /// Home: where onboarding's Done leads.
    var home: @MainActor () -> Void
}

/// The setup flow around `Readiness`: onboarding at first launch and from "Finish Setting Up kotoba…", and the
/// hotkey tap, which starts once Accessibility is allowed. No permission prompt appears before its onboarding
/// step (ux-polish O2).
@MainActor
final class SetupFlow {
    let readiness: Readiness
    private let links: SetupLinks
    private lazy var onboarding = OnboardingController(
        readiness: readiness, routeSettings: routeSettings, vault: vault, router: router, dictionary: dictionary,
        links: links)
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let router: TranscriptionRouter
    /// The dictionary onboarding's Wispr Flow step imports into; nil until it is read at launch.
    private let dictionary: @MainActor () -> DictionaryModel?
    private var activations: Task<Void, Never>?
    private var creditChanges: Task<Void, Never>?
    private var accessibilityChanges: Task<Void, Never>?
    /// Makes the hotkey tap again after Accessibility comes back (`startHotkeys`).
    private var regrants: Task<Void, Never>?
    /// Reads Readiness again when the system disables the tap for user input (`HotkeyTap.disabledByUserInput`).
    private var tapDisables: Task<Void, Never>?

    /// `router` checks a key in onboarding; `links` open the main window where a fix or onboarding's Done leads.
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

    /// Onboarding opens at launch until the owner clicks Done, unless kotoba is set up already (`AppPresence.window`).
    var needsOnboarding: Bool { !OnboardingController.isComplete && !readiness.isComplete }

    /// The window a Dock click or "Open kotoba…" shows (`AppPresence.reopenWindow`): onboarding while it goes on.
    var reopenWindow: AppPresence.LaunchWindow {
        AppPresence.reopenWindow(
            needsOnboarding: needsOnboarding, isOnboardingOpen: onboarding.isOpen,
            isOnboardingDone: OnboardingController.isComplete)
    }

    /// Onboarding where the owner left it, or at Welcome.
    func showOnboarding() {
        onboarding.show()
    }

    /// The dictionary was read at launch, after onboarding may have opened.
    func dictionaryOpened() {
        onboarding.dictionaryOpened()
    }

    /// "Finish Setting Up kotoba…", the menu's and Home's "Add Credit…", and Home's fix: onboarding on the first
    /// missing step. The Azure endpoint is set in the Speech page's "Advanced…" sheet, credit on the provider's site,
    /// as the pill's "Add Credit…".
    func finishSetup() {
        switch readiness.firstMissing {
        case .microphone, .accessibility: onboarding.show(step: .permissions)
        case .setup(.key, _): onboarding.show(step: .key)
        case .setup(.endpoint, _): links.otherSpeechServices()
        case .setup(.credit, let account): NSWorkspace.shared.open(account.creditsPage)
        case nil: onboarding.show()
        }
    }

    /// Home's "Try It…" before the first dictation: onboarding's Try It step.
    func tryIt() {
        onboarding.show(step: .tryIt)
    }

    /// The pill's "Allow Pasting…".
    func allowPasting() {
        onboarding.show(step: .permissions)
    }

    /// A grant made in System Settings shows without a click: Readiness reads again when the menu opens (the menu
    /// does that), when kotoba becomes active, and when macOS announces an Accessibility change, so onboarding sees
    /// the grant while System Settings is in front. macOS announces no Microphone change; returning to kotoba (an
    /// activation) reads it. Credit is read again when a request marks or clears it (`AccountCredit.changes`). Nothing
    /// runs at idle.
    func watchGrants() {
        creditChanges = Task { [weak self, changes = router.credit.changes] in
            for await _ in changes {
                self?.readiness.refresh()
            }
        }
        activations = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.readiness.refresh()
            }
        }
        accessibilityChanges = Task { [weak self] in
            for await _ in Self.accessibilityChanges() {
                // macOS posts it before `AXIsProcessTrusted` returns the new value; Loop and Hammerspoon read again
                // 150-250 ms later.
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                self?.readiness.refresh()
            }
        }
    }

    /// Each change of the Accessibility list in System Settings; a burst comes as one. AppKit holds a distributed
    /// notification until the app is active again unless its observer asks for immediate delivery, and the grant is
    /// made while System Settings is in front. The name is not documented; Hammerspoon, Loop and AltTab observe it on
    /// current macOS.
    private static func accessibilityChanges() -> AsyncStream<Void> {
        let (changes, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let relay = NotificationRelay { continuation.yield() }
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            relay, selector: #selector(NotificationRelay.received),
            name: Notification.Name("com.apple.accessibility.api"),
            object: nil, suspensionBehavior: .deliverImmediately)
        continuation.onTermination = { _ in center.removeObserver(relay) }
        return changes
    }

    /// Returns once the hotkey tap runs. The tap and Cmd-V need Accessibility, so it starts when Readiness sees
    /// the grant. A grant can take a moment to reach the event system, so a failed start tries twice more.
    /// Then it keeps the tap working: after a revoke and a new grant (Readiness goes from not allowed to allowed, by
    /// event, `watchGrants`), the tap is made again, since macOS may send nothing more to the old one.
    func startHotkeys(_ hotkeys: HotkeyTap) async {
        let readiness = readiness
        for await isAllowed in Observations({ readiness.isAccessibilityAllowed }) where isAllowed {
            guard await Self.start(hotkeys) else { continue }
            regrants = Task { [weak self] in await self?.remakeHotkeysAfterRegrant(hotkeys) }
            // A second way to see a revoke, if the Accessibility notification does not come.
            tapDisables = Task { [weak self] in
                for await _ in hotkeys.disabledByUserInput {
                    self?.readiness.refresh()
                }
            }
            return
        }
    }

    private func remakeHotkeysAfterRegrant(_ hotkeys: HotkeyTap) async {
        let readiness = readiness
        var wasAllowed = true
        for await isAllowed in Observations({ readiness.isAccessibilityAllowed }) {
            defer { wasAllowed = isAllowed }
            guard isAllowed, !wasAllowed else { continue }
            if await Self.start(hotkeys) {
                Log.app.notice("Hotkey tap made again after Accessibility came back")
            }
        }
    }

    private static func start(_ hotkeys: HotkeyTap) async -> Bool {
        for attempt in 0..<3 {
            if attempt > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return false
                }
            }
            if await hotkeys.start() { return true }
        }
        Log.app.error("The hotkey tap did not start although Accessibility is allowed")
        return false
    }
}
