import Testing

@testable import KotobaCore

/// The onboarding step order, the Wispr Flow offer, and the footer's forward button on each step.
struct OnboardingFlowTests {
    @Test func theStepsRunInOrderWithoutWisprFlow() {
        let flow = OnboardingFlow(isWisprInstalled: false, isDictionaryOpen: true)

        #expect(flow.steps == [.welcome, .microphone, .accessibility, .key, .tryIt, .done])
        #expect(flow.next(after: .key) == .tryIt)
        #expect(flow.previous(before: .tryIt) == .key)
    }

    @Test func wisprFlowAddsItsStepAfterTheKey() {
        let flow = OnboardingFlow(isWisprInstalled: true, isDictionaryOpen: true)

        #expect(flow.steps == [.welcome, .microphone, .accessibility, .key, .wisprImport, .tryIt, .done])
        #expect(flow.next(after: .key) == .wisprImport)
        #expect(flow.previous(before: .tryIt) == .wisprImport)
        #expect(flow.index(of: .done) == 6)
    }

    @Test func theFirstAndLastStepsHaveNoNeighbourOutside() {
        let flow = OnboardingFlow(isWisprInstalled: false, isDictionaryOpen: true)

        #expect(flow.previous(before: .welcome) == nil)
        #expect(flow.next(after: .done) == nil)
    }

    /// The dictionary is not open yet (it is read at launch), or did not open: there is nothing to import into.
    @Test func theWisprStepNeedsAnOpenDictionary() {
        #expect(!OnboardingFlow(isWisprInstalled: true, isDictionaryOpen: false).steps.contains(.wisprImport))
    }

    @Test func aSavedStepResumesWhereTheOwnerClosedTheWindow() {
        let flow = OnboardingFlow(isWisprInstalled: true, isDictionaryOpen: true)

        #expect(flow.resuming(nil) == .welcome)
        #expect(flow.resuming(.key) == .key)
        #expect(flow.resuming(.wisprImport) == .wisprImport)
    }

    /// The owner closed the window on the Wispr Flow step, then removed Wispr Flow.
    @Test func aSavedStepTheFlowLacksResumesAtTheNextStep() {
        #expect(OnboardingFlow(isWisprInstalled: false, isDictionaryOpen: true).resuming(.wisprImport) == .tryIt)
    }

    /// kotoba cannot work without the microphone or Accessibility: no Skip, and no Continue before the grant.
    @Test(arguments: [OnboardingStep.microphone, .accessibility])
    func aPermissionStepWaitsForItsGrant(step: OnboardingStep) {
        #expect(OnboardingFlow.footer(on: step, isDone: false) == .waitsForStep)
        #expect(OnboardingFlow.footer(on: step, isDone: true) == .continue(isDefault: true))
    }

    @Test func theWisprStepIsOptional() {
        #expect(OnboardingFlow.footer(on: .wisprImport, isDone: false) == .notNow)
        #expect(OnboardingFlow.footer(on: .wisprImport, isDone: true) == .continue(isDefault: true))
    }

    /// Return belongs to the text field on the key and Try It steps.
    @Test(arguments: [OnboardingStep.key, .tryIt])
    func aStepWithATextFieldHasNoDefaultContinue(step: OnboardingStep) {
        #expect(OnboardingFlow.footer(on: step, isDone: false) == .continue(isDefault: false))
        #expect(OnboardingFlow.footer(on: step, isDone: true) == .continue(isDefault: false))
    }

    @Test func welcomeStartsAndDoneFinishes() {
        #expect(OnboardingFlow.footer(on: .welcome, isDone: false) == .getStarted)
        #expect(OnboardingFlow.footer(on: .done, isDone: true) == .done)
    }
}
