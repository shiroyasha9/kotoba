/// Modifier keys, left and right apart, as the app's event tap reports them. In a `Chord`, a kind with both
/// sides set (`.option`) takes either side; one side (`.rightOption`) takes only that key.
public struct ModifierKeys: OptionSet, Sendable, Hashable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let leftControl = Self(rawValue: 1 << 0)
    public static let rightControl = Self(rawValue: 1 << 1)
    public static let leftOption = Self(rawValue: 1 << 2)
    public static let rightOption = Self(rawValue: 1 << 3)
    public static let leftShift = Self(rawValue: 1 << 4)
    public static let rightShift = Self(rawValue: 1 << 5)
    public static let leftCommand = Self(rawValue: 1 << 6)
    public static let rightCommand = Self(rawValue: 1 << 7)
    /// The Fn / Globe key; it has one side.
    public static let function = Self(rawValue: 1 << 8)

    public static let control: Self = [.leftControl, .rightControl]
    public static let option: Self = [.leftOption, .rightOption]
    public static let shift: Self = [.leftShift, .rightShift]
    public static let command: Self = [.leftCommand, .rightCommand]
    public static let rightSides: Self = [.rightControl, .rightOption, .rightShift, .rightCommand]
    /// Each kind with all its sides, in Apple's display order: fn ⌃ ⌥ ⇧ ⌘.
    public static let allKinds: [Self] = [.function, .control, .option, .shift, .command]

    /// Each kind present, with both its sides: right ⌥ and ⌘ give ⌥⌘.
    public var kinds: Self {
        var kinds: Self = []
        for kind in Self.allKinds where !isDisjoint(with: kind) {
            kinds.formUnion(kind)
        }
        return kinds
    }

    /// How many kinds (fn, ⌃, ⌥, ⇧, ⌘) it holds; both sides of one kind count once.
    public var kindCount: Int {
        Self.allKinds.count { !isDisjoint(with: $0) }
    }

    /// Read as a chord's modifiers: every kind in it is held, on one of the sides it allows.
    func isSatisfied(by held: Self) -> Bool {
        Self.allKinds.allSatisfy { kind in
            let sides = intersection(kind)
            return sides.isEmpty || !sides.isDisjoint(with: held)
        }
    }

    /// Read as a chord's modifiers: whenever `other` (another chord's modifiers) is satisfied, so is this.
    func isImplied(by other: Self) -> Bool {
        Self.allKinds.allSatisfy { kind in
            let sides = intersection(kind)
            let otherSides = other.intersection(kind)
            return sides.isEmpty || (!otherSides.isEmpty && otherSides.isSubset(of: sides))
        }
    }
}

/// One keyboard event from the event tap.
public enum KeyInput: Sendable, Hashable {
    case modifiersChanged(ModifierKeys)
    /// A key went down, or repeats. `keyCode` is the macOS virtual key code; `modifiers` the event's own flags,
    /// so a modifier release the tap missed is found at the next key.
    case keyDown(keyCode: UInt16, modifiers: ModifierKeys, isRepeat: Bool)
    case keyUp(keyCode: UInt16, modifiers: ModifierKeys)
    /// The system had disabled the tap and it is back on; a release may have been missed. `modifiers` is the
    /// state now, `isChordKeyDown` whether the key of a held key chord (`heldChordKey`) is still down.
    case tapReenabled(modifiers: ModifierKeys, isChordKeyDown: Bool)
    /// The tap found the key of the held key chord (`heldChordKey`) up although no key-up came, for example
    /// after Secure Input took the keyboard: the press ended.
    case chordKeyReleased
    /// An event kotoba posted itself (its Cmd-V and Return): it passes and changes no state.
    case posted
}

/// The hotkey events for one keyboard event, stored inline so the tap callback does not allocate. One event
/// makes at most three: a missed key-up found as the chord is pressed again gives up, down and cleanup. A
/// fourth would be dropped, not crash the tap.
public struct HotkeyEvents: Sequence, Sendable, Equatable, ExpressibleByArrayLiteral {
    private var first: HotkeyEvent?
    private var second: HotkeyEvent?
    private var third: HotkeyEvent?
    private var count = 0

    public init() {}

    init(_ event: HotkeyEvent) {
        append(event)
    }

    /// For tests: a variadic list allocates, so the classifier uses the two inits above.
    public init(arrayLiteral events: HotkeyEvent...) {
        for event in events {
            append(event)
        }
    }

