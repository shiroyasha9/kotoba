import Testing

@testable import KotobaCore

/// The Polish Last chord: a key with modifiers that polishes the last dictation once every modifier is up, as Paste
/// Last does, since Polish posts ⌘V.
extension HotkeyClassifierTests {
    static let optionOne = Chord(modifiers: .option, keyCode: KeyCode.ansi1)
    static let polishLast = HotkeyDecision(event: .polishLast)

    static let polishLastRows: [Row] = [
        Row(
            name: "Polish Last polishes once every modifier is up; its key does not reach the app",
            polishLastChord: optionOne,
            steps: [
                (leftOption, .pass), (down(KeyCode.ansi1), .swallow), (down(KeyCode.ansi1, isRepeat: true), .swallow),
                (up(KeyCode.ansi1), .swallow), (none, polishLast),
            ]
        ),
        Row(
            name: "another key before the release makes Polish Last part of another shortcut",
            polishLastChord: optionOne,
            steps: [
                (leftOption, .pass), (down(KeyCode.ansi1), .swallow), (down(0), .pass), (up(KeyCode.ansi1), .swallow),
                (none, .pass),
            ]
        ),
        Row(
            name: "with no Polish Last chord the key reaches the app",
            steps: [(leftOption, .pass), (down(KeyCode.ansi1), .pass), (up(KeyCode.ansi1), .pass), (none, .pass)]
        ),
        Row(
            name: "Paste Last pressed after Polish Last in one hold: the last press counts",
            pasteLastChord: Chord(modifiers: .option, keyCode: KeyCode.ansiV), polishLastChord: optionOne,
            steps: [
                (leftOption, .pass), (down(KeyCode.ansi1), .swallow), (up(KeyCode.ansi1), .swallow),
                (down(KeyCode.ansiV), .swallow), (up(KeyCode.ansiV), .swallow), (none, pasteLast),
            ]
        ),
        Row(
            name: "while a recorder listens, Polish Last sends nothing",
            paused: true, polishLastChord: optionOne,
            steps: [(leftOption, .pass), (down(KeyCode.ansi1), .pass), (up(KeyCode.ansi1), .pass), (none, .pass)]
        ),
    ]
}

/// The Polish Last chord follows the Paste Last rules, and must not be the Paste Last or Copy Last chord.
extension ChordTests {
    static let optionOne = Chord(modifiers: .option, keyCode: KeyCode.ansi1)

    static let polishLastRows: [Row] = [
        Row(name: "Polish Last on ⌥1 with the default chords", polishLast: optionOne, problem: nil),
        Row(
            name: "Polish Last with modifiers alone", polishLast: Chord(modifiers: [.control, .option]),
            problem: .needsKey),
        Row(
            name: "Polish Last on the Copy Last chord", copyLast: .defaultCopyLast, polishLast: .defaultCopyLast,
            problem: .polishLastSameAs(.copyLast)),
        Row(
            name: "Polish Last on the Paste Last chord", pasteLast: controlCommandV, polishLast: controlCommandV,
            problem: .polishLastSameAs(.pasteLast)),
        Row(
            name: "Polish Last holds a push-to-talk ⌥ on the way", pushToTalk: Chord(modifiers: .option),
            polishLast: optionOne, problem: .polishLastIncludes(.pushToTalk)),
        Row(
            name: "the second suggestion fits a push-to-talk ⌥", pushToTalk: Chord(modifiers: .option),
            polishLast: Chord.polishLastSuggestions[1], problem: nil),
        Row(
            name: "Polish Last on the system paste",
            polishLast: Chord(modifiers: .command, keyCode: KeyCode.ansiV), problem: .reserved),
    ]
}
