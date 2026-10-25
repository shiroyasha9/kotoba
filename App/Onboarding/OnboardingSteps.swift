import KotobaCore
import KotobaProviders
import SwiftUI

// The onboarding steps, each a `PageForm`'s sections with its `StepHeading` over the first card. `OnboardingView`
// shows one at a time. Welcome is in `WelcomeStep.swift`.

/// A chord as keycaps with each key's name in small text under it, as a Mac keyboard prints "control" under ⌃
/// (docs/research/ui-redesign.md, "Onboarding"): the first time the owner meets the symbols, the names teach them. A
/// one-side modifier ("right ⌥", from Wispr Flow's keys) draws its symbol, and its name says the side.
struct NamedKeycaps: View {
    let keys: [String]

    var body: some View {
        // Every column as wide as the widest name (“command”), each centred on its key, so the keys sit evenly as on a
        // keyboard: under each key, the chord's names lie hidden in one stack, which takes the widest one's width.
        let keys = keys.map(Self.legendAndName)
        let names = keys.compactMap(\.name)
        HStack(alignment: .top) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                VStack {
                    Keycaps(keys: [key.legend])
                    ZStack {
                        ForEach(names, id: \.self) { Text($0).hidden() }
                        if let name = key.name {
                            Text(name)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        // At its own width beside Change…: the row's text wraps instead of the key names.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.map { $0.name ?? $0.legend }.joined(separator: " "))
    }

    /// What a key's cap draws, and the name under it: "right ⌥" draws ⌥ over "right option".
    private static func legendAndName(_ key: String) -> (legend: String, name: String?) {
        for side in ["left ", "right "] where key.hasPrefix(side) {
            let legend = String(key.dropFirst(side.count))
            if let name = Keycaps.names[legend] { return (legend, side + name) }
        }
        return (key, Keycaps.names[key])
    }
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
                // Plain, as System Settings' privacy rows: a default button draws in the accent colour, and the step's
                // one prominent button is Continue once both grants arrive (owner QA 2, R2).
                case .denied:
                    Button("Open System Settings…", action: model.openMicrophoneSettings)
                case .notAsked:
                    Button("Allow…") { Task { await model.allowMicrophone() } }
                }
            }
            PageRow(title: "Accessibility", subtitle: "For your shortcut and the paste, in any app.") {
                SymbolTile(systemImage: "accessibility", tint: .blue, side: PageMetrics.rowTileSide)
            } trailing: {
                if model.readiness.isAccessibilityAllowed {
                    StatusLine("Allowed", .good)
                } else {
                    Button("Allow…", action: model.allowAccessibility)
                }
            }
        } header: {
            StepHeading(
                title: "Allow Access",
                text: Text("kotoba needs both to work in every app."))
        } footer: {
            // What Learn from edits reads is said on its switch in Dictionary, where it is turned on
            // (docs/research/copywriting.md, Onboarding steps).
            if !model.readiness.isAccessibilityAllowed {
                Text("Already on in the Accessibility list? Turn kotoba off and on again.")
            }
        }
    }

    private var microphoneText: String {
        switch model.readiness.microphone {
        case .denied: "Access is off. Turn on kotoba in the Microphone list."
        case .allowed, .notAsked: "To hear you while you dictate."
        }
    }
}

/// The speech service's key: kotoba sends the audio there with the owner's own key.
struct KeyStep: View {
    let model: OnboardingModel

    var body: some View {
        let provider = model.account.title
        Section {
            keyRow(provider: provider)
            result
        } header: {
            StepHeading(
                title: "Connect \(provider)",
                text: Text("Your audio goes straight to \(provider), with your own key."))
        } footer: {
            PriceLine(route: model.route)
        }
        // The other services in a group of their own, clear of the key's links (owner QA, 2026-10-25: three links in
        // one line looked crammed).
        Section {
            PageRow(title: "xAI or Azure", subtitle: "Use another speech service.") {
                Button("Open Speech Settings…", action: model.openOtherSpeechServices)
            }
        }
    }

