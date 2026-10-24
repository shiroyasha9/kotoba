import KotobaCore
import KotobaProviders
import SwiftUI

// The onboarding steps, each a `PageForm`'s sections with its `StepHeading` over the first card. `OnboardingView`
// shows one at a time.

/// What kotoba is good at, in three rows, and both ways to dictate with their keys drawn as keycaps.
struct WelcomeStep: View {
    var body: some View {
        let chords = HotkeyChords.shared
        Section {
            Point("Fast", systemImage: "bolt", tint: .green, text: "Your words appear about a second after you stop.")
            Point(
                "Accurate", page: .dictionary,
                text: "Add names and terms to your dictionary, and kotoba spells them your way.")
            Point(
                "Private", systemImage: "hand.raised", tint: .blue,
                text: "No account. Your audio goes only to the speech service you choose, with your own key.")
        } header: {
            StepHeading(
                title: "Talk Instead of Type",
                text: Text("Speak in any app, and kotoba types your words where your cursor is.")
            ) {
                AppIconView(icon: NSApp.applicationIconImage, side: PageMetrics.welcomeIconSide)
            }
        }
        Section {
            PageRow(title: StatusText.shortcutTitle(.handsFree), subtitle: StatusText.shortcutHelp(.handsFree)) {
                NamedKeycaps(keys: chords.handsFree.keycaps)
            }
            PageRow(title: StatusText.shortcutTitle(.pushToTalk), subtitle: StatusText.pushToTalkHelp(chords)) {
                NamedKeycaps(keys: chords.pushToTalk.keycaps)
            }
        }
    }

    /// One selling point: a tile, a short title and one sentence, as a "What’s New" sheet shows a feature.
    private struct Point: View {
        let title: String
        let systemImage: String
        let tint: Color
        let text: String

        init(_ title: String, systemImage: String, tint: Color, text: String) {
            self.title = title
            self.systemImage = systemImage
            self.tint = tint
            self.text = text
        }

        /// A point about a page shows that page's sidebar tile.
        init(_ title: String, page: PaneID, text: String) {
            self.init(title, systemImage: page.systemImage, tint: page.tint, text: text)
        }

        var body: some View {
            PageRow(title: title, subtitle: text) {
                SymbolTile(systemImage: systemImage, tint: tint, side: PageMetrics.rowTileSide)
            } trailing: {
                EmptyView()
            }
        }
    }
}

/// A chord as keycaps with each key's name in small text under it, as a Mac keyboard prints "control" under ⌃
/// (docs/research/ui-redesign.md, "Onboarding"): the first time the owner meets the symbols, the names teach them.
struct NamedKeycaps: View {
    let keys: [String]

    var body: some View {
        HStack(alignment: .top) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                VStack {
                    Keycaps(keys: [key])
                    if let name = Self.names[key] {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map { Self.names[$0] ?? $0 }.joined(separator: " "))
    }

    /// The names Apple's keyboards print on the modifier keys. A letter or a word key ("Space") names itself.
    private static let names = ["⌃": "control", "⌥": "option", "⌘": "command", "⇧": "shift", "fn": "fn"]
}

/// The microphone and Accessibility, one row each with its own Allow button. kotoba cannot work without either, so
/// Continue waits for both (`OnboardingFlow.footer`).
struct PermissionsStep: View {
    let model: OnboardingModel

