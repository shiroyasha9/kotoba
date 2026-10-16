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
///
/// The Paste Last chord (a key with modifiers) reports `.pasteLast` once every modifier is up again: a Cmd-V posted
/// while ⌃ is held reaches the app as ⌃⌘V.
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
    /// nil, the default, leaves Paste Last to the menu.
    public var pasteLastChord: Chord?
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
    /// The Paste Last key, from its press to its key-up: its repeats and key-up are swallowed, as its press was.
    private var pasteLastKey: UInt16?
    /// Set at the Paste Last press until every modifier is up (`.pasteLast`) or another key or a chord press cancels it.
    private var isPasteLastDue = false

    /// The chords are the owner's saved ones.
    public init(
        dictationChord: Chord = .defaultDictation, cleanupChord: Chord?, pasteLastChord: Chord? = nil,
        isReturnGestureOn: Bool = false
    ) {
        self.isReturnGestureOn = isReturnGestureOn
        self.dictationChord = dictationChord
        self.cleanupChord = cleanupChord
        self.pasteLastChord = pasteLastChord
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
            return keyUp(keyCode, &events)
        }
    }

    /// The key-up of a submit Return, the Paste Last key or a held chord key is swallowed, as its press was.
    private mutating func keyUp(_ keyCode: UInt16, _ events: inout HotkeyEvents) -> HotkeyDecision {
        if isSubmitKeyDown, keyCode == KeyCode.return {
            isSubmitKeyDown = false
        } else if keyCode == pasteLastKey {
            pasteLastKey = nil
        } else if keyCode == heldChordKey {
            heldChordKey = nil
            update(&events)
        } else {
            return HotkeyDecision(events: events)
        }
        return HotkeyDecision(events: events, isSwallowed: true)
    }

    private mutating func keyDown(_ keyCode: UInt16, isRepeat: Bool, _ events: inout HotkeyEvents) -> HotkeyDecision {
        if isHeldKeyRepeat(keyCode, isRepeat: isRepeat, &events) {
            return HotkeyDecision(events: events, isSwallowed: true)
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
        if heldChordKey == nil, pressKeyChord(keyCode, &events) {
            return HotkeyDecision(events: events, isSwallowed: true)
        }
        // Paste Last waits for its modifiers; a key typed meanwhile makes them part of another shortcut.
        isPasteLastDue = false
        // Another key typed during a press, Esc included, makes the press part of another app's shortcut.
        // The key still reaches the app.
        if isPressing, !isInterrupted {
            isInterrupted = true
            events.append(.chordInterrupted)
        }
        return HotkeyDecision(events: events)
    }

    /// Whether `keyCode`, the key of a chord held, repeats: its repeats are swallowed, as its press was. A new press
    /// of it means its key-up was missed (sleep, secure input), so that press ended.
    private mutating func isHeldKeyRepeat(_ keyCode: UInt16, isRepeat: Bool, _ events: inout HotkeyEvents) -> Bool {
        guard keyCode == heldChordKey || keyCode == pasteLastKey else { return false }
        if isRepeat { return true }
        if keyCode == heldChordKey {
            heldChordKey = nil
            update(&events)
        }
        if keyCode == pasteLastKey {
            pasteLastKey = nil
        }
        return false
    }

    /// Starts a press of the dictation or cleanup key chord, or makes Paste Last due; false when `keyCode` with the
    /// modifiers held is none of them.
    private mutating func pressKeyChord(_ keyCode: UInt16, _ events: inout HotkeyEvents) -> Bool {
        let isCleanup = cleanupChord?.isPressed(by: keyCode, with: modifiers) == true
        if isCleanup || dictationChord.isPressed(by: keyCode, with: modifiers) {
            heldChordKey = keyCode
            isHeldKeyCleanup = isCleanup
            update(&events)
            return true
        }
        guard pasteLastChord?.isPressed(by: keyCode, with: modifiers) == true else { return false }
        pasteLastKey = keyCode
        isPasteLastDue = true
        return true
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
            isPasteLastDue = false
        } else if !isHeld, isPressing {
            events.append(.chordUp)
        }
        isPressing = isHeld
        if isHeld, isCleanupHeld, !isCleanupSeen {
            isCleanupSeen = true
            events.append(.cleanupModifier)
        }
        if isPasteLastDue, modifiers.isEmpty {
            isPasteLastDue = false
            if !isPaused { events.append(.pasteLast) }
        }
    }

    private func isHeld(_ chord: Chord, isCleanup: Bool) -> Bool {
        guard chord.keyCode != nil else { return chord.isHeld(by: modifiers) }
        return heldChordKey != nil && isHeldKeyCleanup == isCleanup
    }
}
