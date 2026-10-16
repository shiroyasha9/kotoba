import AVFAudio
import AppKit
import KotobaCore
import KotobaProviders
import Observation

/// What kotoba still needs before a dictation works end to end: the mic, Accessibility, and the key or endpoint
/// of the current speech model. One value for the menu status line, the menu bar icon and onboarding.
/// `refresh()` reads everything again; each read is cheap (`KeyVault` caches `hasKey`), so call it freely.
@MainActor
@Observable
final class Readiness {
    enum Microphone: Sendable {
        case allowed
        /// macOS has not asked yet; onboarding asks.
        case notAsked
        case denied
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

        static func live(settings: TranscriptionSettings, vault: KeyVault) -> Self {
            Self(
                microphone: {
                    switch AVAudioApplication.shared.recordPermission {
                    case .granted: .allowed
                    case .undetermined: .notAsked
                    default: .denied
                    }
                },
                isAccessibilityAllowed: { AXIsProcessTrusted() },
                missingSetup: { settings.missingSetup(hasKey: vault.hasKey(for:)).map { ($0, settings.route.account) } }
            )
        }
    }

    private(set) var microphone: Microphone
    private(set) var isAccessibilityAllowed: Bool
    /// The key or endpoint the current speech model still needs, and whose.
    private(set) var missingSetup: (item: SetupItem, account: ProviderAccount)?

    @ObservationIgnored private let reader: Reader

    /// The first thing to set up, or nil when kotoba is ready.
    var firstMissing: Missing? {
        if microphone != .allowed { return .microphone }
        if !isAccessibilityAllowed { return .accessibility }
        return missingSetup.map { .setup($0.item, $0.account) }
    }

    var isComplete: Bool { firstMissing == nil }

    init(reader: Reader) {
        self.reader = reader
        microphone = reader.microphone()
        isAccessibilityAllowed = reader.isAccessibilityAllowed()
        missingSetup = reader.missingSetup()
    }

    convenience init(settings: TranscriptionSettings, vault: KeyVault) {
        self.init(reader: .live(settings: settings, vault: vault))
    }

    /// Fixed values, for snapshots: reads no permission, Keychain or setting.
    static func sample(
        microphone: Microphone = .allowed, isAccessibilityAllowed: Bool = true,
        missingSetup: (item: SetupItem, account: ProviderAccount)? = nil
    ) -> Readiness {
        Readiness(
            reader: Reader(
                microphone: { microphone }, isAccessibilityAllowed: { isAccessibilityAllowed },
                missingSetup: { missingSetup }))
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

/// The setup flow around `Readiness`: onboarding at first launch and from "Finish Setting Up kotoba…", and the
/// hotkey tap, which starts once Accessibility is allowed. No permission prompt appears before its onboarding
/// step (ux-polish O2).
@MainActor
final class SetupFlow {
    let readiness: Readiness
    private let openSpeechSettings: @MainActor () -> Void
    private lazy var onboarding = OnboardingController(
        readiness: readiness, routeSettings: routeSettings, vault: vault, router: router,
        openSpeechSettings: openSpeechSettings)
    private let routeSettings: TranscriptionSettings
    private let vault: KeyVault
    private let router: TranscriptionRouter
    private var activations: Task<Void, Never>?
    /// Reads Readiness every second while a kotoba window is open; ends when the last one closes.
    private var windowPoll: Task<Void, Never>?

    /// `router` checks a key in onboarding.
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

    /// Onboarding opens at launch until the owner clicks Done, unless kotoba is set up already (`AppPresence.window`).
    var needsOnboarding: Bool { !OnboardingController.isComplete && !readiness.isComplete }

    /// Onboarding where the owner left it, or at Welcome.
    func showOnboarding() {
        onboarding.show()
    }

    /// "Finish Setting Up kotoba…": onboarding on the first missing step. An Azure endpoint is set in Settings.
    func finishSetup() {
        switch readiness.firstMissing {
        case .microphone: onboarding.show(step: .microphone)
        case .accessibility: onboarding.show(step: .accessibility)
        case .setup(.key, _): onboarding.show(step: .key)
        case .setup(.endpoint, _), .setup(.credit, _): openSpeechSettings()
        case nil: onboarding.show()
        }
    }

    /// The pill's "Allow Pasting…".
    func allowPasting() {
        onboarding.show(step: .accessibility)
    }

    /// A grant made in System Settings shows without a click: Readiness reads again when the menu opens (the menu
    /// does that), when kotoba becomes active, and every second while a kotoba window is open (lead decision 4).
    func watchGrants() {
        activations = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.pollWhileWindowsOpen()
            }
        }
    }

    private func pollWhileWindowsOpen() {
        readiness.refresh()
        guard windowPoll == nil else { return }
        windowPoll = Task { [weak self] in
            while Self.isWindowOpen {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                self?.readiness.refresh()
            }
            self?.windowPoll = nil
        }
    }

    /// Settings, onboarding or Fix Last Dictation; the pill panel and the menu have no title bar.
    private static var isWindowOpen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
    }

    /// Returns once the hotkey tap runs. The tap and Cmd-V need Accessibility, so it starts when Readiness sees
    /// the grant. A grant can take a moment to reach the event system, so a failed start tries twice more.
    func startHotkeys(_ hotkeys: HotkeyTap) async {
        let readiness = readiness
        for await isAllowed in Observations({ readiness.isAccessibilityAllowed }) where isAllowed {
            for _ in 0..<3 {
                if await hotkeys.start() { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
            Log.app.error("The hotkey tap did not start although Accessibility is allowed")
        }
    }
}