    mutating func append(_ event: HotkeyEvent) {
        switch count {
        case 0: first = event
        case 1: second = event
        case 2: third = event
        default: return
        }
        count += 1
    }

    public func makeIterator() -> Iterator {
        Iterator(events: self)
    }

    public struct Iterator: IteratorProtocol {
        let events: HotkeyEvents
        var index = 0

        public mutating func next() -> HotkeyEvent? {
            defer { index += 1 }
            switch index {
            case 0: return events.first
            case 1: return events.second
            case 2: return events.third
            default: return nil
            }
        }
    }
}

/// What the tap does with one keyboard event: the hotkey events to send, if any, and whether to
/// keep the key from the focused app.
public struct HotkeyDecision: Sendable, Equatable {
    /// In order; one modifier change can both press the chord and complete the cleanup chord.
    public var events: HotkeyEvents
    public var isSwallowed: Bool

    public init(events: HotkeyEvents, isSwallowed: Bool = false) {
        self.events = events
        self.isSwallowed = isSwallowed
    }

    public init(event: HotkeyEvent, isSwallowed: Bool = false) {
        self.init(events: HotkeyEvents(event), isSwallowed: isSwallowed)
    }

    public static let pass = Self(events: [])
    public static let swallow = Self(events: [], isSwallowed: true)
}

/// Turns raw keyboard events into hotkey events. The tap keeps one instance behind a lock and
/// calls `classify` for every event, so this stays constant-time and does not allocate.
///
/// A press lasts while the dictation chord or the cleanup chord is held: its start reports `.chordDown`, its end
/// `.chordUp`, and the first moment the cleanup chord is held reports `.cleanupModifier`. With the default chords
/// (⌃⌥⌘, and ⌃⌥⇧⌘ for cleanup) the cleanup chord is the dictation chord plus ⇧, pressed in any order; an unrelated
/// cleanup chord reports `.chordDown` and `.cleanupModifier` together. The pipeline decides the mode later.
public struct HotkeyClassifier: Sendable {
    /// On while the indicator shows recording. Esc then cancels, and with `isReturnGestureOn` a plain Return
    /// stops with a submit; neither key reaches the app.
    public var isRecordingShown = false
    /// Return while recording stops and presses Return after the paste (submit after paste).
    public var isReturnGestureOn: Bool
    /// On while a shortcut recorder listens: no chord counts, so the keys reach the recorder; a press in
    /// progress ends at the next keyboard event.
    public var isPaused = false
    public var dictationChord: Chord
    /// nil turns cleanup dictation off.
    public var cleanupChord: Chord?
    /// Set from a submit Return's key-down to its key-up: its repeats and key-up are swallowed too, also after
    /// recording ended in between.
    private var isSubmitKeyDown = false
    private var modifiers: ModifierKeys = []
    /// The key of a key chord now held. Its repeats and its release are swallowed, as its press was.
    public private(set) var heldChordKey: UInt16?
    private var isHeldKeyCleanup = false
    /// A press of either chord is in progress.
    public private(set) var isPressing = false
    /// Set at the first other key typed during one press.
    private var isInterrupted = false
    /// Set when the cleanup chord was held at some moment of this press.
    private var isCleanupSeen = false

    /// The chords are the owner's saved ones.
    public init(dictationChord: Chord = .defaultDictation, cleanupChord: Chord?, isReturnGestureOn: Bool = false) {
        self.isReturnGestureOn = isReturnGestureOn
        self.dictationChord = dictationChord
        self.cleanupChord = cleanupChord
    }

    /// A click on the indicator pill acts as a chord tap. While a chord is held it sends only the chord-down,
    /// so the real release sends the chord-up and the paste still waits for it.
    public func pillClick() -> HotkeyEvents {
        var events = HotkeyEvents(.chordDown)
        if !isPressing {
            events.append(.chordUp)
        }
        return events
    }

