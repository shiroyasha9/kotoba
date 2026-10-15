import Testing

@testable import KotobaCore

/// Return while recording stops the dictation and sends Return after the paste (submit after paste).
extension HotkeyClassifierTests {
    static let returnKey = KeyCode.return
    static let submit = HotkeyDecision(event: .submit, isSwallowed: true)

    static let returnRows: [Row] = [
        Row(
            name: "Return while recording submits; its repeats and key-up do not reach the app",
            recording: true,
            steps: [
                (down(returnKey), submit), (down(returnKey, isRepeat: true), .swallow), (up(returnKey), .swallow),
            ]
        ),
        Row(
            name: "Return while not recording reaches the app",
            steps: [(down(returnKey), .pass), (down(returnKey, isRepeat: true), .pass), (up(returnKey), .pass)]
        ),
        Row(
            name: "Return with a modifier while recording reaches the app",
            recording: true,
            steps: [
                (.modifiersChanged(.leftShift), .pass), (down(returnKey), .pass), (up(returnKey), .pass),
            ]
        ),
        Row(
            name: "Esc while recording still cancels",
            recording: true,
            steps: [(escape, HotkeyDecision(event: .escape, isSwallowed: true))]
        ),
        Row(
            name: "with the gesture off, Return while recording reaches the app",
            recording: true,
            isReturnGestureOn: false,
            steps: [(down(returnKey), .pass), (up(returnKey), .pass)]
        ),
        Row(
            name: "a Return key-up missed: the next Return is a new press",
            recording: true,
            steps: [(down(returnKey), submit), (down(returnKey), submit), (up(returnKey), .swallow)]
        ),
        Row(
            name: "a Return kotoba posted during a recording is not a submit and reaches the app",
            recording: true,
            steps: [(.posted, .pass), (down(returnKey), submit)]
        ),
        Row(
            name: "a Return kotoba posted while a submit Return is held changes nothing",
            recording: true,
            steps: [(down(returnKey), submit), (.posted, .pass), (down(returnKey, isRepeat: true), .swallow)]
        ),
        Row(
            name: "while a shortcut recorder listens, Esc and Return reach it",
            recording: true,
            paused: true,
            steps: [(escape, .pass), (down(returnKey), .pass), (up(returnKey), .pass)]
        ),
        Row(
            name: "a tap back on forgets a Return held, so a later key-up reaches the app",
            recording: true,
            steps: [
                (down(returnKey), submit), (.tapReenabled(modifiers: [], isChordKeyDown: false), .pass),
                (up(returnKey), .pass),
            ]
        ),
    ]

    @Test
    func aReturnHeldWhenRecordingEndsIsStillSwallowedUntilItsKeyUp() {
        var keyboard = Keyboard(
            classifier: HotkeyClassifier(
                cleanupChord: .defaultCleanup, isReturnGestureOn: true))
        keyboard.classifier.isRecordingShown = true
        #expect(keyboard.press(Self.down(Self.returnKey)) == Self.submit)
        keyboard.classifier.isRecordingShown = false
        #expect(keyboard.press(Self.down(Self.returnKey, isRepeat: true)) == .swallow)
        #expect(keyboard.press(Self.up(Self.returnKey)) == .swallow)
        #expect(keyboard.press(Self.down(Self.returnKey)) == .pass)
        #expect(keyboard.press(Self.up(Self.returnKey)) == .pass)
    }
}
