import Testing

@testable import KotobaCore

/// Each row: a dictation and a cleanup chord the owner records, and the reason the pair is refused, if any.
struct ChordTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var dictation = Chord.defaultDictation
        var cleanup: Chord? = .defaultCleanup
        let problem: ChordProblem?

        var testDescription: String { name }
    }

    static let keyK: UInt16 = 0x28

    static let rows: [Row] = [
        Row(name: "the defaults", problem: nil),
        Row(name: "cleanup off", cleanup: nil, problem: nil),
        Row(name: "fn alone", dictation: Chord(modifiers: .function), problem: nil),
        Row(name: "right Option alone", dictation: Chord(modifiers: .rightOption), problem: nil),
        Row(name: "right Command alone", dictation: Chord(modifiers: .rightCommand), problem: nil),
        Row(name: "Option alone, either side", dictation: Chord(modifiers: .option), problem: .commonModifierAlone),
        Row(name: "left Command alone", dictation: Chord(modifiers: .leftCommand), problem: .commonModifierAlone),
        Row(name: "Shift alone", cleanup: Chord(modifiers: .shift), problem: .commonModifierAlone),
        Row(name: "two modifiers without ⌘", dictation: Chord(modifiers: [.control, .option]), problem: nil),
        Row(
            name: "⌘⇧ starts many app shortcuts", dictation: Chord(modifiers: [.shift, .command]), problem: .commandPair
        ),
        Row(name: "⌥⌘", dictation: Chord(modifiers: [.option, .command]), problem: .commandPair),
        Row(name: "⌃⌘", cleanup: Chord(modifiers: [.control, .command]), problem: .commandPair),
        Row(name: "fn⌘", dictation: Chord(modifiers: [.function, .command]), problem: .commandPair),
        Row(
            name: "right ⌘ and right ⇧", dictation: Chord(modifiers: [.rightShift, .rightCommand]), problem: nil),
        Row(name: "⌘⇧ with a key", dictation: Chord(modifiers: [.shift, .command], keyCode: keyK), problem: nil),
        Row(name: "three modifiers with ⌘", dictation: Chord(modifiers: [.control, .option, .command]), problem: nil),
        Row(name: "a key chord", dictation: Chord(modifiers: .option, keyCode: KeyCode.space), problem: nil),
        Row(name: "fn with a key", dictation: Chord(modifiers: .function, keyCode: keyK), problem: nil),
        Row(name: "a key alone", dictation: Chord(modifiers: [], keyCode: keyK), problem: .noModifier),
        Row(
            name: "Shift with a key types a capital", dictation: Chord(modifiers: .shift, keyCode: keyK),
            problem: .noModifier),
        Row(name: "no keys", dictation: Chord(modifiers: []), problem: .noModifier),
        Row(name: "Spotlight", dictation: Chord(modifiers: .command, keyCode: KeyCode.space), problem: .reserved),
        Row(
            name: "Spotlight with the right Command",
            dictation: Chord(modifiers: .rightCommand, keyCode: KeyCode.space),
            problem: .reserved),
        Row(
            name: "the paste kotoba sends", cleanup: Chord(modifiers: .command, keyCode: KeyCode.ansiV),
            problem: .reserved),
        Row(
            name: "a screenshot", dictation: Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansi4),
            problem: .reserved),
        Row(
            name: "⌥⌘Space opens a Finder search",
            dictation: Chord(modifiers: [.option, .command], keyCode: KeyCode.space),
            problem: .reserved),
        Row(
            name: "⌃⌥⌘Space is free",
            dictation: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space), problem: nil),
        Row(name: "Esc as the key", dictation: Chord(modifiers: .option, keyCode: KeyCode.escape), problem: .escape),
        Row(name: "the same chord twice", cleanup: .defaultDictation, problem: .sameAsOther),
        Row(
            name: "the same key chord twice", dictation: Chord(modifiers: .option, keyCode: KeyCode.space),
            cleanup: Chord(modifiers: .option, keyCode: KeyCode.space), problem: .sameAsOther),
        Row(
            name: "the dictation chord holds the whole cleanup chord",
            dictation: .defaultCleanup, cleanup: .defaultDictation, problem: .dictationIncludesCleanup),
        Row(
            name: "right Option dictation holds an either-side Option cleanup",
            dictation: Chord(modifiers: [.control, .rightOption, .command]),
            cleanup: Chord(modifiers: [.control, .option, .command]),
            problem: .dictationIncludesCleanup),
        Row(
            name: "a dictation key chord holds the cleanup modifiers on the way",
            dictation: Chord(modifiers: [.control, .option, .command], keyCode: keyK),
            cleanup: Chord(modifiers: [.control, .option, .command]), problem: .dictationIncludesCleanup),
        Row(
            name: "either-side dictation does not always hold a right-side cleanup",
            dictation: Chord(modifiers: [.control, .option, .command]),
            cleanup: Chord(modifiers: [.control, .rightOption, .command]),
            problem: nil),
        Row(
            name: "a cleanup key chord on top of the dictation chord",
            cleanup: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space), problem: nil),
        Row(
            name: "unrelated chords", dictation: Chord(modifiers: .function), cleanup: Chord(modifiers: .rightOption),
            problem: nil),
    ]

    @Test(arguments: rows)
    func problem(_ row: Row) {
        #expect(Chord.problem(dictation: row.dictation, cleanup: row.cleanup) == row.problem)
    }
}

