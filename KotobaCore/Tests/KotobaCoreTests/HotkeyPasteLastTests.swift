import Testing

@testable import KotobaCore

/// The Paste Last chord: a key with modifiers that pastes the last dictation again once every modifier is up.
extension HotkeyClassifierTests {
    static let controlCommandV = Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV)
    static let controlCommand = KeyInput.modifiersChanged([.leftControl, .leftCommand])
    static let pasteLast = HotkeyDecision(event: .pasteLast)

    static let pasteLastRows: [Row] = [
        Row(
            name: "Paste Last pastes once every modifier is up; its key does not reach the app",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow),
                (down(KeyCode.ansiV, isRepeat: true), .swallow), (up(KeyCode.ansiV), .swallow),
                (.modifiersChanged(.leftCommand), .pass), (none, pasteLast),
            ]
        ),
        Row(
            name: "modifiers up before the key: it pastes, and the key-up still does not reach the app",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow), (none, pasteLast),
                (up(KeyCode.ansiV), .swallow),
            ]
        ),
        Row(
            name: "a second press before the release pastes once",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow), (up(KeyCode.ansiV), .swallow),
                (down(KeyCode.ansiV), .swallow), (up(KeyCode.ansiV), .swallow), (none, pasteLast),
            ]
        ),
        Row(
            name: "another key before the release makes it part of another shortcut",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow), (down(KeyCode.ansiC), .pass),
                (up(KeyCode.ansiV), .swallow), (none, .pass),
            ]
        ),
        Row(
            name: "with another modifier held the key is another app’s shortcut",
            pasteLastChord: controlCommandV,
            steps: [
                (.modifiersChanged([.leftControl, .leftShift, .leftCommand]), .pass), (down(KeyCode.ansiV), .pass),
                (up(KeyCode.ansiV), .pass), (none, .pass),
            ]
        ),
        Row(
            name: "with no Paste Last chord the key reaches the app",
            steps: [(controlCommand, .pass), (down(KeyCode.ansiV), .pass), (up(KeyCode.ansiV), .pass), (none, .pass)]
        ),
        Row(
            name: "a release the tap missed is found at the next key, which reaches the app",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow), (up(KeyCode.ansiV), .swallow),
                (down(0, []), pasteLast),
            ]
        ),
        Row(
            name: "a tap back on with no modifier held pastes",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow),
                (.tapReenabled(modifiers: [], isChordKeyDown: false), pasteLast), (up(KeyCode.ansiV), .swallow),
            ]
        ),
        Row(
            name: "the dictation chord pressed on the way starts a dictation instead",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow),
                (
                    .modifiersChanged([.leftControl, .leftOption, .leftCommand]),
                    HotkeyDecision(event: .chordDown(.tapOrHold))
                ),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "while a shortcut recorder listens, the chord reaches it",
            paused: true,
            pasteLastChord: controlCommandV,
            steps: [(controlCommand, .pass), (down(KeyCode.ansiV), .pass), (up(KeyCode.ansiV), .pass), (none, .pass)]
        ),
        Row(
            name: "a key that starts as plain typing is not swallowed later",
            pasteLastChord: controlCommandV,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiV), .swallow), (none, pasteLast),
                (down(KeyCode.ansiV), .pass), (down(KeyCode.ansiV, isRepeat: true), .pass), (up(KeyCode.ansiV), .pass),
            ]
        ),
    ]
}

/// The Paste Last chord must have a key, must not be another chord, and must not hold a modifier-only chord on the
/// way to its key.
extension ChordTests {
    static let controlCommandV = Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV)

    static let pasteLastRows: [Row] = [
        Row(name: "Paste Last off", problem: nil),
        Row(name: "Paste Last on ⌃⌘V, as Wispr Flow has it", pasteLast: controlCommandV, problem: nil),
        Row(name: "Paste Last with modifiers alone", pasteLast: Chord(modifiers: .function), problem: .needsKey),
        Row(
            name: "Paste Last on the paste kotoba sends",
            pasteLast: Chord(modifiers: .command, keyCode: KeyCode.ansiV), problem: .reserved),
        Row(
            name: "Paste Last with Shift and a key types a capital",
            pasteLast: Chord(modifiers: .shift, keyCode: KeyCode.ansiV), problem: .noModifier),
        Row(
            name: "Paste Last on the dictation key chord",
            handsFree: Chord(modifiers: .option, keyCode: KeyCode.space),
            pasteLast: Chord(modifiers: .option, keyCode: KeyCode.space), problem: .pasteLastSameAs(.handsFree)),
        Row(
            name: "Paste Last on the cleanup key chord with the other Option",
            cleanup: Chord(modifiers: .option, keyCode: KeyCode.space),
            pasteLast: Chord(modifiers: .rightOption, keyCode: KeyCode.space), problem: .pasteLastSameAs(.cleanup)),
        Row(
            name: "Paste Last holds the dictation chord on the way",
            pasteLast: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.ansiV),
            problem: .pasteLastIncludes(.handsFree)),
        Row(
            name: "Paste Last holds the cleanup chord on the way",
            handsFree: Chord(modifiers: .function),
            pasteLast: Chord(modifiers: [.control, .option, .shift, .command], keyCode: KeyCode.ansiV),
            problem: .pasteLastIncludes(.cleanup)),
        Row(
            name: "either-side ⌘ in Paste Last holds a right ⌘ dictation chord",
            handsFree: Chord(modifiers: .rightCommand), pasteLast: controlCommandV,
            problem: .pasteLastIncludes(.handsFree)),
        Row(
            name: "with cleanup off, Paste Last may use the cleanup modifiers",
            handsFree: Chord(modifiers: .function), cleanup: nil,
            pasteLast: Chord(modifiers: [.control, .option, .shift, .command], keyCode: KeyCode.ansiV), problem: nil),
        Row(
            name: "Paste Last next to a dictation key chord with the same modifiers",
            handsFree: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space),
            pasteLast: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.ansiV), problem: nil),
        Row(
            name: "a chord's own problem comes before Paste Last's",
            handsFree: Chord(modifiers: .option), pasteLast: Chord(modifiers: .function),
            problem: .commonModifierAlone),
    ]
}
