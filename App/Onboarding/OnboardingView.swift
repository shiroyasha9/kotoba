import KotobaCore
import KotobaProviders
import SwiftUI

/// One step at a time, built from the page parts (`PageForm`, `PageRow`, `SymbolTile`): a bold, left-aligned title and
/// one plain sentence (macOS 26 onboarding, WWDC25 356), the step's cards, and the step dots with Back and Continue at
/// the bottom. A grant never moves the window on: the step shows it and the owner clicks Continue (owner, 2026-10-16).
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    /// After Done: closes the window and opens the app on Home.
    let close: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PageForm {
                content
            }
            footer
                .padding([.horizontal, .bottom], PageMetrics.formInset)
        }
        // The window does not resize: its rows wrap to its width, as they would in any window this wide. Without it the
        // form asks for its rows' one-line width.
        .frame(width: PageMetrics.onboardingWindowSize.width)
        .task { await model.checkWispr() }
        .wisprImportAlert(model.dictionary, imported: model.wisprImportAnswered)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome: WelcomeStep()
        case .permissions: PermissionsStep(model: model)
        case .key: KeyStep(model: model)
        case .tryIt: TryItStep(model: model)
        case .done: DoneStep(model: model)
        }
    }

    private var footer: some View {
        HStack {
            StepDots(model: model)
            Spacer()
            if OnboardingFlow.previous(before: model.step) != nil {
                Button("Back", action: model.goBack)
            }
            switch OnboardingFlow.footer(on: model.step, isDone: model.isDone(model.step)) {
            case .getStarted:
                Button("Get Started", action: model.goForward).keyboardShortcut(.defaultAction)
            case .continue(.plain):
                Button("Continue", action: model.goForward)
            case .continue(let emphasis):
                // Prominent once the step is done; Return presses it unless the step's text field takes Return.
                Button("Continue", action: model.goForward)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(emphasis == .defaultAction ? .defaultAction : nil)
            case .waitsForStep:
                // Until both grants arrive, the rows' Allow buttons are the way on; Continue shows where it leads.
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

/// A step's title and its one sentence, bold and left-aligned as macOS 26's onboarding and alerts (WWDC25 356), over
/// the step's first card; Welcome puts kotoba's icon above it. The first section's header, so it starts where the
/// cards' text starts.
struct StepHeading<Icon: View>: View {
    let title: String
    /// A `Text`, so the UI-text lint sees its words wherever the formatter puts the argument (`Text(` is a builder).
    let text: Text
    @ViewBuilder var icon: Icon

    var body: some View {
        VStack(alignment: .leading) {
            icon
            Text(title)
                .font(.largeTitle)
                .bold()
                .foregroundStyle(.primary)
            text
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension StepHeading where Icon == EmptyView {
    init(title: String, text: Text) {
        self.init(title: title, text: text) { EmptyView() }
    }
}

/// One dot per step: done steps show a checkmark, the shown step is in the accent colour, done or not, so the owner
/// always sees where they are. Custom: macOS has no page indicator control (UIPageControl is iOS only).
private struct StepDots: View {
    let model: OnboardingModel

    var body: some View {
        HStack {
            ForEach(OnboardingFlow.steps) { step in
                let isShown = step == model.step
                let isDone = model.isDone(step)
                Image(systemName: Self.symbol(isShown: isShown, isDone: isDone))
                    .foregroundStyle(Self.style(isShown: isShown, isDone: isDone))
                    .font(.caption2)
                    .imageScale(.small)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(OnboardingFlow.index(of: model.step) + 1) of \(OnboardingFlow.steps.count)")
    }

    private static func symbol(isShown: Bool, isDone: Bool) -> String {
        if isDone { return "checkmark.circle.fill" }
        return isShown ? "circle.fill" : "circle"
    }

    private static func style(isShown: Bool, isDone: Bool) -> AnyShapeStyle {
        if isShown { return AnyShapeStyle(.tint) }
        return isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary)
    }
}
