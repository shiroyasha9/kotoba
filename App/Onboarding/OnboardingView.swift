import KotobaProviders
import SwiftUI

/// One step at a time: a symbol, a title, one or two plain sentences and the step's own control, with the step
/// dots and Back/Continue at the bottom.
struct OnboardingView: View {
    /// A readable line length in the window: every step's text and boxes share it.
    static let textWidth: CGFloat = 420

    @Bindable var model: OnboardingModel
    /// Closes the window after Done.
    let close: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.tint)
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
        .task(id: model.isGrantNew) { await moveOnAfterGrant() }
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .microphone: MicrophoneStep(model: model)
        case .accessibility: AccessibilityStep(model: model)
        case .key: KeyStep(model: model)
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
        case .tryIt: "Try It"
        case .done: model.readiness.isComplete ? "You\u{2019}re Ready" : "Almost Ready"
        }
    }

    private var footer: some View {
        HStack {
            StepDots(model: model)
            Spacer()
            if model.step.previous != nil {
                Button("Back", action: model.goBack)
            }
            switch model.step {
            case .welcome:
                Button("Get Started", action: model.goForward).keyboardShortcut(.defaultAction)
            case .done:
                Button("Done") {
                    model.finish()
                    close()
                }
                .keyboardShortcut(.defaultAction)
            case .key, .tryIt:
                // No default button here: Return belongs to the text field.
                Button("Continue", action: model.goForward)
            case .microphone, .accessibility:
                // Until the grant arrives, the step's own button is the default one; Return never skips it.
                if model.isDone(model.step) {
                    Button("Continue", action: model.goForward).keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for Now", action: model.goForward)
                }
            }
        }
        .controlSize(.large)
    }

    /// A grant that arrives while its step shows moves the window on by itself, after the checkmark showed for a
    /// moment. The app refreshes `Readiness` every second while a kotoba window is open (System Settings sends no
    /// event); this view only watches it.
    private func moveOnAfterGrant() async {
        guard model.isGrantNew else { return }
        let step = model.step
        do {
            try await Task.sleep(for: .seconds(0.8))
        } catch {
            return
        }
        if model.step == step { model.goForward() }
    }
}

/// One dot per step: done steps show a checkmark, the shown step is filled. Custom: macOS has no page indicator
/// control (UIPageControl is iOS only).
private struct StepDots: View {
    let model: OnboardingModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases) { step in
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
        .accessibilityLabel("Step \(model.step.index + 1) of \(OnboardingStep.allCases.count)")
    }
}
