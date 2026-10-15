/// Modifier keys held, as the app's event tap reports them.
public struct ModifierKeys: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let command = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
    /// The Fn / Globe key.
    public static let function = Self(rawValue: 1 << 4)

    /// Ctrl+Opt+Cmd; other modifiers held with it do not matter.
    public static let chord: ModifierKeys = [.control, .option, .command]
}

/// One keyboard event from the event tap.
public enum KeyInput: Sendable, Hashable {
    case modifiersChanged(ModifierKeys)
    /// A key went down. `keyCode` is the macOS virtual key code.
    case keyDown(keyCode: UInt16)
    /// The system had disabled the tap and it is back on; `modifiers` is the state now, since a
    /// release may have been missed.
    case tapReenabled(modifiers: ModifierKeys)
}

/// What the tap does with one keyboard event: the hotkey event to send, if any, and whether to
/// keep the key from the focused app.
public struct HotkeyDecision: Sendable, Equatable {
    /// In order; one modifier change can both press the chord and complete the cleanup chord.
    public var events: [HotkeyEvent]
    public var isSwallowed: Bool

    public init(events: [HotkeyEvent], isSwallowed: Bool = false) {
        self.events = events
        self.isSwallowed = isSwallowed
    }

    public init(event: HotkeyEvent, isSwallowed: Bool = false) {
        self.init(events: [event], isSwallowed: isSwallowed)
    }

    public static let pass = Self(events: [])
}

/// Turns raw keyboard events into hotkey events. The tap keeps one instance behind a lock and
/// calls `classify` for every event, so this must stay cheap.
public struct HotkeyClassifier: Sendable {
    /// On while the indicator shows recording: Esc then cancels and does not reach the app.
    public var swallowsEscape = false
    private let escapeKeyCode: UInt16
    /// The owner's cleanup chord; nil turns cleanup dictation off.
    public var cleanupChord: ModifierKeys?
    private var isChordDown = false
    /// Set at the first other key typed during one chord press.
    private var isInterrupted = false
    /// Set when the cleanup chord was complete at some moment of this press.
    private var isCleanupSeen = false

    /// `escapeKeyCode` is the app's `kVK_Escape`; this module does not link Carbon.
    /// `cleanupChord` is the owner's setting. The first moment of a press when all of it is down,
    /// in any order, reports `.cleanupModifier` once; the pipeline decides the mode later.
    public init(escapeKeyCode: UInt16, cleanupChord: ModifierKeys?) {
        self.escapeKeyCode = escapeKeyCode
        self.cleanupChord = cleanupChord
    }

    public mutating func classify(_ input: KeyInput) -> HotkeyDecision {
        switch input {
        case .modifiersChanged(let modifiers), .tapReenabled(let modifiers):
            return modifiersChanged(to: modifiers)
        case .keyDown(let keyCode):
            let isEscape = keyCode == escapeKeyCode
            if isEscape, swallowsEscape {
                return HotkeyDecision(event: .escape, isSwallowed: true)
            }
            // A key typed with the chord held, Esc included, makes the chord part of another
            // app's shortcut. The key still reaches the app.
            guard isChordDown, !isInterrupted else { return .pass }
            isInterrupted = true
            return HotkeyDecision(event: .chordInterrupted)
        }
    }

    private mutating func modifiersChanged(to modifiers: ModifierKeys) -> HotkeyDecision {
        var events: [HotkeyEvent] = []
        let isDown = modifiers.isSuperset(of: .chord)
        if isDown, !isChordDown {
            events.append(.chordDown)
            isInterrupted = false
            isCleanupSeen = false
        } else if !isDown, isChordDown {
            events.append(.chordUp)
        }
        isChordDown = isDown
        if isDown, !isCleanupSeen, let cleanupChord, modifiers.isSuperset(of: cleanupChord) {
            isCleanupSeen = true
            events.append(.cleanupModifier)
        }
        return HotkeyDecision(events: events)
    }
}