/// Each row: the keys pressed while the shortcut recorder listens, and what it records.
struct ChordCaptureTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let inputs: [KeyInput]
        let outcome: ChordCapture.Outcome?

        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(
            name: "modifiers are recorded when the last goes up, as the most held at once",
            inputs: [
                .modifiersChanged(.leftControl), .modifiersChanged([.leftControl, .leftOption]),
                .modifiersChanged([.leftControl, .leftOption, .leftCommand]),
                .modifiersChanged([.leftOption, .leftCommand]),
                .modifiersChanged(.leftCommand), .modifiersChanged([]),
            ],
            outcome: .recorded(.defaultDictation)),
        Row(
            name: "the right Option alone keeps its side",
            inputs: [.modifiersChanged(.rightOption), .modifiersChanged([])],
            outcome: .recorded(Chord(modifiers: .rightOption))),
        Row(
            name: "both Options make either side",
            inputs: [.modifiersChanged([.leftOption, .rightOption]), .modifiersChanged([])],
            outcome: .recorded(Chord(modifiers: .option))),
        Row(
            name: "fn alone",
            inputs: [.modifiersChanged(.function), .modifiersChanged([])],
            outcome: .recorded(Chord(modifiers: .function))),
        Row(
            name: "a key is recorded as it goes down, with the modifiers held then",
            inputs: [
                .modifiersChanged(.leftOption),
                .keyDown(keyCode: KeyCode.space, modifiers: .leftOption, isRepeat: false),
            ],
            outcome: .recorded(Chord(modifiers: .option, keyCode: KeyCode.space))),
        Row(
            name: "Esc alone cancels", inputs: [.keyDown(keyCode: KeyCode.escape, modifiers: [], isRepeat: false)],
            outcome: .cancelled),
        Row(
            name: "Esc with a modifier is recorded, so the rules can refuse it",
            inputs: [
                .modifiersChanged(.leftOption),
                .keyDown(keyCode: KeyCode.escape, modifiers: .leftOption, isRepeat: false),
            ],
            outcome: .recorded(Chord(modifiers: .option, keyCode: KeyCode.escape))),
        Row(name: "modifiers still held record nothing yet", inputs: [.modifiersChanged(.leftOption)], outcome: nil),
    ]

    @Test(arguments: rows)
    func capture(_ row: Row) {
        var capture = ChordCapture()
        var outcome: ChordCapture.Outcome?
        for input in row.inputs {
            outcome = capture.handle(input) ?? outcome
        }
        #expect(outcome == row.outcome)
    }
}

extension ChordTests {
    @Test(arguments: [
        (Chord(modifiers: [.control, .option]), true), (Chord(modifiers: [.rightShift, .rightCommand]), true),
        (Chord.defaultDictation, false), (Chord(modifiers: .function), false),
        (Chord(modifiers: [.control, .option], keyCode: KeyCode.space), false),
    ])
    func twoModifiersAloneOpenTheMicBriefly(_ chord: Chord, _ opens: Bool) {
        #expect(chord.opensMicBriefly == opens)
    }
}