    var body: some View {
        Section {
            PageRow(title: "Microphone", subtitle: microphoneText) {
                SymbolTile(
                    systemImage: PaneID.microphones.systemImage, tint: PaneID.microphones.tint,
                    side: PageMetrics.rowTileSide)
            } trailing: {
                switch model.readiness.microphone {
                case .allowed:
                    StatusLine("Allowed", .good)
                case .denied:
                    Button("Open System Settings…", action: model.openMicrophoneSettings)
                        .keyboardShortcut(.defaultAction)
                case .notAsked:
                    Button("Allow…") { Task { await model.allowMicrophone() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            PageRow(title: "Accessibility", subtitle: "So your shortcut works in every app, and kotoba can paste.") {
                SymbolTile(systemImage: "accessibility", tint: .blue, side: PageMetrics.rowTileSide)
            } trailing: {
                if model.readiness.isAccessibilityAllowed {
                    StatusLine("Allowed", .good)
                } else {
                    // The default button once the microphone is done, so one button at a time stands out and Return goes
                    // on to the next grant.
                    Button("Allow…", action: model.allowAccessibility)
                        .keyboardShortcut(model.readiness.microphone == .allowed ? .defaultAction : nil)
                }
            }
        } header: {
            StepHeading(
                title: "Allow Access",
                text: Text(
                    "kotoba needs the microphone to hear you, and Accessibility for your shortcut and to type your "
                        + "words."))
        } footer: {
            VStack(alignment: .leading) {
                Text(
                    "kotoba reads only the text field it pasted into, and only when “Learn from my edits” is on, "
                        + "to learn your corrections. It never reads your screen.")
                if !model.readiness.isAccessibilityAllowed {
                    Text(
                        "If kotoba is on in the Accessibility list already and this step stays open, turn it off "
                            + "and on again.")
                }
            }
        }
    }

    private var microphoneText: String {
        switch model.readiness.microphone {
        case .denied: "Access is off. Turn on kotoba in the Microphone list."
        case .allowed, .notAsked: "Used only while you dictate, with an orange dot in the menu bar."
        }
    }
}

/// The speech service's key: kotoba sends the audio there with the owner's own key.
struct KeyStep: View {
    let model: OnboardingModel

    var body: some View {
        let provider = model.account.title
        Section {
            PageRow(title: "\(provider) key", subtitle: nil) {
                SymbolTile(
                    systemImage: PaneID.speech.systemImage, tint: PaneID.speech.tint, side: PageMetrics.rowTileSide)
            } trailing: {
                KeyField(account: model.account, keyChecks: model.keyChecks)
            }
            result
        } header: {
            StepHeading(
                title: "Connect a Speech Service",
                text: Text("kotoba sends your audio to \(provider), which turns it into text."))
        } footer: {
            VStack(alignment: .leading) {
                PriceLine(route: model.route)
                // Below the card, so a link that goes away moves nothing the pointer is on.
                HStack {
                    // Gone once a key is saved, unless the provider refused it: Change… is then the next thing to do.
                    if !model.keyChecks.isSaved(model.account)
                        || model.keyChecks.status[model.account] == .checked(.invalid)
                    {
                        Button("Get a Key at \(provider)…") { model.open(model.account.keysPage) }
                    }
                    Button("Use xAI or Azure Instead…", action: model.openOtherSpeechServices)
                }
                .buttonStyle(.link)
            }
        }
    }

    /// The shared check result after a save here; with none, what `Readiness` knows about a key saved before.
    /// In the row's text column, under the key's name.
    @ViewBuilder private var result: some View {
        if let status = model.keyChecks.status[model.account] {
            KeyCheckLine(status: status, account: model.account).inRowTextColumn()
        } else if model.readiness.missingSetup?.item == .endpoint {
            StatusLine("Key saved. Add your Azure endpoint to check it.", .neutral).inRowTextColumn()
        } else if model.readiness.missingSetup == nil {
            StatusLine("Key saved", .good).inRowTextColumn()
        }
    }
}

struct TryItStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let chord = HotkeyChords.shared.handsFree.title
        let hold = StatusText.holdToDictate(.shared)
        Section {
            TextField("Try It", text: $model.tryItText, prompt: Text("Your words appear here"), axis: .vertical)
                .labelsHidden()
                .lineLimit(3...5)
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
        } header: {
            // Both ways to dictate sit together above the field, so the result line below never moves them.
            StepHeading(
                title: "Try It",
                text: Text("Press \(chord), say “Hello from kotoba”, then press \(chord) again. \(hold)"))
        } footer: {
            // Always laid out, so the step does not move when the dictation works.
            let works = model.isDone(.tryIt)
            StatusLine("It works.", .good)
                .opacity(works ? 1 : 0)
                .accessibilityHidden(!works)
        }
    }
}

/// Setup's result, the two choices a new install makes, and the Wispr Flow import when Wispr Flow is on this Mac.
struct DoneStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        let isReady = model.readiness.isComplete
        if let step = model.firstMissingStep, let missing = model.readiness.firstMissing {
            Section {
                PageRow(title: missing.problemText, subtitle: nil) {
                    SymbolTile(systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
                } trailing: {
                    if model.readiness.missingSetup?.item == .endpoint {
                        Button("Add Your Azure Endpoint…", action: model.openOtherSpeechServices)
                    } else {
                        Button(Self.fixTitle(step)) { model.step = step }
                    }
                }
            } header: {
                heading(isReady: isReady)
            }
        }
        Section {
            Toggle(
                "Open kotoba when you log in",
                isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
            if let problem = model.loginProblem {
                PageRow(title: problem.text, subtitle: nil) {
                    Button("Open Login Items…", action: model.openLoginItemsSettings)
                }
            }
            Toggle("Play a sound when dictation starts and stops", isOn: $model.playsSounds)
        } header: {
            if model.firstMissingStep == nil {
                heading(isReady: isReady)
            }
        }
        // Applied as the step shows (default on), so a problem shows here before Done closes the window.
        .task { model.setOpensAtLogin(model.opensAtLogin) }
        if model.offersWisprImport {
            Section {
                PageRow(title: "Wispr Flow dictionary", subtitle: wisprText) {
                    SymbolTile(
                        systemImage: PaneID.dictionary.systemImage, tint: PaneID.dictionary.tint,
                        side: PageMetrics.rowTileSide)
                } trailing: {
                    if model.wisprImported != nil {
                        StatusLine("Imported", .good)
                    } else if model.dictionary?.wisprImport?.isReading == true {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Import…", action: model.previewWisprImport)
                    }
                }
            }
        }
    }

    private func heading(isReady: Bool) -> some View {
        StepHeading(
            title: isReady ? "You’re Ready" : "Almost Ready",
            text: Text("Open kotoba from the menu bar or the Dock to change your microphone or settings."))
    }

    /// What the row says before and after the import.
    private var wisprText: String {
        guard let added = model.wisprImported else {
            return "Add your words and replacements from Wispr Flow, so kotoba spells them right from the start."
        }
        return added.isEmpty ? "Your dictionary already has every word from Wispr Flow." : "Added \(added.countsText)."
    }

    private static func fixTitle(_ step: OnboardingStep) -> String {
        step == .permissions ? "Allow Access" : "Add Your Key"
    }
}
