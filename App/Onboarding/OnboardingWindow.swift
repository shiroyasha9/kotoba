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

    /// The window is shown or minimised.
    var isOpen: Bool { window != nil }

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
        ] + welcomeSnapshots(ready) + [keycapsBesideButtonSnapshot()]
    }

    /// Welcome with Wispr Flow's shortcuts usable (the sample's hands-free), unusable and absent; then Try It with the
    /// shortcuts Welcome took: one mode (the other is one kotoba cannot take), both, one equal to kotoba's default; while
    /// Wispr Flow runs; after the owner changed a taken chord; and Change…'s sheet.
    private static func welcomeSnapshots(_ ready: Readiness) -> [Snapshot] {
        let both = ["62+61": "popo", "49+58": "ptt"]
        return [
            window("onboarding-welcome-no-wispr-shortcuts") { model(.welcome, ready, wisprKeys: nil) },
            window("onboarding-welcome-no-wispr") { model(.welcome, ready, isWisprInstalled: false) },
            window("onboarding-tryIt-wispr") { tookWispr(model(.welcome, ready)) },
            window("onboarding-tryIt-wispr-running") { tookWispr(model(.welcome, ready, wisprRuns: true)) },
            window("onboarding-tryIt-wispr-both") { tookWispr(model(.welcome, ready, wisprKeys: both)) },
            // The tallest Try It: a line under each shortcut row and the footnote.
            window("onboarding-tryIt-wispr-both-running") {
                tookWispr(model(.welcome, ready, wisprKeys: both, wisprRuns: true))
            },
            window("onboarding-tryIt-wispr-default") {
                tookWispr(model(.welcome, ready, wisprKeys: ["55+58+59": "popo"]))
            },
            window("onboarding-tryIt-wispr-changed") {
                let model = tookWispr(model(.welcome, ready, wisprKeys: both, wisprRuns: true))
                _ = model.chords.save(Chord(modifiers: .function), as: .handsFree)
                return model
            },
            MainWindow.sheetSnapshot(named: "onboarding-change-shortcut") {
                ShortcutSheet(chords: HotkeyChords(defaults: nil), role: .handsFree)
            },
        ]
    }

    /// Try It after Welcome took Wispr Flow's shortcuts: only Welcome takes them.
    private static func tookWispr(_ model: OnboardingModel) -> OnboardingModel {
        model.step = .tryIt
        return model
    }

    /// Try It's shortcut rows with their text in three lines (the Wispr Flow line under the subtitle): Hands-free,
    /// whose subtitle fits on one line, and Push to talk, whose subtitle wraps, each over the same row with its keycaps
    /// hidden at no height. The run fails when the keycaps' centre is not Change…'s (owner QA 3, S1), when the keycaps'
    /// names make a row taller, or when the wrapped row's keycaps leave its title line.
    private static func keycapsBesideButtonSnapshot() -> Snapshot {
        let frames = KeycapFrames()
        let chords = HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option, keyCode: KeyCode.space))
        let roles: [ChordRole] = [.handsFree, .pushToTalk]
        let rows = roles.flatMap { role in [true, false].map { (role, $0) } }
        let check: @MainActor (NSView) -> String? = { _ in frames.problem(in: roles) }
        var snapshot = Snapshots.fixedWindow(named: "onboarding-keycaps-beside-button", size: size, check: check) {
            PageForm {
                Section {
                    // One ForEach: a form's rows need ids unique across the section.
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                        let (role, isShown) = item
                        let keys = (role == .handsFree ? chords.handsFree : chords.pushToTalk).keycaps
                        let subtitle =
                            role == .handsFree ? StatusText.shortcutHelp(.handsFree) : StatusText.pushToTalkHelp(chords)
                        let row = "\(role) \(isShown ? "shown" : "hidden")"
                        PageRow(title: StatusText.shortcutTitle(role), subtitle: subtitle) {
                            HStack {
                                if isShown {
                                    NamedKeycaps(keys: keys).modifier(frames.measuring("\(row) keycaps"))
                                } else {
                                    // Their width, so the text wraps alike, at no height, with their guides reset to
                                    // that zero height's centre, so Change… sits as it would alone.
                                    NamedKeycaps(keys: keys).hidden()
                                        .frame(height: 0)
                                        .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
                                        .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
                                }
                                Button("Change…") {}.modifier(frames.measuring("\(row) button"))
                            }
                        } extra: {
                            WisprFlowPoint.ImportedLine()
                        }
                        .modifier(frames.measuring(row))
                    }
                }
            }
            .frame(width: size.width)
            .coordinateSpace(.named(KeycapFrames.space))
        }
        // The form sets its rows' measured heights in the window's first run loop turn.
        snapshot.settlesInWindow = true
        return snapshot
    }

    /// The frames `keycapsBesideButtonSnapshot` lays out, by name, in its form's coordinates.
    @MainActor final class KeycapFrames {
        static let space = "keycaps-rows"
        var rects: [String: CGRect] = [:]

        func measuring(_ name: String) -> KeycapMeasuring { KeycapMeasuring(frames: self, name: name) }

        func problem(in roles: [ChordRole]) -> String? {
            for role in roles {
                guard let row = rects["\(role) shown"], let keycaps = rects["\(role) shown keycaps"],
                    let button = rects["\(role) shown button"], let bare = rects["\(role) hidden"],
                    let bareButton = rects["\(role) hidden button"]
                else { return "the \(role) rows were not laid out" }
                let keysCentre = keycaps.minY + NamedKeycaps.keysCentre
                if abs(keysCentre - button.midY) > 0.5 {
                    return "the \(role) keycaps centre \(keysCentre - button.midY) pt off Change…"
                }
                if row.height > bare.height + 0.5 {
                    return "the keycaps make the \(role) row \(row.height) pt tall, \(bare.height) pt without them"
                }
                // Change… alone sits on the title line of a wrapped row.
                let offTitle = (keysCentre - row.minY) - (bareButton.midY - bare.minY)
                if role == .pushToTalk, abs(offTitle) > 0.5 {
                    return "the \(role) keycaps centre \(offTitle) pt off the row's title line"
                }
            }
            return nil
        }
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

/// Records a view's frame in `KeycapFrames.space` under `name`.
struct KeycapMeasuring: ViewModifier {
    let frames: OnboardingController.KeycapFrames
    let name: String

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(OnboardingController.KeycapFrames.space))
        } action: {
            frames.rects[name] = $0
        }
    }
}
