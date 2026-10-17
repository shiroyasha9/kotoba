/// What the shortcut recorder makes of the keys pressed while it listens. Modifiers alone are recorded when the
/// last one goes up, as the most that were down at once; a key is recorded as it goes down, with the modifiers
/// held then, and so is a middle or side mouse button. A side counts only when the right key alone was used: left ⌥ or
/// both make "either ⌥".
public struct ChordCapture: Sendable {
    public enum Outcome: Sendable, Equatable {
        case recorded(Chord)
        /// Esc with no modifier held.
        case cancelled
    }

    /// The modifiers held now, for the recorder to show while it listens.
    public private(set) var held: ModifierKeys = []
    private var peak: ModifierKeys = []

    public init() {}

    public mutating func handle(_ input: KeyInput) -> Outcome? {
        switch input {
        case .modifiersChanged(let modifiers), .tapReenabled(let modifiers, _):
            held = modifiers
            peak.formUnion(modifiers)
            guard modifiers.isEmpty, !peak.isEmpty else { return nil }
            return .recorded(Chord(modifiers: Self.sides(peak)))
        case .keyDown(let keyCode, _, _):
            if keyCode == KeyCode.escape, held.isEmpty { return .cancelled }
            return .recorded(Chord(modifiers: Self.sides(held), keyCode: keyCode))
        case .otherMouseDown(let button, _):
            guard Chord.mouseButtons.contains(button) else { return nil }
            return .recorded(Chord(modifiers: Self.sides(held), mouseButton: button))
        case .keyUp, .chordKeyReleased, .posted, .mouseDown, .otherMouseUp, .otherMouseDragged:
            return nil
        }
    }

    private static func sides(_ pressed: ModifierKeys) -> ModifierKeys {
        var chord: ModifierKeys = []
        for kind in ModifierKeys.allKinds {
            let sides = pressed.intersection(kind)
            guard !sides.isEmpty else { continue }
            let right = kind.intersection(.rightSides)
            chord.formUnion(sides == right ? right : kind)
        }
        return chord
    }
}
