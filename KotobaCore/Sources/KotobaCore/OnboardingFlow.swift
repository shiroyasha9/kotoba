import Foundation

/// The first-run steps (docs/research/ux-polish.md, section 3). `OnboardingFlow` puts them in order.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    case welcome
    case microphone
    case accessibility
    case key
    /// Only when Wispr Flow is on this Mac (`OnboardingFlow.init`).
    case wisprImport
    case tryIt
    case done

    public var id: Self { self }
}

/// What the footer offers on a step, next to Back.
public enum OnboardingFooter: Equatable, Sendable {
    /// How Continue stands out: prominent once the step is done; also Return's button unless the step's text field
    /// takes Return.
    public enum Emphasis: Equatable, Sendable {
        case plain
        case prominent
        case defaultAction
    }

    case getStarted
    case `continue`(Emphasis)
    /// The step is optional and not done: the footer moves on without it.
    case notNow
    /// Continue shows dimmed until the step is done: kotoba cannot work without it (a permission).
    case waitsForStep
    case done
}

/// The order of the onboarding steps, and how the window moves through them. kotoba cannot work without the
/// microphone or Accessibility (the hotkey tap needs it), so those steps wait for their grant and never move on by
/// themselves: the owner sees the granted state and clicks Continue (owner, 2026-10-16).
public struct OnboardingFlow: Equatable, Sendable {
    public let steps: [OnboardingStep]

    /// The Wispr Flow step shows when Wispr Flow is on this Mac and kotoba's dictionary is open to import into.
    public init(isWisprInstalled: Bool, isDictionaryOpen: Bool) {
        let offersWisprImport = isWisprInstalled && isDictionaryOpen
        steps = OnboardingStep.allCases.filter { $0 != .wisprImport || offersWisprImport }
    }

    /// The position of `step` from 0, for "Step 2 of 7"; a step the flow lacks counts as the first.
    public func index(of step: OnboardingStep) -> Int {
        steps.firstIndex(of: step) ?? 0
    }

    public func next(after step: OnboardingStep) -> OnboardingStep? {
        steps.firstIndex(of: step).flatMap { steps.indices.contains($0 + 1) ? steps[$0 + 1] : nil }
    }

    public func previous(before step: OnboardingStep) -> OnboardingStep? {
        steps.firstIndex(of: step).flatMap { $0 > 0 ? steps[$0 - 1] : nil }
    }

    /// The step to show for `saved` (where the owner closed the window): itself when the flow has it, else the step
    /// after its place (the Wispr Flow step after Wispr Flow was removed), else Welcome.
    public func resuming(_ saved: OnboardingStep?) -> OnboardingStep {
        guard let saved else { return .welcome }
        if steps.contains(saved) { return saved }
        let order = OnboardingStep.allCases
        let place = order.firstIndex(of: saved) ?? 0
        return steps.first { (order.firstIndex(of: $0) ?? 0) > place } ?? .welcome
    }

    /// The footer's forward button on `step`; `isDone` is the step's own requirement (a grant, an import).
    public static func footer(on step: OnboardingStep, isDone: Bool) -> OnboardingFooter {
        switch step {
        case .welcome: .getStarted
        case .microphone, .accessibility: isDone ? .continue(.defaultAction) : .waitsForStep
        case .wisprImport: isDone ? .continue(.defaultAction) : .notNow
        case .key, .tryIt: .continue(isDone ? .prominent : .plain)
        case .done: .done
        }
    }
}
