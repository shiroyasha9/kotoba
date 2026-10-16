import KotobaCore
import KotobaProviders
import SwiftUI

// The onboarding steps and the small views they share. `OnboardingView` shows one at a time.

private struct StepText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: OnboardingView.textWidth)
    }
}

// MARK: - Steps

/// What kotoba is good at, in three short points, and both ways to dictate. Keys show as symbols only (owner,
/// 2026-10-16).
struct WelcomeStep: View {
    var body: some View {
        StepText("Speak in any app, and kotoba types your words where your cursor is.")
        VStack(alignment: .leading, spacing: 12) {
            Point("Fast", systemImage: "bolt", text: "Your words appear about one second after you stop.")
            Point(
                "Accurate", systemImage: "character.book.closed",
                text: "Add names and terms to your dictionary, and kotoba spells them your way.")
            Point(
                "Private", systemImage: "lock",
                text:
                    "kotoba needs no account. Your audio goes only to the speech service you choose, with your own key."
            )
        }
        .frame(width: OnboardingView.textWidth, alignment: .leading)
        .padding(.vertical, 2)
        Form {
            Section {
                LabeledContent(StatusText.shortcutTitle(.handsFree)) {
                    ChordRecorder(chords: .shared, role: .handsFree)
                }
                LabeledContent(StatusText.shortcutTitle(.pushToTalk)) {
                    ChordRecorder(chords: .shared, role: .pushToTalk)
                }
            } footer: {
                let chords = HotkeyChords.shared
                Text(
                    "Tap \(chords.handsFree.title), speak, then tap it again.\n" + StatusText.holdToDictate(chords)
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // A form fills its container; here it is only as tall as its rows.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: OnboardingView.textWidth + 20)
    }

    /// One selling point: a symbol, a short title and one sentence, as a "What’s New" sheet shows a feature.
    private struct Point: View {
        let title: String
        let systemImage: String
        let text: String

        init(_ title: String, systemImage: String, text: String) {
            self.title = title
            self.systemImage = systemImage
            self.text = text
        }

        var body: some View {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
            }
            .multilineTextAlignment(.leading)
        }
    }
}

struct MicrophoneStep: View {
    let model: OnboardingModel

    var body: some View {
        StepText("kotoba listens only while you dictate. The orange dot in the menu bar shows when the mic is on.")
        Group {
            switch model.readiness.microphone {
            case .allowed:
                StatusLine("Microphone allowed", .good)
            case .denied:
                StatusLine("Microphone access is off.", .problem)
                Button("Open System Settings…", action: model.openMicrophoneSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                Text("Turn on kotoba in the Microphone list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .notAsked:
                Button("Allow Microphone") { Task { await model.allowMicrophone() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
        .padding(.top, 8)
    }
}

struct AccessibilityStep: View {
    let model: OnboardingModel

    var body: some View {
        StepText(
            "kotoba needs Accessibility to notice \(StatusText.dictationChords(.shared)) in every app and to paste "
                + "your text. kotoba reads only the text field it pasted into, and only when “Learn from my edits” "
                + "is on, to learn your corrections. It never reads your screen."
        )
        if model.readiness.isAccessibilityAllowed {
            StatusLine("Accessibility allowed", .good).padding(.top, 8)
        } else {
            Button("Open System Settings…", action: model.allowAccessibility)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 8)
            Text("Turn on kotoba in the list. If it is on already and this step stays open, turn it off and on again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: OnboardingView.textWidth)
        }
    }
}

struct KeyStep: View {
    let model: OnboardingModel

    var body: some View {
        let provider = model.account.title
        StepText("kotoba sends your audio to \(provider), which turns it into text.")
        PriceLine(route: model.route)
            .font(.callout)
        // Hidden once a key is saved, unless the provider refused it: Change… is then the next thing to do, and a second
        // key button would compete with it.
        if !model.keyChecks.isSaved(model.account) || model.keyChecks.status[model.account] == .checked(.invalid) {
            Button("Get a Key at \(provider)…") { model.open(model.account.keysPage) }
                .padding(.top, 4)
        }
        KeyField(account: model.account, keyChecks: model.keyChecks, fieldWidth: 280)
        result
            .font(.callout)
            .frame(minHeight: 34, alignment: .top)
        Button("Use xAI or Azure Instead…", action: model.openSpeechSettings)
            .buttonStyle(.link)
            .font(.callout)
    }

    /// The shared check result after a save here; with none, what `Readiness` knows about a key saved before.
    @ViewBuilder private var result: some View {
        if let status = model.keyChecks.status[model.account] {
            KeyCheckLine(status: status, account: model.account)
        } else if model.readiness.missingSetup?.item == .endpoint {
            StatusLine("Key saved. Add your Azure endpoint to check it.", .neutral)
        } else if model.readiness.missingSetup == nil {
            StatusLine("Key saved", .good)
        }
    }
}

/// Wispr Flow is on this Mac: one click shows what its dictionary would add (the alert Settings > Dictionary shows),
/// and Import adds it. Optional: "Not Now" moves on, and Settings > Dictionary keeps the same button.
struct WisprImportStep: View {
    let model: OnboardingModel

    var body: some View {
        StepText(
            "Add the words and replacements from your Wispr Flow dictionary, so kotoba spells them right "
                + "from the start."
        )
        Group {
            if let added = model.wisprImported {
                StatusLine(Self.importedText(added), .good)
            } else if model.dictionary?.wisprImport?.isReading == true {
                ProgressView().controlSize(.small)
            } else {
                Button("Import from Wispr Flow…", action: model.previewWisprImport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(.top, 8)
        if model.wisprImported == nil {
            Text("You can also do this later in Settings > Dictionary.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    static func importedText(_ added: DictionaryImport) -> String {
        added.isEmpty
            ? "Your dictionary already has every word from Wispr Flow."
            : "Added \(added.countsText)."
    }
}

struct TryItStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let chord = HotkeyChords.shared.handsFree.title
        // Both ways to dictate sit together above the field, so the field's result line below never moves them.
        StepText(
            "Tap \(chord), say \u{201C}Hello from kotoba\u{201D}, then tap \(chord) again.\n"
                + StatusText.holdToDictate(.shared))
        TextField("Try It", text: $model.tryItText, prompt: Text("Your words appear here"), axis: .vertical)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...3)
            .frame(width: 360)
            .focused($isFieldFocused)
            .onAppear { isFieldFocused = true }
        // Always laid out, so the step does not move when the dictation works.
        let works = model.isDone(.tryIt)
        StatusLine("It works.", .good)
            .font(.callout)
            .opacity(works ? 1 : 0)
            .accessibilityHidden(!works)
    }
}

struct DoneStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepText("Open kotoba from the menu bar or the Dock to change your microphone or settings.")
        Form {
            Toggle(
                "Open kotoba when you log in",
                isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
            Toggle("Play a sound when dictation starts and stops", isOn: $model.playsSounds)
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        // A form fills its container; here it is only as tall as its rows.
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: OnboardingView.textWidth)
        // Applied as the step shows (default on), so a problem shows here before Done closes the window.
        .task { model.setOpensAtLogin(model.opensAtLogin) }
        if let problem = model.loginProblem {
            Text(problem.text).font(.callout).foregroundStyle(.secondary)
            Button("Open Login Items…", action: model.openLoginItemsSettings)
        }
        if let step = model.firstMissingStep, let missing = model.readiness.firstMissing {
            HStack {
                StatusLine(missing.problemText, .problem)
                if model.readiness.missingSetup?.item == .endpoint {
                    Button("Add Your Azure Endpoint…", action: model.openSpeechSettings)
                } else {
                    Button(fixTitle(step)) { model.step = step }
                }
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }

    private func fixTitle(_ step: OnboardingStep) -> String {
        switch step {
        case .microphone: "Allow Microphone"
        case .accessibility: "Allow Accessibility"
        default: "Add Your Key"
        }
    }
}
