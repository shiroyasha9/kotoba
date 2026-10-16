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
    /// A mouse button went down (left, right or other): a ⌘-click or ⌥-drag makes a press part of a mouse gesture, as
    /// a typed key does.
    case mouseDown
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
/// A press lasts while the hands-free, push-to-talk or cleanup chord is held: its start reports `.chordDown`, its
/// end `.chordUp`, and the first moment the cleanup chord is held reports `.cleanupModifier`. With the default chords
/// (⌃⌥⌘, and ⌃⌥⇧⌘ for cleanup) the cleanup chord is the dictation chord plus ⇧, pressed in any order; an unrelated
/// cleanup chord reports `.chordDown` and `.cleanupModifier` together. The pipeline decides the mode later.
///
/// The press follows the chord held with the most keys (`Chord.rank`), so a chord reached through another one on the
/// way wins: with ⌥ for push to talk and ⌃⌥⌘ hands-free, ⌥ first reports `.chordDown(.hold)`, and ⌃ and ⌘ after it
/// `.gestureChanged(.toggle)`. A press never goes back to a chord with fewer keys.
///
/// The Paste Last and Polish Last chords (a key with modifiers) report `.pasteLast` and `.polishLast` once every
/// modifier is up again: a Cmd-V posted while ⌃ is held reaches the app as ⌃⌘V. The Copy Last chord posts no key, so it
/// reports `.copyLast` at its press.
public struct HotkeyClassifier: Sendable {
    /// On while the indicator shows recording. Esc then cancels, and with `isReturnGestureOn` a plain Return
    /// stops with a submit; neither key reaches the app.
    public var isRecordingShown = false
    /// Return while recording stops and presses Return after the paste (submit after paste).
    public var isReturnGestureOn: Bool
    /// On while a shortcut recorder listens: no chord counts, so the keys reach the recorder; a press in
    /// progress ends at the next keyboard event.
    public var isPaused = false
    public var handsFreeChord: Chord
    /// nil, or the hands-free chord: that one chord does both (`ChordGesture.tapOrHold`).
    public var pushToTalkChord: Chord?
    /// nil turns cleanup dictation off.
    public var cleanupChord: Chord?
    /// nil, the default, leaves Paste Last to the menu.
    public var pasteLastChord: Chord?
    /// nil leaves Copy Last to the menu.
    public var copyLastChord: Chord?
    /// nil, the default, leaves Polish Last to the menu.
    public var polishLastChord: Chord?
    /// Set from a submit Return's key-down to its key-up: its repeats and key-up are swallowed too, also after
    /// recording ended in between.
    private var isSubmitKeyDown = false
    private(set) var modifiers: ModifierKeys = []
    /// The key chord now held. Its key's repeats and its release are swallowed, as its press was.
    private(set) var heldKeyChord: Chord?
    /// The chord the press in progress follows; nil when no press is.
    private var press: RankedGesture?
    /// Set at the first other key typed during one press.
    private var isInterrupted = false
    /// Set when the cleanup chord was held at some moment of this press.
    private var isCleanupSeen = false
    /// The Paste Last, Copy Last and Polish Last keys, each from its press to its key-up: its repeats and key-up are
    /// swallowed, as its press was. Apart, so pressing one while another is down keeps both swallowed.
    private var pasteLastKey: UInt16?
    private var copyLastKey: UInt16?
    private var polishLastKey: UInt16?
    /// `.pasteLast` or `.polishLast`, set at its press until every modifier is up (then sent) or another key or a
    /// chord press cancels it.
    private var dueAtRelease: HotkeyEvent?

    /// The chords are the owner's saved ones.
    public init(
        handsFreeChord: Chord = .defaultHandsFree, pushToTalkChord: Chord? = nil, cleanupChord: Chord?,
        pasteLastChord: Chord? = nil, copyLastChord: Chord? = nil, polishLastChord: Chord? = nil,
        isReturnGestureOn: Bool = false
    ) {
        self.isReturnGestureOn = isReturnGestureOn
        self.copyLastChord = copyLastChord
        self.polishLastChord = polishLastChord
        self.handsFreeChord = handsFreeChord
        self.pushToTalkChord = pushToTalkChord
        self.cleanupChord = cleanupChord
        self.pasteLastChord = pasteLastChord
    }

    /// The key of the key chord now held, for the tap to check a lost key-up.
    public var heldChordKey: UInt16? { heldKeyChord?.keyCode }

    /// A press of any chord is in progress.
    public var isPressing: Bool { press != nil }

    /// A saved chord has a key, so the tap needs key-up events.
    public var hasKeyChord: Bool {
        handsFreeChord.keyCode != nil || pushToTalkChord?.keyCode != nil || cleanupChord?.keyCode != nil
            || pasteLastChord != nil || copyLastChord != nil || polishLastChord != nil
    }