    /// The key's name with "Get a Key at …" under it, as System Settings puts a row's link under its title, and the
    /// field beside them. Custom: a `PageRow` subtitle is text, not a link.
    private func keyRow(provider: String) -> some View {
        HStack {
            RowLeading {
                SymbolTile(
                    systemImage: PaneID.speech.systemImage, tint: PaneID.speech.tint, side: PageMetrics.rowTileSide)
            } content: {
                VStack(alignment: .leading) {
                    Text("\(provider) key")
                    // Gone once a key is saved, unless the provider refused it: Change… is then the next thing to do.
                    if !model.keyChecks.isSaved(model.account)
                        || model.keyChecks.status[model.account] == .checked(.invalid)
                    {
                        Button("Get a Key at \(provider)…") { model.open(model.account.keysPage) }
                            .buttonStyle(.link)
                            .font(.subheadline)
                    }
                }
            }
            Spacer()
            KeyField(account: model.account, route: model.route, keyChecks: model.keyChecks)
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

/// Both ways to dictate with their keys drawn as keycaps (docs/research/ui-redesign.md, "Onboarding": keys as keycaps
/// with their names, never a chord in a sentence), each with Change…, and the field the words arrive in (owner QA 3, S2:
/// the rows moved here from Welcome, so the owner sets the keys where they first use them). A line under a row whose
/// chord Welcome took from Wispr Flow says so, and a footnote asks to quit Wispr Flow while it runs on the same keys.
struct TryItStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var isFieldFocused: Bool
    /// The way to dictate whose Change… sheet is open.
    @State private var changing: ChordRole?

    var body: some View {
        let chords = model.chords
        let wisprRoles = model.wisprShortcutRoles
        // Both ways to dictate sit together above the field, so the result line below never moves them.
        Section {
            shortcutRow(
                .handsFree, subtitle: StatusText.shortcutHelp(.handsFree), chord: chords.handsFree,
                isFromWispr: wisprRoles.contains(.handsFree))
            shortcutRow(
                .pushToTalk, subtitle: StatusText.pushToTalkHelp(chords), chord: chords.pushToTalk,
                isFromWispr: wisprRoles.contains(.pushToTalk))
        } header: {
            StepHeading(title: "Try It", text: Text("Say “Hello from kotoba.”"))
        } footer: {
            // kotoba does not quit Wispr Flow: while it runs on a chord kotoba took, one press starts both apps.
            if model.isWisprRunning, !wisprRoles.isEmpty {
                Text(WisprFlowPoint.runningText)
            }
        }
        Section {
            TextField("Try It", text: $model.tryItText, prompt: Text("Your words appear here"), axis: .vertical)
                .labelsHidden()
                .lineLimit(3...5)
                .focused($isFieldFocused)
                .onAppear(perform: focusField)
        } footer: {
            // Always laid out, so the step does not move when the dictation works.
            let works = model.isDone(.tryIt)
            StatusLine("It works.", .good)
                .opacity(works ? 1 : 0)
                .accessibilityHidden(!works)
        }
        // The recorder pauses the hotkey tap while it listens (`HotkeyChords.isRecording`), so the press it records
        // starts no dictation; the new chord applies at once. Back in the field, the next press pastes there.
        .sheet(
            isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } }),
            onDismiss: focusField
        ) {
            if let changing {
                ShortcutSheet(chords: chords, role: changing)
            }
        }
    }

    private func focusField() {
        isFieldFocused = true
    }

    /// A way to dictate: its keycaps and Change… with the Shortcuts page's recorder, and under its subtitle the line
    /// that says its chord came from Wispr Flow.
    private func shortcutRow(_ role: ChordRole, subtitle: String, chord: Chord, isFromWispr: Bool) -> some View {
        PageRow(title: StatusText.shortcutTitle(role), subtitle: subtitle) {
            HStack {
                NamedKeycaps(keys: chord.keycaps)
                Button("Change…") { changing = role }
                    .accessibilityLabel("Change \(StatusText.shortcutTitle(role)) Shortcut")
            }
        } extra: {
            if isFromWispr {
                WisprFlowPoint.ImportedLine()
            }
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
            Toggle("Start and stop sounds", isOn: $model.playsSounds)
            // Turning it takes effect at once; the default (on for a release build) applies at Done.
            Toggle(
                "Open at login",
                isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
        } header: {
            if model.firstMissingStep == nil {
                heading(isReady: isReady)
            }
        } footer: {
            // A footnote under the switch, as System Settings writes one, only after the owner turned it.
            if let problem = model.loginProblem {
                LoginItemFootnote(problem: problem)
            }
        }
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
            text: Text(
                isReady ? "Dictate in any app. kotoba stays in the menu bar." : "Fix this, then dictate in any app."))
    }

    /// What the row says before and after the import.
    private var wisprText: String {
        guard let added = model.wisprImported else {
            return "Bring your words and replacements."
        }
        return added.isEmpty ? "Every word is already in your dictionary." : "Added \(added.countsText)."
    }

    private static func fixTitle(_ step: OnboardingStep) -> String {
        step == .permissions ? "Allow Access" : "Add Your Key"
    }
}

/// One way to dictate with the Shortcuts page's recorder (`ChordRecorder`), from Try It's Change….
struct ShortcutSheet: View {
    let chords: HotkeyChords
    let role: ChordRole

    var body: some View {
        PageSheet(title: "Change Shortcut") {
            Section {
                ChordRecorder(chords: chords, role: role, help: help)
            } footer: {
                Text("You can change every shortcut later on kotoba’s Shortcuts page.")
            }
        }
    }

    private var help: String {
        role == .pushToTalk ? StatusText.pushToTalkHelp(chords) : StatusText.shortcutHelp(role)
    }
}
