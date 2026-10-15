import Testing

@testable import KotobaCore

/// Each row: whether the indicator shows recording, the keyboard events in order, and the
/// decision expected for each.
struct HotkeyClassifierTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var recording = false
        var cleanupChord: ModifierKeys? = [.control, .option, .command, .shift]
        let steps: [(KeyInput, HotkeyDecision)]

        var testDescription: String { name }
    }

    /// kVK_Escape
    static let escapeKeyCode: UInt16 = 0x35
    static let escape = KeyInput.keyDown(keyCode: escapeKeyCode)
    static let keyA = KeyInput.keyDown(keyCode: 0)
    static let chord = KeyInput.modifiersChanged(.chord)
    static let none = KeyInput.modifiersChanged([])
    static let hyper = KeyInput.modifiersChanged([.control, .option, .command, .shift])

    static let rows: [Row] = [
        Row(
            name: "the chord goes down and up",
            steps: [
                (.modifiersChanged([.control]), .pass), (.modifiersChanged([.control, .option]), .pass),
                (chord, HotkeyDecision(event: .chordDown)),
                (.modifiersChanged([.control, .option]), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "shift held first: the chord-down also reports the cleanup modifier",
            steps: [
                (.modifiersChanged([.shift]), .pass), (.modifiersChanged([.control, .option, .shift]), .pass),
                (hyper, HotkeyDecision(events: [.chordDown, .cleanupModifier])),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "shift last: the cleanup modifier comes after the chord-down",
            steps: [
                (chord, HotkeyDecision(event: .chordDown)), (hyper, HotkeyDecision(event: .cleanupModifier)),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "the cleanup modifier is reported once per press, even if shift goes up and down",
            steps: [
                (chord, HotkeyDecision(event: .chordDown)), (hyper, HotkeyDecision(event: .cleanupModifier)),
                (chord, .pass), (hyper, .pass), (none, HotkeyDecision(event: .chordUp)),
                (hyper, HotkeyDecision(events: [.chordDown, .cleanupModifier])),
            ]
        ),
        Row(
            name: "with cleanup off, shift with the chord reports nothing more",
            cleanupChord: nil,
            steps: [(hyper, HotkeyDecision(event: .chordDown)), (none, HotkeyDecision(event: .chordUp))]
        ),
        Row(
            name: "a configured cleanup chord replaces the default",
            cleanupChord: [.control, .option, .command, .function],
            steps: [
                (hyper, HotkeyDecision(event: .chordDown)), (none, HotkeyDecision(event: .chordUp)),
                (
                    .modifiersChanged([.control, .option, .command, .function]),
                    HotkeyDecision(events: [.chordDown, .cleanupModifier])
                ),
            ]
        ),
        Row(
            name: "Esc while recording shows cancels and is swallowed",
            recording: true,
            steps: [(escape, HotkeyDecision(event: .escape, isSwallowed: true))]
        ),
        Row(name: "Esc while idle reaches the app", steps: [(escape, .pass)]),
        Row(name: "a key with no chord is ordinary typing", steps: [(keyA, .pass)]),
        Row(
            name: "a key with the chord held interrupts once and reaches the app",
            steps: [
                (chord, HotkeyDecision(event: .chordDown)), (keyA, HotkeyDecision(event: .chordInterrupted)),
                (keyA, .pass), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "Esc with the chord held before recording shows is a shortcut",
            steps: [(chord, HotkeyDecision(event: .chordDown)), (escape, HotkeyDecision(event: .chordInterrupted))]
        ),
        Row(
            name: "Esc with the chord held while recording shows cancels",
            recording: true,
            steps: [
                (chord, HotkeyDecision(event: .chordDown)), (escape, HotkeyDecision(event: .escape, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a new chord press can be interrupted again",
            steps: [
                (chord, HotkeyDecision(event: .chordDown)), (keyA, HotkeyDecision(event: .chordInterrupted)),
                (none, HotkeyDecision(event: .chordUp)), (chord, HotkeyDecision(event: .chordDown)),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
            ]
        ),
        Row(
            name: "a release missed while the tap was off is reported when it is back",
            steps: [
                (chord, HotkeyDecision(event: .chordDown)),
                (.tapReenabled(modifiers: []), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a tap back on with the chord still held reports nothing",
            steps: [(chord, HotkeyDecision(event: .chordDown)), (.tapReenabled(modifiers: .chord), .pass)]
        ),
    ]

    @Test(arguments: rows)
    func classify(_ row: Row) {
        var classifier = HotkeyClassifier(escapeKeyCode: Self.escapeKeyCode, cleanupChord: row.cleanupChord)
        classifier.swallowsEscape = row.recording
        for (index, (input, expected)) in row.steps.enumerated() {
            #expect(classifier.classify(input) == expected, "step \(index)")
        }
    }
}
