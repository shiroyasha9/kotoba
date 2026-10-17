import Testing

@testable import KotobaCore

/// A middle or side mouse button as the Hands-free or Push to talk chord: the button is the chord's key. Its down starts
/// the press and its up ends it, and both are kept from the front app; every other button is a click.
extension HotkeyClassifierTests {
    /// "Mouse Button 4" and "Mouse Button 5", as macOS counts them from 1.
    static let back = 3
    static let forward = 4
    static let mouseFour = Chord(mouseButton: back)

    static func buttonDown(_ button: Int, _ modifiers: ModifierKeys = asHeld) -> KeyInput {
        .otherMouseDown(button: button, modifiers: modifiers)
    }

    static func buttonUp(_ button: Int, _ modifiers: ModifierKeys = asHeld) -> KeyInput {
        .otherMouseUp(button: button, modifiers: modifiers)
    }

    static let mouseRows: [Row] = [
        Row(
            name: "push to talk on a side button: a hold press, its down and up kept from the app",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "hands-free on the middle button does both, as one chord",
            handsFreeChord: Chord(mouseButton: Chord.middleMouseButton),
            steps: [
                (buttonDown(2), HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (buttonUp(2), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "another button with no press is an ordinary click",
            pushToTalkChord: mouseFour,
            steps: [(buttonDown(forward), .pass), (buttonUp(forward), .pass)]
        ),
        Row(
            name: "another button during the press is a click: it interrupts once and reaches the app",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (buttonDown(forward), HotkeyDecision(event: .chordInterrupted)), (buttonUp(forward), .pass),
                (.mouseDown, .pass), (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a left click during the press is a shortcut, as a ⌥-click is",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (.mouseDown, HotkeyDecision(event: .chordInterrupted)),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a key typed during the press is a shortcut",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "the button with a modifier the chord does not have is a plain click",
            pushToTalkChord: mouseFour,
            steps: [
                (leftOption, .pass), (buttonDown(back), .pass), (buttonUp(back), .pass), (none, .pass),
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
            ]
        ),
        Row(
            name: "⌥ with a side button: the button with ⌥ held presses it, and ⌥ may go up first",
            pushToTalkChord: Chord(modifiers: .option, mouseButton: back),
            steps: [
                (buttonDown(back), .pass), (buttonUp(back), .pass), (leftOption, .pass),
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)), (none, .pass),
                (buttonUp(back, []), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "the hands-free chord reached while the button is held follows hands-free",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (chord, HotkeyDecision(event: .gestureChanged(.toggle))), (none, .pass),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a button-up missed while the tap was off is reported when it is back",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (.tapReenabled(modifiers: [], isChordKeyDown: false), HotkeyDecision(event: .chordUp)),
                (buttonUp(back), .pass),
            ]
        ),
        Row(
            name: "a new down of the held button means its up was missed: the press ends and a new one starts",
            pushToTalkChord: mouseFour,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (buttonDown(back), HotkeyDecision(events: [.chordUp, .chordDown(.hold)], isSwallowed: true)),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "while a key chord is held the button is a click",
            handsFreeChord: optionSpace,
            pushToTalkChord: mouseFour,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.toggle), isSwallowed: true)),
                (buttonDown(back), HotkeyDecision(event: .chordInterrupted)), (buttonUp(back), .pass),
                (spaceUp, HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "while the button is held another chord's key is typing: Copy Last and a key chord do not act",
            handsFreeChord: mouseFour,
            pushToTalkChord: optionSpace,
            copyLastChord: controlCommandC,
            steps: [
                (buttonDown(back), HotkeyDecision(event: .chordDown(.toggle), isSwallowed: true)),
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordInterrupted)), (spaceUp, .pass),
                (controlCommand, .pass), (down(KeyCode.ansiC), .pass), (up(KeyCode.ansiC), .pass), (none, .pass),
                (buttonUp(back), HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "while a recorder listens the button reaches the recorder",
            paused: true,
            pushToTalkChord: mouseFour,
            steps: [(buttonDown(back), .pass), (buttonUp(back), .pass)]
        ),
        Row(
            name: "with no mouse chord every button passes",
            steps: [(buttonDown(2), .pass), (buttonUp(2), .pass)]
        ),
    ]

    @Test
    func theTapListensToOtherMouseButtonsOnlyWhileADictationChordIsOne() {
        #expect(HotkeyClassifier(cleanupChord: .defaultCleanup).hasMouseChord == false)
        #expect(HotkeyClassifier(pushToTalkChord: Self.mouseFour, cleanupChord: nil).hasMouseChord)
        #expect(HotkeyClassifier(handsFreeChord: Self.mouseFour, cleanupChord: nil).hasMouseChord)
        #expect(HotkeyClassifier(pushToTalkChord: Self.mouseFour, cleanupChord: nil).hasKeyChord == false)
    }

    @Test
    func theHeldButtonIsTheTriggerToCheckAfterAGap() {
        var keyboard = Keyboard(classifier: HotkeyClassifier(pushToTalkChord: Self.mouseFour, cleanupChord: nil))
        _ = keyboard.press(Self.buttonDown(Self.back))
        #expect(keyboard.classifier.heldTrigger == .mouseButton(Self.back))
        #expect(keyboard.classifier.heldChordKey == nil)
        _ = keyboard.press(Self.buttonUp(Self.back))
        #expect(keyboard.classifier.heldTrigger == nil)
    }
}

/// A side button for Push to talk, through the classifier into the pipeline: the double tap and the minimum length
/// rules apply as for a key.
struct PipelineMouseButtonTests {
    @Test func aDoubleTapOfTheSideButtonRecordsHandsFreeUntilTheNextPress() async {
        let world = FakeWorld(transcript: "side button")
        let pipeline = world.makePipeline()
        var classifier = HotkeyClassifier(pushToTalkChord: HotkeyClassifierTests.mouseFour, cleanupChord: nil)
        let button = HotkeyClassifierTests.back
        func click(_ hold: Duration) async {
            await pipeline.send(classifier.classify(.otherMouseDown(button: button, modifiers: [])))
            world.clock.advance(by: hold)
            await pipeline.send(classifier.classify(.otherMouseUp(button: button, modifiers: [])))
        }

        await click(.milliseconds(100))
        world.clock.advance(by: .milliseconds(150))
        await click(.milliseconds(100))
        world.clock.advance(by: .seconds(3))
        await pipeline.settle()
        #expect(await pipeline.state == .recording(isLong: false))

        await click(.milliseconds(100))
        await pipeline.settle()
        #expect(await world.paster.pasted == ["side button"])
    }

    @Test func aShortSideButtonTapIsDroppedWithNothingKept() async {
        let world = FakeWorld(transcript: "never")
        let pipeline = world.makePipeline()
        var classifier = HotkeyClassifier(pushToTalkChord: HotkeyClassifierTests.mouseFour, cleanupChord: nil)

        await pipeline.send(classifier.classify(.otherMouseDown(button: HotkeyClassifierTests.back, modifiers: [])))
        world.clock.advance(by: .milliseconds(100))
        await pipeline.send(classifier.classify(.otherMouseUp(button: HotkeyClassifierTests.back, modifiers: [])))
        await pipeline.settle()

        #expect(await pipeline.state == .idle)
        #expect(await world.store.records.isEmpty)
        #expect(await world.paster.pasteCount == 0)
    }
}

extension DictationPipeline {
    func send(_ decision: HotkeyDecision) async {
        for event in decision.events {
            await handle(event)
        }
    }
}
