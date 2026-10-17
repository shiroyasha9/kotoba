import Testing

@testable import KotobaCore

/// Each row: a hands-free, a push-to-talk, a cleanup, a Paste Last and a Copy Last chord the owner records, and the reason they are refused, if any.
struct ChordTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var handsFree = Chord.defaultHandsFree
        var pushToTalk: Chord?
        var cleanup: Chord? = .defaultCleanup
        var pasteLast: Chord?
        var copyLast: Chord?
        var polishLast: Chord?
        let problem: ChordProblem?

        var testDescription: String { name }
    }

    static let keyK: UInt16 = 0x28

    static let rows: [Row] = [
        Row(name: "the defaults", problem: nil),
        Row(name: "cleanup off", cleanup: nil, problem: nil),
        Row(name: "fn alone", handsFree: Chord(modifiers: .function), problem: nil),
        Row(name: "right Option alone", handsFree: Chord(modifiers: .rightOption), problem: nil),
        Row(name: "right Command alone", handsFree: Chord(modifiers: .rightCommand), problem: nil),
        Row(name: "Option alone, either side", handsFree: Chord(modifiers: .option), problem: .commonModifierAlone),
        Row(name: "left Command alone", handsFree: Chord(modifiers: .leftCommand), problem: .commonModifierAlone),
        Row(name: "Shift alone", cleanup: Chord(modifiers: .shift), problem: .commonModifierAlone),
        Row(name: "two modifiers without ⌘", handsFree: Chord(modifiers: [.control, .option]), problem: nil),
        Row(
            name: "⌘⇧ starts many app shortcuts", handsFree: Chord(modifiers: [.shift, .command]), problem: .commandPair
        ),
        Row(name: "⌥⌘", handsFree: Chord(modifiers: [.option, .command]), problem: .commandPair),
        Row(name: "⌃⌘", cleanup: Chord(modifiers: [.control, .command]), problem: .commandPair),
        Row(name: "fn⌘", handsFree: Chord(modifiers: [.function, .command]), problem: .commandPair),
        Row(
            name: "right ⌘ and right ⇧", handsFree: Chord(modifiers: [.rightShift, .rightCommand]), problem: nil),
        Row(name: "⌘⇧ with a key", handsFree: Chord(modifiers: [.shift, .command], keyCode: keyK), problem: nil),
        Row(name: "three modifiers with ⌘", handsFree: Chord(modifiers: [.control, .option, .command]), problem: nil),
        Row(name: "a key chord", handsFree: Chord(modifiers: .option, keyCode: KeyCode.space), problem: nil),
        Row(name: "fn with a key", handsFree: Chord(modifiers: .function, keyCode: keyK), problem: nil),
        Row(name: "a key alone", handsFree: Chord(modifiers: [], keyCode: keyK), problem: .noModifier),
        Row(
            name: "Shift with a key types a capital", handsFree: Chord(modifiers: .shift, keyCode: keyK),
            problem: .noModifier),
        Row(name: "no keys", handsFree: Chord(modifiers: []), problem: .noModifier),
        Row(name: "Spotlight", handsFree: Chord(modifiers: .command, keyCode: KeyCode.space), problem: .reserved),
        Row(
            name: "Spotlight with the right Command",
            handsFree: Chord(modifiers: .rightCommand, keyCode: KeyCode.space),
            problem: .reserved),
        Row(
            name: "the paste kotoba sends", cleanup: Chord(modifiers: .command, keyCode: KeyCode.ansiV),
            problem: .reserved),
        Row(
            name: "a screenshot", handsFree: Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansi4),
            problem: .reserved),
        Row(
            name: "⌥⌘Space opens a Finder search",
            handsFree: Chord(modifiers: [.option, .command], keyCode: KeyCode.space),
            problem: .reserved),
        Row(
            name: "⌃⌥⌘Space is free",
            handsFree: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space), problem: nil),
        Row(name: "Esc as the key", handsFree: Chord(modifiers: .option, keyCode: KeyCode.escape), problem: .escape),
        Row(name: "the same chord twice", cleanup: .defaultHandsFree, problem: .sameAsCleanup(.handsFree)),
        Row(
            name: "the same key chord twice", handsFree: Chord(modifiers: .option, keyCode: KeyCode.space),
            cleanup: Chord(modifiers: .option, keyCode: KeyCode.space), problem: .sameAsCleanup(.handsFree)),
        Row(
            name: "the dictation chord holds the whole cleanup chord",
            handsFree: .defaultCleanup, cleanup: .defaultHandsFree, problem: .dictationIncludesCleanup(.handsFree)),
        Row(
            name: "right Option dictation holds an either-side Option cleanup",
            handsFree: Chord(modifiers: [.control, .rightOption, .command]),
            cleanup: Chord(modifiers: [.control, .option, .command]),
            problem: .dictationIncludesCleanup(.handsFree)),
        Row(
            name: "a dictation key chord holds the cleanup modifiers on the way",
            handsFree: Chord(modifiers: [.control, .option, .command], keyCode: keyK),
            cleanup: Chord(modifiers: [.control, .option, .command]), problem: .dictationIncludesCleanup(.handsFree)),
        Row(
            name: "either-side dictation does not always hold a right-side cleanup",
            handsFree: Chord(modifiers: [.control, .option, .command]),
            cleanup: Chord(modifiers: [.control, .rightOption, .command]),
            problem: nil),
        Row(
            name: "a cleanup key chord on top of the dictation chord",
            cleanup: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space), problem: nil),
        Row(
            name: "unrelated chords", handsFree: Chord(modifiers: .function), cleanup: Chord(modifiers: .rightOption),
            problem: nil),
    ]

    static let mouseFour = Chord(mouseButton: 3)

    /// A middle or side mouse button is a dictation chord's key: it needs no modifier and takes none of the key rules.
    static let mouseRows: [Row] = [
        Row(name: "hands-free on a side button", handsFree: mouseFour, problem: nil),
        Row(name: "push to talk on the middle button", pushToTalk: Chord(mouseButton: 2), problem: nil),
        Row(
            name: "push to talk on ⌥ with a side button", pushToTalk: Chord(modifiers: .option, mouseButton: 3),
            problem: nil),
        Row(name: "⌘ with a side button", handsFree: Chord(modifiers: .command, mouseButton: 4), problem: nil),
        Row(name: "both dictation chords on one button", handsFree: mouseFour, pushToTalk: mouseFour, problem: nil),
        Row(
            name: "hands-free and push to talk on two side buttons", handsFree: Chord(mouseButton: 4),
            pushToTalk: mouseFour, problem: nil),
        Row(name: "cleanup on a side button", cleanup: mouseFour, problem: .mouseButtonOnlyForDictation),
        Row(name: "Paste Last on a side button", pasteLast: mouseFour, problem: .mouseButtonOnlyForDictation),
        Row(name: "Copy Last on a side button", copyLast: mouseFour, problem: .mouseButtonOnlyForDictation),
        Row(name: "Polish Last on a side button", polishLast: mouseFour, problem: .mouseButtonOnlyForDictation),
        Row(
            name: "the default Copy Last next to a side button for both dictation chords", handsFree: mouseFour,
            copyLast: .defaultCopyLast, problem: nil),
        Row(
            name: "Paste Last with the modifiers of a side-button chord does not hold it",
            pushToTalk: Chord(modifiers: [.control, .command], mouseButton: 3),
            pasteLast: Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV), problem: nil),
        Row(
            name: "a side-button chord that holds the whole cleanup chord",
            handsFree: Chord(modifiers: [.control, .option, .shift, .command], mouseButton: 3),
            problem: .dictationIncludesCleanup(.handsFree)),
    ]

    /// Saved as "<modifiers>", "<modifiers>:<key code>" or "<modifiers>:m<button>"; an unreadable value is nil, so the
    /// default applies.
    @Test(
        arguments: [
            ("7", Chord(modifiers: ModifierKeys(rawValue: 7))),
            ("12:49", Chord(modifiers: .option, keyCode: KeyCode.space)),
            ("0:m3", Chord(mouseButton: 3)),
            ("12:m2", Chord(modifiers: .option, mouseButton: 2)),
            ("0:m31", Chord(mouseButton: 31)),
            ("0:m1", nil), ("0:m0", nil), ("0:m", nil), ("0:m32", nil), ("0:m99999999999", nil), ("0:mx", nil),
            ("0:", nil), ("a", nil), ("0:1:2", nil), ("0:70000", nil),
        ] as [(String, Chord?)])
    func aStoredChordReadsBack(_ stored: String, _ chord: Chord?) {
        #expect(Chord(storedValue: stored) == chord)
        if let chord {
            #expect(chord.storedValue == stored)
        }
    }

    @Test func theDefaultCopyLastStaysOnNextToMouseChords() {
        #expect(Chord.copyLast(saved: nil, handsFree: Self.mouseFour, cleanup: .defaultCleanup) == .defaultCopyLast)
    }

    /// Push to talk drops a press shorter than the hold threshold, so one modifier alone may be its chord.
    static let pushToTalkRows: [Row] = [
        Row(name: "push to talk on ⌥ alone", pushToTalk: Chord(modifiers: .option), problem: nil),
        Row(name: "push to talk on left ⌥ alone", pushToTalk: Chord(modifiers: .leftOption), problem: nil),
        Row(name: "push to talk on ⌃ alone", pushToTalk: Chord(modifiers: .control), problem: nil),
        Row(name: "push to talk on fn alone", pushToTalk: Chord(modifiers: .function), problem: nil),
        Row(name: "push to talk on right ⌘ alone", pushToTalk: Chord(modifiers: .rightCommand), problem: nil),
        Row(name: "push to talk on right ⇧ alone", pushToTalk: Chord(modifiers: .rightShift), problem: nil),
        // Held while typing capitals, or while pausing before a shortcut, longer than the hold threshold.
        Row(name: "push to talk on ⇧ alone", pushToTalk: Chord(modifiers: .shift), problem: .commonModifierAlone),
        Row(
            name: "push to talk on left ⇧ alone", pushToTalk: Chord(modifiers: .leftShift),
            problem: .commonModifierAlone),
        Row(name: "push to talk on ⌘ alone", pushToTalk: Chord(modifiers: .command), problem: .commonModifierAlone),
        Row(
            name: "push to talk on left ⌘ alone", pushToTalk: Chord(modifiers: .leftCommand),
            problem: .commonModifierAlone),
        Row(name: "push to talk on ⌥⌘", pushToTalk: Chord(modifiers: [.option, .command]), problem: .commandPair),
        Row(name: "push to talk with no keys", pushToTalk: Chord(modifiers: []), problem: .noModifier),
        Row(name: "push to talk on a key alone", pushToTalk: Chord(modifiers: [], keyCode: keyK), problem: .noModifier),
        Row(
            name: "push to talk on Spotlight", pushToTalk: Chord(modifiers: .command, keyCode: KeyCode.space),
            problem: .reserved),
        Row(name: "push to talk on the hands-free chord", pushToTalk: .defaultHandsFree, problem: nil),
        Row(
            name: "hands-free keeps its rules next to push to talk", handsFree: Chord(modifiers: .option),
            pushToTalk: Chord(modifiers: .function), problem: .commonModifierAlone),
        Row(
            name: "push to talk on the cleanup chord", pushToTalk: .defaultCleanup,
            problem: .sameAsCleanup(.pushToTalk)),
        Row(
            name: "push to talk holds the whole cleanup chord",
            pushToTalk: Chord(modifiers: [.function, .control, .option, .shift, .command]),
            problem: .dictationIncludesCleanup(.pushToTalk)),
        Row(
            name: "the cleanup chord holds push to talk on the way: the press follows cleanup",
            pushToTalk: Chord(modifiers: .option), problem: nil),
        Row(
            name: "Paste Last holds ⌥ push to talk on the way",
            pushToTalk: Chord(modifiers: .option),
            pasteLast: Chord(modifiers: [.control, .option], keyCode: KeyCode.ansiV),
            problem: .pasteLastIncludes(.pushToTalk)),
        Row(
            name: "Paste Last on the push-to-talk key chord",
            pushToTalk: Chord(modifiers: .option, keyCode: KeyCode.space),
            pasteLast: Chord(modifiers: .option, keyCode: KeyCode.space),
            problem: .pasteLastSameAs(.pushToTalk)),
        Row(
            name: "Paste Last next to ⌥ push to talk",
            pushToTalk: Chord(modifiers: .option),
            pasteLast: Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiV), problem: nil),
    ]

    /// Each row: the chord saved, its role, the hands-free chord after the save, the push-to-talk chord the owner had
    /// set (nil: none), and the one kept.
    @Test(arguments: [
        (
            Chord?.some(Chord(modifiers: .option)), ChordRole.pushToTalk, Chord.defaultHandsFree, Chord?.none,
            Chord?.some(Chord(modifiers: .option))
        ),
        (.defaultHandsFree, .pushToTalk, .defaultHandsFree, Chord(modifiers: .option), nil),
        (nil, .pushToTalk, .defaultHandsFree, Chord(modifiers: .option), nil),
        (
            Chord(modifiers: .rightOption), .handsFree, Chord(modifiers: .rightOption), Chord(modifiers: .rightOption),
            Chord(modifiers: .rightOption)
        ),
        (
            Chord(modifiers: .function), .handsFree, Chord(modifiers: .function), Chord(modifiers: .option),
            Chord(modifiers: .option)
        ),
        (Chord(modifiers: .function), .handsFree, Chord(modifiers: .function), nil, nil),
        (.defaultCleanup, .cleanup, .defaultHandsFree, Chord(modifiers: .option), Chord(modifiers: .option)),
    ])
    func aPushToTalkChordTheOwnerSetStays(
        _ saved: Chord?, _ role: ChordRole, _ handsFree: Chord, _ set: Chord?, _ kept: Chord?
    ) {
        #expect(Chord.pushToTalk(afterSaving: saved, as: role, handsFree: handsFree, kept: set) == kept)
    }

    // One array of arrays: a chain of `+` takes the type checker too long.
    @Test(arguments: [rows, pasteLastRows, copyLastRows, polishLastRows, pushToTalkRows, mouseRows].flatMap { $0 })
    func problem(_ row: Row) {
        #expect(
            Chord.problem(
                handsFree: row.handsFree, pushToTalk: row.pushToTalk, cleanup: row.cleanup, pasteLast: row.pasteLast,
                copyLast: row.copyLast, polishLast: row.polishLast) == row.problem)
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
            outcome: .recorded(.defaultHandsFree)),
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
        Row(
            name: "a mouse button is recorded as it goes down",
            inputs: [.otherMouseDown(button: 3, modifiers: [])], outcome: .recorded(Chord(mouseButton: 3))),
        Row(
            name: "a mouse button with the modifiers held then",
            inputs: [.modifiersChanged(.leftOption), .otherMouseDown(button: 2, modifiers: .leftOption)],
            outcome: .recorded(Chord(modifiers: .option, mouseButton: 2))),
        Row(
            name: "a left or right button is never a chord",
            inputs: [.otherMouseDown(button: 0, modifiers: []), .otherMouseDown(button: 1, modifiers: [])],
            outcome: nil),
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
        (Chord(modifiers: .option), true), (Chord(modifiers: .rightOption), true),
        (Chord.defaultHandsFree, false), (Chord(modifiers: .function), false),
        (Chord(modifiers: [.control, .option], keyCode: KeyCode.space), false),
        (Chord(modifiers: .option, mouseButton: 3), false),
    ])
    func oneOrTwoModifiersAloneOpenTheMicBriefly(_ chord: Chord, _ opens: Bool) {
        #expect(chord.opensMicBriefly == opens)
    }
}