    /// A click on the indicator pill acts as a hands-free tap. While a chord is held it sends only the chord-down,
    /// so the real release sends the chord-up and the paste still waits for it.
    public func pillClick() -> HotkeyEvents {
        var events = HotkeyEvents(.chordDown(.toggle))
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
                heldKeyChord = nil
            }
            isSubmitKeyDown = false
            update(&events)
            return HotkeyDecision(events: events)
        case .chordKeyReleased:
            guard heldKeyChord != nil else { return .pass }
            heldKeyChord = nil
            update(&events)
            return HotkeyDecision(events: events)
        case .posted:
            return .pass
        case .mouseDown:
            interrupt(&events)
            return HotkeyDecision(events: events)
        case .keyDown(let keyCode, let held, let isRepeat):
            sync(held, keyCode: keyCode, &events)
            return keyDown(keyCode, isRepeat: isRepeat, &events)
        case .keyUp(let keyCode, let held):
            sync(held, keyCode: keyCode, &events)
            return keyUp(keyCode, &events)
        }
    }

    /// The key-up of a submit Return, the Paste Last, Copy Last or Polish Last key or a held chord key is swallowed, as its
    /// press was.
    private mutating func keyUp(_ keyCode: UInt16, _ events: inout HotkeyEvents) -> HotkeyDecision {
        if isSubmitKeyDown, keyCode == KeyCode.return {
            isSubmitKeyDown = false
        } else if keyCode == pasteLastKey {
            pasteLastKey = nil
        } else if keyCode == copyLastKey {
            copyLastKey = nil
        } else if keyCode == polishLastKey {
            polishLastKey = nil
        } else if keyCode == heldChordKey {
            heldKeyChord = nil
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
        // Paste Last and Polish Last wait for their modifiers; a key typed meanwhile makes them part of another shortcut.
        dueAtRelease = nil
        // Another key typed during a press, Esc included, makes the press part of another app's shortcut.
        // The key still reaches the app.
        interrupt(&events)
        return HotkeyDecision(events: events)
    }

    /// A key or a click during a press, the first one only.
    private mutating func interrupt(_ events: inout HotkeyEvents) {
        guard isPressing, !isInterrupted else { return }
        isInterrupted = true
        events.append(.chordInterrupted)
    }

    /// Whether `keyCode`, the key of a chord held, repeats: its repeats are swallowed, as its press was. A new press
    /// of it means its key-up was missed (sleep, secure input), so that press ended.
    private mutating func isHeldKeyRepeat(_ keyCode: UInt16, isRepeat: Bool, _ events: inout HotkeyEvents) -> Bool {
        guard keyCode == heldChordKey || keyCode == pasteLastKey || keyCode == copyLastKey || keyCode == polishLastKey
        else { return false }
        if isRepeat { return true }
        if keyCode == heldChordKey {
            heldKeyChord = nil
            update(&events)
        }
        if keyCode == pasteLastKey {
            pasteLastKey = nil
        }
        if keyCode == copyLastKey {
            copyLastKey = nil
        }
        if keyCode == polishLastKey {
            polishLastKey = nil
        }
        return false
    }

    /// Holds the hands-free, push-to-talk or cleanup key chord, makes Paste Last or Polish Last due, or copies the last
    /// dictation; false when `keyCode` with the modifiers held is none of them.
    private mutating func pressKeyChord(_ keyCode: UInt16, _ events: inout HotkeyEvents) -> Bool {
        if let chord = keyChord(pressedBy: keyCode) {
            heldKeyChord = chord
            update(&events)
            return true
        }
        if copyLastChord?.isPressed(by: keyCode, with: modifiers) == true {
            copyLastKey = keyCode
            // A Paste Last that waits for its modifiers is part of this other shortcut now, as after any other key.
            dueAtRelease = nil
            events.append(.copyLast)
            return true
        }
        if polishLastChord?.isPressed(by: keyCode, with: modifiers) == true {
            polishLastKey = keyCode
            dueAtRelease = .polishLast
            return true
        }
        guard pasteLastChord?.isPressed(by: keyCode, with: modifiers) == true else { return false }
        pasteLastKey = keyCode
        dueAtRelease = .pasteLast
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

    /// The chord whose key `keyCode` is, pressed with exactly its modifiers: cleanup first, as before the split.
    private func keyChord(pressedBy keyCode: UInt16) -> Chord? {
        if let cleanupChord, cleanupChord.isPressed(by: keyCode, with: modifiers) { return cleanupChord }
        if let pushToTalkChord, pushToTalkChord.isPressed(by: keyCode, with: modifiers) { return pushToTalkChord }
        return handsFreeChord.isPressed(by: keyCode, with: modifiers) ? handsFreeChord : nil
    }

    private mutating func update(_ events: inout HotkeyEvents) {
        let held = isPaused ? nil : strongestHeld()
        switch (held, press) {
        case (let held?, nil):
            events.append(.chordDown(held.gesture))
            press = held
            isInterrupted = false
            isCleanupSeen = false
            dueAtRelease = nil
        case (let held?, let current?) where held.rank > current.rank:
            press = held
            if held.gesture != current.gesture {
                events.append(.gestureChanged(held.gesture))
            }
        case (nil, _?):
            events.append(.chordUp)
            press = nil
        default: break
        }
        let isCleanupHeld = !isPaused && cleanupChord.map(isHeld) == true
        if isCleanupHeld, !isCleanupSeen {
            isCleanupSeen = true
            events.append(.cleanupModifier)
        }
        if let due = dueAtRelease, modifiers.isEmpty {
            dueAtRelease = nil
            if !isPaused { events.append(due) }
        }
    }
}
