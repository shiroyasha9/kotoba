/// One keyboard event from the event tap, or a middle or side mouse button while a dictation chord is one.
public enum KeyInput: Sendable, Hashable {
    case modifiersChanged(ModifierKeys)
    /// A key went down, or repeats. `keyCode` is the macOS virtual key code; `modifiers` the event's own flags,
    /// so a modifier release the tap missed is found at the next key.
    case keyDown(keyCode: UInt16, modifiers: ModifierKeys, isRepeat: Bool)
    case keyUp(keyCode: UInt16, modifiers: ModifierKeys)
    /// The system had disabled the tap and it is back on; a release may have been missed. `modifiers` is the
    /// state now, `isChordKeyDown` whether the key or button of a held chord (`heldTrigger`) is still down.
    case tapReenabled(modifiers: ModifierKeys, isChordKeyDown: Bool)
    /// The tap found the key of the held key chord (`heldChordKey`) up although no key-up came, for example
    /// after Secure Input took the keyboard: the press ended.
    case chordKeyReleased
    /// An event kotoba posted itself (its Cmd-V and Return): it passes and changes no state.
    case posted
    /// A mouse button went down (left, right or other): a ⌘-click or ⌥-drag makes a press part of a mouse gesture, as
    /// a typed key does.
    case mouseDown
    /// A mouse button other than left or right went down (`Chord.Trigger.mouseButton`), from the tap: it listens to
    /// these only while a dictation chord is a mouse button. `modifiers` are the event's own flags.
    case otherMouseDown(button: Int, modifiers: ModifierKeys)
    case otherMouseUp(button: Int, modifiers: ModifierKeys)
    /// The pointer moved with that button down.
    case otherMouseDragged(button: Int)
}

/// What the tap does with one keyboard event: the hotkey events to send, if any, and whether to
/// keep the key (or the mouse button) from the focused app.
public struct HotkeyDecision: Sendable, Equatable {
    /// In order; one modifier change can both press the chord and complete the cleanup chord.
    public var events: HotkeyEvents
    public var isSwallowed: Bool
    /// A drag of the held mouse chord's button goes on as a plain pointer move: apps never got that button's down.
    public var passesAsMove: Bool

    public init(events: HotkeyEvents, isSwallowed: Bool = false, passesAsMove: Bool = false) {
        self.events = events
        self.isSwallowed = isSwallowed
        self.passesAsMove = passesAsMove
    }

    public init(event: HotkeyEvent, isSwallowed: Bool = false) {
        self.init(events: HotkeyEvents(event), isSwallowed: isSwallowed)
    }

    public static let pass = Self(events: [])
    public static let swallow = Self(events: [], isSwallowed: true)
}
