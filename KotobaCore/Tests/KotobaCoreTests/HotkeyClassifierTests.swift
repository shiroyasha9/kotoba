import Testing

@testable import KotobaCore

/// Each row: whether the indicator shows recording, the keyboard events in order, and the
/// decision expected for each.
struct HotkeyClassifierTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var recording = false
        var paused = false
        var handsFreeChord = Chord.defaultHandsFree
        var pushToTalkChord: Chord?
        var cleanupChord: Chord? = .defaultCleanup
        var pasteLastChord: Chord?
        var copyLastChord: Chord?
        var isReturnGestureOn = true
        let steps: [(KeyInput, HotkeyDecision)]

        var testDescription: String { name }
    }

    /// kVK_Escape
    /// In a key event: the modifiers the steps before left held, as a real key event carries them. `Keyboard`
    /// fills it in; a row that needs other flags (a missed release) names them.
    static let asHeld = ModifierKeys(rawValue: 1 << 15)
    static let leftArrow: UInt16 = 0x7B
    static let escape = down(KeyCode.escape)
    static let keyA = down(0)
    static let spaceDown = down(KeyCode.space)
    static let spaceRepeat = down(KeyCode.space, isRepeat: true)
    static let spaceUp = up(KeyCode.space)
    static let chord = KeyInput.modifiersChanged([.leftControl, .leftOption, .leftCommand])
    static let none = KeyInput.modifiersChanged([])
    static let hyper = KeyInput.modifiersChanged([.leftControl, .leftOption, .leftCommand, .leftShift])
    static let fnKey = KeyInput.modifiersChanged(.function)
    static let leftOption = KeyInput.modifiersChanged(.leftOption)
    static let rightOption = KeyInput.modifiersChanged(.rightOption)
    static let optionSpace = Chord(modifiers: .option, keyCode: KeyCode.space)

    static let rows: [Row] = [
        Row(
            name: "the chord goes down and up",
            steps: [
                (.modifiersChanged(.leftControl), .pass), (.modifiersChanged([.leftControl, .leftOption]), .pass),
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (.modifiersChanged([.leftControl, .leftOption]), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "shift held first: the chord-down also reports the cleanup modifier",
            steps: [
                (.modifiersChanged(.leftShift), .pass),
                (.modifiersChanged([.leftControl, .leftOption, .leftShift]), .pass),
                (hyper, HotkeyDecision(events: [.chordDown(.tapOrHold), .cleanupModifier])),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "shift last: the cleanup modifier comes after the chord-down",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (hyper, HotkeyDecision(event: .cleanupModifier)),
                (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "the cleanup modifier is reported once per press, even if shift goes up and down",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (hyper, HotkeyDecision(event: .cleanupModifier)),
                (chord, .pass), (hyper, .pass), (none, HotkeyDecision(event: .chordUp)),
                (hyper, HotkeyDecision(events: [.chordDown(.tapOrHold), .cleanupModifier])),
            ]
        ),
        Row(
            name: "with cleanup off, shift with the chord reports nothing more",
            cleanupChord: nil,
            steps: [(hyper, HotkeyDecision(event: .chordDown(.tapOrHold))), (none, HotkeyDecision(event: .chordUp))]
        ),
        Row(
            name: "a configured cleanup chord replaces the default",
            cleanupChord: Chord(modifiers: [.function, .control, .option, .command]),
            steps: [
                (hyper, HotkeyDecision(event: .chordDown(.tapOrHold))), (none, HotkeyDecision(event: .chordUp)),
                (
                    .modifiersChanged([.function, .leftControl, .leftOption, .leftCommand]),
                    HotkeyDecision(events: [.chordDown(.tapOrHold), .cleanupModifier])
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
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
                (keyA, .pass), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "Esc with the chord held before recording shows is a shortcut",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (escape, HotkeyDecision(event: .chordInterrupted)),
            ]
        ),
        Row(
            name: "Esc with the chord held while recording shows cancels",
            recording: true,
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (escape, HotkeyDecision(event: .escape, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a new chord press can be interrupted again",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
                (none, HotkeyDecision(event: .chordUp)), (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
            ]
        ),
        Row(
            name: "a release missed while the tap was off is reported when it is back",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (.tapReenabled(modifiers: [], isChordKeyDown: false), HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a tap back on with the chord still held reports nothing",
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (.tapReenabled(modifiers: [.leftControl, .leftOption, .leftCommand], isChordKeyDown: false), .pass),
            ]
        ),
        Row(
            name: "fn alone as the chord: tap, and a key with it is a shortcut",
            handsFreeChord: Chord(modifiers: .function),
            steps: [
                (fnKey, HotkeyDecision(event: .chordDown(.tapOrHold))), (none, HotkeyDecision(event: .chordUp)),
                (fnKey, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (keyA, HotkeyDecision(event: .chordInterrupted)),
                (none, HotkeyDecision(event: .chordUp)), (chord, .pass),
            ]
        ),
        Row(
            name: "right Option as the chord: left Option is ordinary",
            handsFreeChord: Chord(modifiers: .rightOption),
            steps: [
                (leftOption, .pass), (none, .pass), (rightOption, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (.modifiersChanged([.leftOption, .rightOption]), .pass), (leftOption, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "a key chord goes down and up with its key; the key never reaches the app",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (spaceRepeat, .swallow), (none, .pass), (spaceUp, HotkeyDecision(event: .chordUp, isSwallowed: true)),
                (spaceUp, .pass),
            ]
        ),
        Row(
            name: "a key chord needs exactly its modifiers",
            handsFreeChord: optionSpace,
            steps: [
                (spaceDown, .pass), (spaceUp, .pass), (.modifiersChanged([.leftOption, .leftShift]), .pass),
                (spaceDown, .pass), (.modifiersChanged(.rightOption), .pass),
                (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
            ]
        ),
        Row(
            name: "another key during a key chord press is a shortcut and reaches the app",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (keyA, HotkeyDecision(event: .chordInterrupted)), (keyA, .pass),
                (spaceUp, HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
        Row(
            name: "Esc while recording cancels with a key chord too",
            recording: true,
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (escape, HotkeyDecision(event: .escape, isSwallowed: true)),
            ]
        ),
        Row(
            name: "a key chord release missed while the tap was off is reported when it is back",
            handsFreeChord: optionSpace,
            steps: [
                (leftOption, .pass), (spaceDown, HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true)),
                (.tapReenabled(modifiers: .leftOption, isChordKeyDown: true), .pass),
                (.tapReenabled(modifiers: [], isChordKeyDown: false), HotkeyDecision(event: .chordUp)),
                (spaceUp, .pass),
            ]
        ),
        Row(
            name: "a cleanup key chord on top of the dictation chord completes the cleanup chord",
            cleanupChord: Chord(modifiers: [.control, .option, .command], keyCode: KeyCode.space),
            steps: [
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))),
                (spaceDown, HotkeyDecision(event: .cleanupModifier, isSwallowed: true)),
                (spaceUp, .swallow), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "an unrelated cleanup chord starts the press and completes cleanup at once",
            cleanupChord: Chord(modifiers: .function),
            steps: [
                (fnKey, HotkeyDecision(events: [.chordDown(.tapOrHold), .cleanupModifier])),
                (none, HotkeyDecision(event: .chordUp)),
                (chord, HotkeyDecision(event: .chordDown(.tapOrHold))), (none, HotkeyDecision(event: .chordUp)),
            ]
        ),
        Row(
            name: "an unrelated cleanup key chord starts the press, and its key does not reach the app",
            handsFreeChord: Chord(modifiers: .function),
            cleanupChord: optionSpace,
            steps: [
                (leftOption, .pass),
                (spaceDown, HotkeyDecision(events: [.chordDown(.tapOrHold), .cleanupModifier], isSwallowed: true)),
                (spaceUp, HotkeyDecision(event: .chordUp, isSwallowed: true)),
            ]
        ),
    ]

    // One array of arrays: a chain of `+` takes the type checker too long.
    @Test(arguments: [rows, missedReleaseRows, returnRows, pasteLastRows, copyLastRows, splitRows].flatMap { $0 })
    func classify(_ row: Row) {
        var keyboard = Keyboard(
            classifier: HotkeyClassifier(
                handsFreeChord: row.handsFreeChord, pushToTalkChord: row.pushToTalkChord,
                cleanupChord: row.cleanupChord,
                pasteLastChord: row.pasteLastChord, copyLastChord: row.copyLastChord,
                isReturnGestureOn: row.isReturnGestureOn))
        keyboard.classifier.isRecordingShown = row.recording
        keyboard.classifier.isPaused = row.paused
        for (index, (input, expected)) in row.steps.enumerated() {
            #expect(keyboard.press(input) == expected, "step \(index)")
        }
    }
}

extension HotkeyClassifierTests {
    static func down(_ keyCode: UInt16, _ modifiers: ModifierKeys = asHeld, isRepeat: Bool = false) -> KeyInput {
        .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
    }

    static func up(_ keyCode: UInt16, _ modifiers: ModifierKeys = asHeld) -> KeyInput {
        .keyUp(keyCode: keyCode, modifiers: modifiers)
    }

    /// Sends inputs to the classifier, with `asHeld` in a key event replaced by the modifiers held.
    struct Keyboard {
        var classifier: HotkeyClassifier
        private var held: ModifierKeys = []

        init(classifier: HotkeyClassifier) {
            self.classifier = classifier
        }

        mutating func press(_ input: KeyInput) -> HotkeyDecision {
            let filled: KeyInput =
                switch input {
                case .modifiersChanged(let modifiers), .tapReenabled(let modifiers, _):
                    {
                        held = modifiers
                        return input
                    }()
                case .keyDown(let keyCode, asHeld, let isRepeat):
                    .keyDown(keyCode: keyCode, modifiers: held, isRepeat: isRepeat)
                case .keyUp(let keyCode, asHeld): .keyUp(keyCode: keyCode, modifiers: held)
                case .keyDown, .keyUp, .chordKeyReleased, .posted, .mouseDown: input
                }
            return classifier.classify(filled)
        }
    }
}

extension HotkeyClassifierTests {
    @Test
    func aNewChordAppliesAtTheNextEvent() {
        var keyboard = Keyboard(classifier: HotkeyClassifier(cleanupChord: nil))
        #expect(keyboard.press(Self.fnKey) == .pass)
        keyboard.classifier.handsFreeChord = Chord(modifiers: .function)
        #expect(keyboard.press(Self.none) == .pass)
        #expect(keyboard.press(Self.fnKey) == HotkeyDecision(event: .chordDown(.tapOrHold)))
        keyboard.classifier.handsFreeChord = Self.optionSpace
        #expect(keyboard.press(Self.none) == HotkeyDecision(event: .chordUp))
        #expect(keyboard.press(Self.leftOption) == .pass)
        #expect(keyboard.press(Self.spaceDown) == HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true))
    }

    @Test
    func whilePausedNoChordCountsAndAPressInProgressEnds() {
        var keyboard = Keyboard(
            classifier: HotkeyClassifier(cleanupChord: .defaultCleanup))
        #expect(keyboard.press(Self.chord) == HotkeyDecision(event: .chordDown(.tapOrHold)))
        keyboard.classifier.isPaused = true
        #expect(keyboard.press(Self.hyper) == HotkeyDecision(event: .chordUp))
        #expect(keyboard.press(Self.chord) == .pass)
        #expect(keyboard.press(Self.keyA) == .pass)
        keyboard.classifier.handsFreeChord = Self.optionSpace
        #expect(keyboard.press(Self.leftOption) == .pass)
        #expect(keyboard.press(Self.spaceDown) == .pass)
        keyboard.classifier.isPaused = false
        #expect(keyboard.press(Self.spaceUp) == .pass)
        #expect(keyboard.press(Self.spaceDown) == HotkeyDecision(event: .chordDown(.tapOrHold), isSwallowed: true))
    }
}
