import Testing

@testable import KotobaCore

/// A click on the indicator pill acts as a chord tap, in order with the real chord.
extension HotkeyClassifierTests {
    @Test
    func aPillClickIsATapOrOnlyAChordDownWhileAChordIsHeld() {
        var keyboard = Keyboard(classifier: HotkeyClassifier(cleanupChord: .defaultCleanup))
        #expect(keyboard.classifier.pillClick() == [.chordDown, .chordUp])
        #expect(keyboard.press(Self.chord) == HotkeyDecision(event: .chordDown))
        #expect(keyboard.classifier.pillClick() == [.chordDown])
        #expect(keyboard.press(Self.none) == HotkeyDecision(event: .chordUp))
    }
}
