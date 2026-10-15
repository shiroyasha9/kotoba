import KotobaProviders
import SwiftUI

// The six onboarding steps and the small views they share. `OnboardingView` shows one at a time.

/// A line with a symbol in its status color: allowed, off, or a hint.
private struct StatusLine: View {
    enum Kind { case good, problem, neutral }

    let text: String
    let kind: Kind

    init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .good: StatusLabel(text, systemImage: "checkmark.circle.fill", color: .green)
        case .problem: StatusLabel(text, systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .neutral: StatusLabel(text, systemImage: "info.circle", color: .secondary)
        }
    }
}

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

struct WelcomeStep: View {
    var body: some View {
        // Keys are named in words once, here (CODING_STANDARDS, user-facing text 4).
        StepText(
            "Tap \(StatusText.dictationChordNamed), speak, and tap again. "
                + "kotoba types what you said where your cursor is, in about a second."
        )
        LabeledContent("Shortcut") {
            ChordRecorder(chords: .shared, role: .dictation)
        }
        .fixedSize()
        .padding(.top, 4)
        Label(
            "No account. Your audio goes only to the speech service you choose, with your own key.", systemImage: "lock"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: OnboardingView.textWidth)
        .padding(.top, 8)
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
            "kotoba needs Accessibility to notice \(StatusText.dictationChord) in every app and to paste your text. "
                + "kotoba does not read your screen or your typing."
        )
        if model.readiness.isAccessibilityAllowed {
            StatusLine("Accessibility allowed", .good).padding(.top, 8)
        } else {
            Button("Open Accessibility Settings", action: model.allowAccessibility)
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
    @State private var draft = ""

    var body: some View {
        let provider = model.account.title
        StepText("kotoba sends your audio to \(provider), which turns it into text.")
        PriceLine(route: model.route)
            .font(.callout)
        Button("Get a Key at \(provider)…") { model.open(model.account.keysPage) }
            .padding(.top, 4)
        HStack {
            SecureField("Key", text: $draft, prompt: Text("Paste your \(provider) key"))
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(save)
            Button("Save", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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

    private func save() {
        let key = draft
        draft = ""
        Task { await model.saveKey(key) }
    }
}

struct TryItStep: View {
    @Bindable var model: OnboardingModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let chord = StatusText.dictationChord
        StepText("Tap \(chord), say \u{201C}Hello from kotoba\u{201D}, then tap \(chord) again.")
        TextField("Try It", text: $model.tryItText, prompt: Text("Your words appear here"), axis: .vertical)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...3)
            .frame(width: 360)
            .focused($isFieldFocused)
            .onAppear { isFieldFocused = true }
        if model.tryItText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Or hold \(StatusText.dictationChord) while you speak, and let go.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            StatusLine("It works.", .good).font(.callout)
        }
    }
}

struct DoneStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepText("kotoba lives in the menu bar. Click the waveform icon to change your microphone or open Settings.")
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
        if let step = model.firstMissingStep {
            HStack {
                StatusLine(missingText(step), .problem)
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

    /// What the missing step leaves undone, in the owner's terms.
    private func missingText(_ step: OnboardingStep) -> String {
        switch step {
        case .microphone: "kotoba cannot use the microphone yet."
        case .accessibility: "kotoba cannot hear \(StatusText.dictationChord) or paste yet."
        default:
            model.readiness.missingSetup?.item == .endpoint
                ? "kotoba has no Azure endpoint yet." : "kotoba has no \(model.account.title) key yet."
        }
    }

    private func fixTitle(_ step: OnboardingStep) -> String {
        switch step {
        case .microphone: "Allow the Microphone"
        case .accessibility: "Allow Accessibility"
        default: "Add Your Key"
        }
    }
}
