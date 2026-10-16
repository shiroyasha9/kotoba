import Testing

@testable import KotobaCore

/// The Copy Last chord: a key with modifiers that puts the last dictation on the clipboard at its press. It posts no
/// key, so it does not wait for the modifiers to go up, as Paste Last does.
extension HotkeyClassifierTests {
    static let controlCommandC = Chord.defaultCopyLast
    static let copyLast = HotkeyDecision(event: .copyLast, isSwallowed: true)

    static let copyLastRows: [Row] = [
        Row(
            name: "Copy Last copies at its press; its key, repeats and key-up do not reach the app",
            copyLastChord: controlCommandC,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiC), copyLast),
                (down(KeyCode.ansiC, isRepeat: true), .swallow), (up(KeyCode.ansiC), .swallow), (none, .pass),
            ]
        ),
        Row(
            name: "each press copies once",
            copyLastChord: controlCommandC,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiC), copyLast), (up(KeyCode.ansiC), .swallow),
                (down(KeyCode.ansiC), copyLast), (up(KeyCode.ansiC), .swallow), (none, .pass),
            ]
        ),
        Row(
            name: "with another modifier held the key is another app’s shortcut",
            copyLastChord: controlCommandC,
            steps: [
                (.modifiersChanged([.leftControl, .leftShift, .leftCommand]), .pass), (down(KeyCode.ansiC), .pass),
                (up(KeyCode.ansiC), .pass), (none, .pass),
            ]
        ),
        Row(
            name: "with no Copy Last chord the key reaches the app",
            steps: [(controlCommand, .pass), (down(KeyCode.ansiC), .pass), (up(KeyCode.ansiC), .pass), (none, .pass)]
        ),
        Row(
            name: "while a shortcut recorder listens, the chord reaches it",
            paused: true,
            copyLastChord: controlCommandC,
            steps: [(controlCommand, .pass), (down(KeyCode.ansiC), .pass), (up(KeyCode.ansiC), .pass), (none, .pass)]
        ),
        Row(
            name: "Copy Last and Paste Last on the same modifiers each do their own",
            pasteLastChord: controlCommandV, copyLastChord: controlCommandC,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiC), copyLast), (up(KeyCode.ansiC), .swallow),
                (down(KeyCode.ansiV), .swallow), (up(KeyCode.ansiV), .swallow), (none, pasteLast),
            ]
        ),
        Row(
            name: "after the chord, the key typed alone reaches the app",
            copyLastChord: controlCommandC,
            steps: [
                (controlCommand, .pass), (down(KeyCode.ansiC), copyLast), (up(KeyCode.ansiC), .swallow),
                (none, .pass), (down(KeyCode.ansiC), .pass), (down(KeyCode.ansiC, isRepeat: true), .pass),
                (up(KeyCode.ansiC), .pass),
            ]
        ),
    ]
}

/// The Copy Last chord follows the Paste Last rules, and must not be the Paste Last chord.
extension ChordTests {
    static let copyLastRows: [Row] = [
        Row(name: "Copy Last on ⌃⌘C with the default chords", copyLast: .defaultCopyLast, problem: nil),
        Row(
            name: "Copy Last next to Paste Last", pasteLast: controlCommandV, copyLast: .defaultCopyLast,
            problem: nil),
        Row(name: "Copy Last with modifiers alone", copyLast: Chord(modifiers: .function), problem: .needsKey),
        Row(
            name: "Copy Last on the system copy",
            copyLast: Chord(modifiers: .command, keyCode: KeyCode.ansiC), problem: .reserved),
        Row(
            name: "Copy Last on the Paste Last chord", pasteLast: controlCommandV, copyLast: controlCommandV,
            problem: .copyLastSameAs(.pasteLast)),
        Row(
            name: "Copy Last on the dictation key chord",
            handsFree: Chord(modifiers: .option, keyCode: KeyCode.space),
            copyLast: Chord(modifiers: .option, keyCode: KeyCode.space), problem: .copyLastSameAs(.handsFree)),
        Row(
            name: "either-side ⌘ in Copy Last holds a right ⌘ dictation chord",
            handsFree: Chord(modifiers: .rightCommand), copyLast: .defaultCopyLast,
            problem: .copyLastIncludes(.handsFree)),
        Row(
            name: "Copy Last holds a push-to-talk ⌃ on the way",
            pushToTalk: Chord(modifiers: .control), copyLast: .defaultCopyLast,
            problem: .copyLastIncludes(.pushToTalk)),
        Row(
            name: "Paste Last’s own problem comes before Copy Last’s",
            pasteLast: Chord(modifiers: .function), copyLast: Chord(modifiers: .function), problem: .needsKey),
    ]
}
