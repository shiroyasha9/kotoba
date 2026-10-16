import KotobaCore
import KotobaProviders
import SwiftUI

/// One step at a time: a symbol (kotoba's icon on Welcome), a title, one or two plain sentences and the step's own
/// control, with the step dots and Back/Continue at the bottom. A grant never moves the window on: the step shows it
/// and the owner clicks Continue (owner, 2026-10-16).
struct OnboardingView: View {
    /// A readable line length in the window: every step's text and boxes share it.
    static let textWidth: CGFloat = 420

    @Bindable var model: OnboardingModel
    /// Closes the window after Done.
    let close: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                icon
                Text(title)
                    .font(.title)
                    .fontWeight(.semibold)
                content
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 480, minHeight: 360)
        .task { await model.checkWispr() }
        .wisprImportAlert(model.dictionary, imported: model.wisprImportAnswered)
    }

    @ViewBuilder private var icon: some View {
        if model.step == .welcome {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.tint)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .microphone: MicrophoneStep(model: model)
        case .accessibility: AccessibilityStep(model: model)
        case .key: KeyStep(model: model)
        case .wisprImport: WisprImportStep(model: model)
        case .tryIt: TryItStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private var symbol: String {
        switch model.step {
        case .welcome: "waveform"
        case .microphone: "mic"
        case .accessibility: "accessibility"
        case .key: "key"
        case .wisprImport: "character.book.closed"
        case .tryIt: "text.cursor"
        case .done: model.readiness.isComplete ? "checkmark.circle" : "exclamationmark.circle"
        }
    }

    private var title: String {
        switch model.step {
        case .welcome: "Talk Instead of Type"
        case .microphone: "Allow the Microphone"
        case .accessibility: "Allow Accessibility"
        case .key: "Connect a Speech Service"
        case .wisprImport: "Bring Your Words from Wispr Flow"
        case .tryIt: "Try It"
        case .done: model.readiness.isComplete ? "You\u{2019}re Ready" : "Almost Ready"
        }
    }

    private var footer: some View {
        HStack {
            StepDots(model: model)
            Spacer()
            if model.flow.previous(before: model.step) != nil {
                Button("Back", action: model.goBack)
            }
            switch OnboardingFlow.footer(on: model.step, isDone: model.isDone(model.step)) {
            case .getStarted:
                Button("Get Started", action: model.goForward).keyboardShortcut(.defaultAction)
            case .continue(let isDefault):
                // Not the default where Return belongs to the step's text field.
                Button("Continue", action: model.goForward).keyboardShortcut(isDefault ? .defaultAction : nil)
            case .notNow:
                Button("Not Now", action: model.goForward)
            case .waitsForStep:
                // Until the grant arrives, the step's own button is the default one; Continue shows where it leads.
                Button("Continue", action: model.goForward).disabled(true)
            case .done:
                Button("Done") {
                    model.finish()
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlSize(.large)
    }
}

/// One dot per step: done steps show a checkmark, the shown step is filled. Custom: macOS has no page indicator
/// control (UIPageControl is iOS only).
private struct StepDots: View {
    let model: OnboardingModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.flow.steps) { step in
                Group {
                    if model.isDone(step) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Image(systemName: step == model.step ? "circle.fill" : "circle")
                            .foregroundStyle(step == model.step ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    }
                }
                .font(.caption2)
                .imageScale(.small)
                .opacity(step == model.step || model.isDone(step) ? 1 : 0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(model.flow.index(of: model.step) + 1) of \(model.flow.steps.count)")
    }
}
