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
            // The tallest Try It: a mark beside each shortcut row's title and the footnote.
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

    /// Try It's shortcut rows with the Wispr Flow mark beside their titles: Hands-free, whose subtitle fits on one line,
    /// and Push to talk, whose subtitle wraps, with kotoba's default keys and with Wispr Flow's one-side keys, whose
    /// names are wider than any modifier's; each over the same row with its keycaps hidden at no height. The run fails
    /// when the keycaps' centre is not Change…'s (owner QA 3, S1), when a wrapped row's keycaps leave its title line,
    /// when the gaps between the default keys differ within or across the rows, when the rows' last keycaps end at
    /// different x (owner QA 4, U2), or when a name touches the next name or Change….
    private static func keycapsBesideButtonSnapshot() -> Snapshot {
        let frames = KeycapFrames()
        let chords = HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option, keyCode: KeyCode.space))
        let rows = [
            KeycapRow(id: "handsFree", role: .handsFree, keys: chords.handsFree.keycaps, hasModifierNames: true),
            KeycapRow(id: "pushToTalk", role: .pushToTalk, keys: chords.pushToTalk.keycaps, hasModifierNames: true),
            KeycapRow(
                id: "handsFree one-side", role: .handsFree, keys: ["right ⌃", "right ⌥"], hasModifierNames: false),
            KeycapRow(id: "pushToTalk one-side", role: .pushToTalk, keys: ["right ⌥"], hasModifierNames: false),
        ]
        let items = rows.flatMap { row in [true, false].map { (row, $0) } }
        let check: @MainActor (NSView) -> String? = { _ in frames.problem(in: rows) }
        var snapshot = Snapshots.fixedWindow(named: "onboarding-keycaps-beside-button", size: size, check: check) {
            PageForm {
                Section {
                    // One ForEach: a form's rows need ids unique across the section.
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let (keycapRow, isShown) = item
                        let role = keycapRow.role
                        let subtitle =
                            role == .handsFree ? StatusText.shortcutHelp(.handsFree) : StatusText.pushToTalkHelp(chords)
                        let row = "\(keycapRow.id) \(isShown ? "shown" : "hidden")"
                        PageRow(title: StatusText.shortcutTitle(role), subtitle: subtitle) {
                            HStack {
                                if isShown {
                                    NamedKeycaps(keys: keycapRow.keys)
                                        .modifier(frames.measuring("\(row) keycaps"))
                                        .modifier(frames.measuringParts(row))
                                } else {
                                    // Their width, so the text wraps alike, at no height, with their guides reset to
                                    // that zero height's centre, so Change… sits as it would alone.
                                    NamedKeycaps(keys: keycapRow.keys).hidden()
                                        .frame(height: 0)
                                        .alignmentGuide(VerticalAlignment.center) { $0[VerticalAlignment.center] }
                                        .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
                                }
                                Button("Change…") {}.modifier(frames.measuring("\(row) button"))
                            }
                        } badge: {
                            WisprFlowPoint.ImportedMark()
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

    /// A shortcut row in `keycapsBesideButtonSnapshot`. `hasModifierNames`: every name is a modifier's ("command", not
    /// "right option"), so the keys sit one gap apart.
    struct KeycapRow {
        let id: String
        let role: ChordRole
        let keys: [String]
        let hasModifierNames: Bool
    }

    /// The frames `keycapsBesideButtonSnapshot` lays out, by name, in its form's coordinates.
    @MainActor final class KeycapFrames {
        nonisolated static let space = "keycaps-rows"
        var rects: [String: CGRect] = [:]
        /// Each shown row's keycaps and their names, left to right.
        var parts: [String: (keys: [CGRect], names: [CGRect])] = [:]

        func measuring(_ name: String) -> KeycapMeasuring { KeycapMeasuring(frames: self, name: name) }

        func measuringParts(_ row: String) -> KeycapPartsMeasuring { KeycapPartsMeasuring(frames: self, row: row) }

        func problem(in rows: [KeycapRow]) -> String? {
            for keycapRow in rows {
                let id = keycapRow.id
                guard let row = rects["\(id) shown"], let keycaps = rects["\(id) shown keycaps"],
                    let button = rects["\(id) shown button"], let bare = rects["\(id) hidden"],
                    let bareButton = rects["\(id) hidden button"]
                else { return "the \(id) rows were not laid out" }
                let keysCentre = keycaps.minY + NamedKeycaps.keysCentre
                if abs(keysCentre - button.midY) > 0.5 {
                    return "the \(id) keycaps centre \(keysCentre - button.midY) pt off Change…"
                }
                // Change… alone sits on the title line of a wrapped row.
                let offTitle = (keysCentre - row.minY) - (bareButton.midY - bare.minY)
                if keycapRow.role == .pushToTalk, abs(offTitle) > 0.5 {
                    return "the \(id) keycaps centre \(offTitle) pt off the row's title line"
                }
            }
            return spacingProblem(in: rows)
        }

        /// One gap between every two keycaps of the rows with modifier names, every row's last keycap at one x, and
        /// every name inside its keycaps' view, clear of the next name and of Change….
        private func spacingProblem(in rows: [KeycapRow]) -> String? {
            var gaps: [CGFloat] = []
            var ends: [CGFloat] = []
            for keycapRow in rows {
                let id = keycapRow.id
                guard let (keys, names) = parts["\(id) shown"], let last = keys.last,
                    let view = rects["\(id) shown keycaps"], let button = rects["\(id) shown button"]
                else { return "the \(id) keycaps were not measured" }
                if keycapRow.hasModifierNames {
                    gaps += zip(keys, keys.dropFirst()).map { $1.minX - $0.maxX }
                }
                ends.append(last.maxX)
                for (name, next) in zip(names, names.dropFirst()) where next.minX - name.maxX < 1 {
                    return "the \(id) key names are \(next.minX - name.maxX) pt apart"
                }
                if let name = names.first, name.minX < view.minX - 0.5 {
                    return "the \(id) first key name starts \(view.minX - name.minX) pt before its view"
                }
                if let name = names.last, button.minX - name.maxX < 1 {
                    return "the \(id) last key name ends \(button.minX - name.maxX) pt before Change…"
                }
            }
            if let low = gaps.min(), let high = gaps.max(), high - low > 0.5 {
                return "the keycap gaps run from \(low) to \(high) pt"
            }
            if let low = ends.min(), let high = ends.max(), high - low > 0.5 {
                return "the rows' last keycaps end \(high - low) pt apart"
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

/// Records the frames of a `NamedKeycaps`' keycaps and names in `KeycapFrames.space` under `row`.
struct KeycapPartsMeasuring: ViewModifier {
    let frames: OnboardingController.KeycapFrames
    let row: String

    func body(content: Content) -> some View {
        content.backgroundPreferenceValue(NamedKeycaps.Parts.self) { parts in
            Color.clear.onGeometryChange(for: [CGRect].self) { proxy in
                let origin = proxy.frame(in: .named(OnboardingController.KeycapFrames.space)).origin
                return parts.map { proxy[$0.bounds].offsetBy(dx: origin.x, dy: origin.y) }
            } action: { rects in
                let isName = parts.map(\.isName)
                let sorted = { (names: Bool) in
                    zip(rects, isName).filter { $0.1 == names }.map(\.0).sorted { $0.minX < $1.minX }
                }
                frames.parts[row] = (sorted(false), sorted(true))
            }
        }
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
