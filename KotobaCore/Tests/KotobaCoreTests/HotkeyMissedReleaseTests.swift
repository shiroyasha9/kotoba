import Testing

@testable import KotobaCore

extension HotkeyClassifierTests {
    /// A missed key-up or modifier release (sleep, secure input, a tap the system turned off) never leaves a chord
    /// down: each key event carries the real modifier flags, and the state follows them.
    static let missedReleaseRows: [Row] = [
        Row(
            name: "a modifier release missed is found at the next key: the press ends and the key reaches the app",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))), (down(0, []), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a modifier press missed is found at the next key",
            steps: [
                (
                    down(0, [.leftControl, .leftOption, .leftCommand]),
                    HotkeyDecision(events: [.chordDown(.tapOrHold), .chordInterrupted])
                )
            ]
        ),
        Row(
            name: "a stuck Option does not swallow the spacebar",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (down(KeyCode.space, []), .pass), (up(KeyCode.space, []), .pass),
                (down(KeyCode.space, []), .pass),
            ]
        ),
        Row(
            name: "a key chord release missed: the next press of the key ends the press and reaches the app",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (none, .pass),
                (down(KeyCode.space, []), HotkeyDecision(event: .chordUp)), (up(KeyCode.space, []), .pass),
                (down(KeyCode.space, []), .pass),
            ]
        ),
        Row(
            name: "a key chord release missed, then the chord again: a new press",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (spaceDown, HotkeyDecision(events: [.chordUp, .chordDown(.tapOrHold)], isSwallowed: true)),
            ]
        ),
        Row(
            name: "other keys reach the app while a key chord release is missing",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (none, .pass),
                (keyA, HotkeyDecision(event: .chordInterrupted)), (keyA, .pass), (up(0), .pass),
            ]
        ),
        Row(
            name: "the tap finds a key chord's key up after a missed key-up: the press ends",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (.chordKeyReleased, HotkeyDecision(event: .chordUp)), (spaceUp, .pass), (keyA, .pass),
            ]
        ),
        Row(
            name: "a key found up with no key chord held changes nothing",
            steps: [(chord, HotkeyDecision(event: .chordDown(.tapOrHold))), (.chordKeyReleased, .pass)]
        ),
        Row(
            name: "macOS marks an arrow with fn: an arrow alone does not press an fn chord",
            handsFreeChord: Chord(modifiers: .function),
            steps: [(down(leftArrow, .function), .pass), (up(leftArrow, .function), .pass)]
        ),
        Row(
            name: "with fn held, an arrow is a shortcut; a missed fn release is found at the next letter",
            handsFreeChord: Chord(modifiers: .function),
            steps: [
                (fnKey, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (down(leftArrow, .function), HotkeyDecision(event: .chordInterrupted)),
                (down(0, []), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a key event with no side bits keeps a right-side press",
            handsFreeChord: Chord(modifiers: .rightOption),
            steps: [
                (rightOption, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (down(0, .leftOption), HotkeyDecision(event: .chordInterrupted)),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
    ]
}