    public mutating func classify(_ input: KeyInput) -> HotkeyDecision {
        var events = HotkeyEvents()
        switch input {
        case .modifiersChanged(let held):
            modifiers = held
            update(&events)
            return HotkeyDecision(events: events)
        case .tapReenabled(let held, let isChordKeyDown):
            modifiers = held
            if !isChordKeyDown {
                heldChordKey = nil
            }
            isSubmitKeyDown = false
            update(&events)
            return HotkeyDecision(events: events)
        case .chordKeyReleased:
            guard heldChordKey != nil else { return .pass }
            heldChordKey = nil
            update(&events)
            return HotkeyDecision(events: events)
        case .posted:
            return .pass
        case .keyDown(let keyCode, let held, let isRepeat):
            sync(held, keyCode: keyCode, &events)
            return keyDown(keyCode, isRepeat: isRepeat, &events)
        case .keyUp(let keyCode, let held):
            sync(held, keyCode: keyCode, &events)
            if isSubmitKeyDown, keyCode == KeyCode.return {
                isSubmitKeyDown = false
                return HotkeyDecision(events: events, isSwallowed: true)
            }
            guard keyCode == heldChordKey else { return HotkeyDecision(events: events) }
            heldChordKey = nil
            update(&events)
            return HotkeyDecision(events: events, isSwallowed: true)
        }
    }

    private mutating func keyDown(_ keyCode: UInt16, isRepeat: Bool, _ events: inout HotkeyEvents) -> HotkeyDecision {
        if keyCode == heldChordKey {
            if isRepeat {
                return HotkeyDecision(events: events, isSwallowed: true)
            }
            // A new press of the chord key: its key-up was missed (sleep, secure input), so that press ended.
            heldChordKey = nil
            update(&events)
        }
        // A shortcut recorder that listens gets every key, Esc and Return included.
        guard !isPaused else { return HotkeyDecision(events: events) }
        if keyCode == KeyCode.escape, isRecordingShown {
            events.append(.escape)
            return HotkeyDecision(events: events, isSwallowed: true)
        }
        if keyCode == KeyCode.return, isReturnGestureOn {
            // A new press while the flag is on means the key-up was missed.
            if isSubmitKeyDown, isRepeat {
                return HotkeyDecision(events: events, isSwallowed: true)
            }
            isSubmitKeyDown = isRecordingShown && modifiers.isEmpty
            if isSubmitKeyDown {
                events.append(.submit)
                return HotkeyDecision(events: events, isSwallowed: true)
            }
        }
        if heldChordKey == nil {
            let isCleanup = cleanupChord?.isPressed(by: keyCode, with: modifiers) == true
            if isCleanup || dictationChord.isPressed(by: keyCode, with: modifiers) {
                heldChordKey = keyCode
                isHeldKeyCleanup = isCleanup
                update(&events)
                return HotkeyDecision(events: events, isSwallowed: true)
            }
        }
        // Another key typed during a press, Esc included, makes the press part of another app's shortcut.
        // The key still reaches the app.
        if isPressing, !isInterrupted {
            isInterrupted = true
            events.append(.chordInterrupted)
        }
        return HotkeyDecision(events: events)
    }

    /// Follows a key event's own flags, so a modifier change the tap missed cannot leave a chord down. Only which
    /// kinds are held is taken: the sides stay as the modifier events reported them, since a key event may carry no
    /// side bits. macOS sets the fn flag on arrows, function and navigation keys, so there fn stays as it was.
    private mutating func sync(_ held: ModifierKeys, keyCode: UInt16, _ events: inout HotkeyEvents) {
        var synced: ModifierKeys = []
        for kind in ModifierKeys.allKinds {
            let isFunctionMarked = kind == .function && KeyCode.carriesFunctionFlag(keyCode)
            let isHeld = isFunctionMarked ? !modifiers.isDisjoint(with: kind) : !held.isDisjoint(with: kind)
            guard isHeld else { continue }
            let tracked = modifiers.intersection(kind)
            synced.formUnion(tracked.isEmpty ? held.intersection(kind) : tracked)
        }
        guard synced != modifiers else { return }
        modifiers = synced
        update(&events)
    }

    private mutating func update(_ events: inout HotkeyEvents) {
        let isCleanupHeld = cleanupChord.map { isHeld($0, isCleanup: true) } ?? false
        let isHeld = !isPaused && (isCleanupHeld || isHeld(dictationChord, isCleanup: false))
        if isHeld, !isPressing {
            events.append(.chordDown)
            isInterrupted = false
            isCleanupSeen = false
        } else if !isHeld, isPressing {
            events.append(.chordUp)
        }
        isPressing = isHeld
        if isHeld, isCleanupHeld, !isCleanupSeen {
            isCleanupSeen = true
            events.append(.cleanupModifier)
        }
    }

    private func isHeld(_ chord: Chord, isCleanup: Bool) -> Bool {
        guard chord.keyCode != nil else { return chord.isHeld(by: modifiers) }
        return heldChordKey != nil && isHeldKeyCleanup == isCleanup
    }
}
