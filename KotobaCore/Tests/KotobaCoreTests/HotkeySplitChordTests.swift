import Testing

@testable import KotobaCore

/// Separate hands-free and push-to-talk chords: each press reports the gesture of the chord held with the most keys.
extension HotkeyClassifierTests {
    static let option = Chord(modifiers: .option)

    static let splitRows: [Row] = [
        Row(
            name: "push to talk on ⌥ alone: a hold press",
            pushToTalkChord: option,
            steps: [(leftOption, HotkeyDecision(event: .chordDown(.hold))), (none, HotkeyDecision(event: .chordUp))]
        ),
        Row(
            name: "the hands-free chord alone: a toggle press",
            pushToTalkChord: option,
            steps: [
                (controlCommand, .pass), (chord, HotkeyDecision(event: .chordDown(.toggle))),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "⌥ first, then ⌃⌘: the press follows hands-free",
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (.modifiersChanged([.leftControl, .leftOption]), .pass),
                (chord, HotkeyDecision(event: .gestureChanged(.toggle))), (leftOption, .pass),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a press never goes back to the chord with fewer keys",
            pushToTalkChord: option,
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.toggle))), (leftOption, .pass), (chord, .pass),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "⌥ with a letter is a shortcut",
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (keyA, HotkeyDecision(event: .chordInterrupted)), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a missed ⌥ press found at a letter: a shortcut",
            pushToTalkChord: option,
            steps: [(down(0, .leftOption), HotkeyDecision(events: [.chordDown(.hold), .chordInterrupted]))]
        ),
        Row(
            name: "a push-to-talk release missed while the tap was off is reported when it is back",
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (.tapReenabled(modifiers: [], isChordKeyDown: false), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "the cleanup chord reached through ⌥ follows cleanup",
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (hyper, HotkeyDecision(events: [.gestureChanged(.tapOrHold), .cleanupModifier])),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "right ⌥ hands-free next to either-side ⌥ push to talk: the side decides",
            handsFreeChord: Chord(modifiers: .rightOption),
            pushToTalkChord: option,
            steps: [
                (rightOption, HotkeyDecision(event: .chordDown(.toggle))), (none, HotkeyDecision(event: .chordUp)),
                (leftOption, HotkeyDecision(event: .chordDown(.hold))), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "push to talk saved as the hands-free chord is one chord, as before",
            pushToTalkChord: .defaultHandsFree,
            steps: [(chord, HotkeyDecision(event: .chordDown(.tapOrHold))), (none, HotkeyDecision(event: .chordUp))]
        ),
        Row(
            name: "a push-to-talk key chord on top of the hands-free chord",
            pushToTalkChord: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space),
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.toggle))),
                (spaceDown, HotkeyDecision(event: .gestureChanged(.hold), isSwallowed: true)),
                (spaceRepeat, .swallow), (spaceUp, .swallow), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a hands-free key chord on top of ⌥ push to talk",
            handsFreeChord: optionSpace,
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (spaceDown, HotkeyDecision(event: .gestureChanged(.toggle), isSwallowed: true)),
                (spaceUp, .swallow), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a push-to-talk key chord release missed: the next press of its key ends the press",
            pushToTalkChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.hold), isSwallowed: true)),
                (none, .pass), (down(KeyCode.space, []), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a ⌥-drag is a shortcut: the click interrupts once and reaches the app",
            pushToTalkChord: option,
            steps: [
                (leftOption, HotkeyDecision(event: .chordDown(.hold))),
                (.mouseDown, HotkeyDecision(event: .chordInterrupted)), (.mouseDown, .pass),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a click during a hands-free press is a shortcut too",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (.mouseDown, HotkeyDecision(event: .chordInterrupted)),
            ]
        ),
        Row(name: "a click with no press is an ordinary click", pushToTalkChord: option, steps: [(.mouseDown, .pass)]),
        Row(
            name: "while a recorder listens, ⌥ push to talk counts for nothing",
            paused: true,
            pushToTalkChord: option,
            steps: [(leftOption, .pass), (none, .pass)]
        ),
    ]

    @Test
    func aPillClickIsAHandsFreeTapWithSplitChords() {
        var keyboard = Keyboard(classifier: HotkeyClassifier(pushToTalkChord: Self.option, cleanupChord: nil))
        #expect(keyboard.classifier.pillClick() == [.chordDown(.toggle), .chordUp])
        #expect(keyboard.press(Self.leftOption) == HotkeyDecision(event: .chordDown(.hold)))
        #expect(keyboard.classifier.pillClick() == [.chordDown(.toggle)])
    }

    @Test
    func aPushToTalkKeyChordNeedsKeyUpEvents() {
        #expect(HotkeyClassifier(cleanupChord: nil).hasKeyChord == false)
        #expect(HotkeyClassifier(pushToTalkChord: Self.optionSpace, cleanupChord: nil).hasKeyChord)
    }
}
