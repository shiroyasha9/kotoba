import Testing

@testable import KotobaCore

/// The onboarding step order, a step saved by an older build, the Wispr Flow offer, and the footer's forward button on
/// each step.
struct OnboardingFlowTests {
    @Test func theStepsRunInOrder() {
        #expect(OnboardingFlow.steps == [.welcome, .permissions, .key, .tryIt, .done])
        #expect(OnboardingFlow.next(after: .key) == .tryIt)
        #expect(OnboardingFlow.previous(before: .tryIt) == .key)
        #expect(OnboardingFlow.index(of: .done) == 4)
    }

    @Test func theFirstAndLastStepsHaveNoNeighbourOutside() {
        #expect(OnboardingFlow.previous(before: .welcome) == nil)
        #expect(OnboardingFlow.next(after: .done) == nil)
    }

    @Test func aSavedStepResumesWhereTheOwnerClosedTheWindow() {
        #expect(OnboardingStep(saved: nil) == .welcome)
        #expect(OnboardingStep(saved: "key") == .key)
        #expect(OnboardingStep(saved: "permissions") == .permissions)
    }

    /// 0.4 had seven steps: the microphone and Accessibility are one step now, and the Wispr Flow import is a row on
    /// Done, so a window closed on its step resumes at the step that came after it.
    @Test(arguments: [
        ("microphone", OnboardingStep.permissions), ("accessibility", .permissions), ("wisprImport", .tryIt),
    ])
    func aStepSavedByAnOlderBuildResumesAtItsPlace(saved: String, step: OnboardingStep) {
        #expect(OnboardingStep(saved: saved) == step)
    }

    @Test func anUnknownSavedStepStartsAtWelcome() {
        #expect(OnboardingStep(saved: "somethingElse") == .welcome)
    }

    @Test func doneOffersTheWisprImportWhenWisprFlowIsInstalled() {
        #expect(OnboardingFlow.offersWisprImport(isWisprInstalled: true, isDictionaryOpen: true))
        #expect(!OnboardingFlow.offersWisprImport(isWisprInstalled: false, isDictionaryOpen: true))
    }

    /// The dictionary is not open yet (it is read at launch), or did not open: there is nothing to import into.
    @Test func theWisprImportNeedsAnOpenDictionary() {
        #expect(!OnboardingFlow.offersWisprImport(isWisprInstalled: true, isDictionaryOpen: false))
    }

    /// Welcome takes Wispr Flow's shortcuts once, when it shows during the first setup; never again after (the owner
    /// may have changed them), and never for a Mac set up before.
    @Test func welcomeTakesWisprShortcutsOnceBeforeSetupIsDone() {
        #expect(OnboardingFlow.takesWisprShortcuts(on: .welcome, hasTaken: false, isComplete: false))
        #expect(!OnboardingFlow.takesWisprShortcuts(on: .welcome, hasTaken: true, isComplete: false))
        #expect(!OnboardingFlow.takesWisprShortcuts(on: .welcome, hasTaken: false, isComplete: true))
        #expect(!OnboardingFlow.takesWisprShortcuts(on: .permissions, hasTaken: false, isComplete: false))
    }

    /// kotoba cannot work without the microphone or Accessibility: no Skip, and no Continue before both grants.
    @Test func thePermissionsStepWaitsForBothGrants() {
        #expect(OnboardingFlow.footer(on: .permissions, isDone: false) == .waitsForStep)
        #expect(OnboardingFlow.footer(on: .permissions, isDone: true) == .continue(.defaultAction))
    }

    /// Return belongs to the text field on the key and Try It steps; Continue stands out once the step is done.
    @Test(arguments: [OnboardingStep.key, .tryIt])
    func aStepWithATextFieldHasNoDefaultContinue(step: OnboardingStep) {
        #expect(OnboardingFlow.footer(on: step, isDone: false) == .continue(.plain))
        #expect(OnboardingFlow.footer(on: step, isDone: true) == .continue(.prominent))
    }

    /// A step's dot checks when its requirement is met, or, for a step with nothing to do (Welcome) or one the owner
    /// may skip (Try It), once the owner went past it. A key the owner skipped stays open: Ready asks for it.
    @Test func aDotChecksWhenItsStepIsDoneOrPassed() {
        #expect(OnboardingFlow.isChecked(.welcome, shown: .permissions, isDone: false))
        #expect(!OnboardingFlow.isChecked(.welcome, shown: .welcome, isDone: false))
        #expect(OnboardingFlow.isChecked(.tryIt, shown: .done, isDone: false))
        #expect(!OnboardingFlow.isChecked(.tryIt, shown: .key, isDone: false))
        #expect(!OnboardingFlow.isChecked(.key, shown: .done, isDone: false))
        #expect(OnboardingFlow.isChecked(.key, shown: .welcome, isDone: true))
        #expect(!OnboardingFlow.isChecked(.done, shown: .done, isDone: false))
    }

    @Test func welcomeStartsAndDoneFinishes() {
        #expect(OnboardingFlow.footer(on: .welcome, isDone: false) == .getStarted)
        #expect(OnboardingFlow.footer(on: .done, isDone: true) == .done)
    }
}
