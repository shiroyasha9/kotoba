import Foundation

/// The first-run steps (docs/research/ui-redesign.md, "Onboarding"). `OnboardingFlow` puts them in order.
public enum OnboardingStep: String, CaseIterable, Sendable, Identifiable {
    case welcome
    /// The microphone and Accessibility, one row each.
    case permissions
    case key
    case tryIt
    /// The Wispr Flow import is a row here when Wispr Flow is on this Mac.
    case done

    public var id: Self { self }

    /// The step to show for `saved`, the raw value stored where the owner closed the window: Welcome when there is
    /// none. 0.4 had seven steps; its microphone and Accessibility steps are `permissions` now, and its Wispr Flow
    /// step resumes at the step after it, Try It. An unknown value starts at Welcome.
    public init(saved: String?) {
        switch saved {
        case "microphone", "accessibility": self = .permissions
        case "wisprImport": self = .tryIt
        default: self = saved.flatMap(Self.init(rawValue:)) ?? .welcome
        }
    }
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
    /// Continue shows dimmed until the step is done: kotoba cannot work without it (both permissions).
    case waitsForStep
    case done
}

/// The order of the onboarding steps, and how the window moves through them. kotoba cannot work without the
/// microphone or Accessibility (the hotkey tap needs it), so the permissions step waits for both grants and never moves
/// on by itself: the owner sees the granted state and clicks Continue (owner, 2026-10-16).
public enum OnboardingFlow {
    public static let steps = OnboardingStep.allCases

    /// The position of `step` from 0, for "Step 2 of 5".
    public static func index(of step: OnboardingStep) -> Int {
        steps.firstIndex(of: step) ?? 0
    }

    public static func next(after step: OnboardingStep) -> OnboardingStep? {
        let next = index(of: step) + 1
        return steps.indices.contains(next) ? steps[next] : nil
    }

    public static func previous(before step: OnboardingStep) -> OnboardingStep? {
        let previous = index(of: step) - 1
        return steps.indices.contains(previous) ? steps[previous] : nil
    }

    /// The Done step offers the Wispr Flow import when Wispr Flow is on this Mac and kotoba's dictionary is open to
    /// import into (it is read at launch, maybe after the window opened).
    public static func offersWisprImport(isWisprInstalled: Bool, isDictionaryOpen: Bool) -> Bool {
        isWisprInstalled && isDictionaryOpen
    }

    /// The step dots' check on `step` while `shown` is on screen: its own requirement is met (`isDone`), or it asks for
    /// nothing kotoba needs (Welcome, and Try It, which the owner may skip) and the owner went past it.
    public static func isChecked(_ step: OnboardingStep, shown: OnboardingStep, isDone: Bool) -> Bool {
        if isDone { return true }
        let isPassed = index(of: step) < index(of: shown)
        return isPassed && (step == .welcome || step == .tryIt)
    }

    /// The footer's forward button on `step`; `isDone` is the step's own requirement (the grants, a key, a dictation).
    public static func footer(on step: OnboardingStep, isDone: Bool) -> OnboardingFooter {
        switch step {
        case .welcome: .getStarted
        case .permissions: isDone ? .continue(.defaultAction) : .waitsForStep
        case .key, .tryIt: .continue(isDone ? .prominent : .plain)
        case .done: .done
        }
    }
}

/// The Done step's "Open at login" switch (owner QA 1, Q5). The switch shows what the system holds after each turn: a
/// change that failed puts it back, as System Settings does. Done applies the choice it shows only when the owner did not
/// turn it: a turn took effect then, and registering again would only fail.
public struct LoginItemChoice: Sendable, Equatable {
    public private(set) var isOn: Bool
    private var isTurnedByOwner = false

    /// `isOn` is the switch's first value: on for a release build until setup is done, else what the system holds.
    public init(isOn: Bool) {
        self.isOn = isOn
    }

    /// The owner turned the switch, and the change was tried; `systemIsOn` is what the system holds now (on, or waiting
    /// for approval).
    public mutating func ownerTurned(systemIsOn: Bool) {
        isTurnedByOwner = true
        isOn = systemIsOn
    }

    /// Done applies `isOn`: the owner did not turn the switch.
    public var isAppliedAtDone: Bool {
        !isTurnedByOwner
    }
}
