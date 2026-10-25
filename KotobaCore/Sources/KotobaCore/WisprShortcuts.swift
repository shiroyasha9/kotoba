/// Wispr Flow's two ways to dictate as kotoba chords, which onboarding's Welcome takes when it shows (owner QA 2, R1).
/// Wispr keeps its shortcuts in `prefs.user.shortcuts` of its `config.json`: macOS virtual key codes joined by "+",
/// each mapped to an action. "popo" is hands-free (Wispr records it as a locked dictation: `isLocked ? "popo" : "ptt"`
/// in its app bundle), "ptt" is push to talk; its other actions (paste_last_text, polish, lens, dismiss, …) are not
/// read. Only a chord kotoba can save is taken; for the other mode kotoba keeps its own chord.
public struct WisprShortcuts: Sendable, Equatable {
    /// What kotoba makes of Wispr Flow's keys for one mode.
    public enum Found: Sendable, Equatable {
        case usable(Chord)
        /// Wispr Flow has keys for this mode that kotoba cannot take: two keys, a double fn press, Wispr's aux button,
        /// or a chord kotoba refuses (`Chord.problem`).
        case unusable
    }

    /// nil: Wispr Flow has no keys for the mode.
    public var handsFree: Found?
    public var pushToTalk: Found?

    public init(handsFree: Found? = nil, pushToTalk: Found? = nil) {
        self.handsFree = handsFree
        self.pushToTalk = pushToTalk
    }

    /// `shortcuts` is Wispr Flow's `prefs.user.shortcuts`. Each chord must work with the owner's other kotoba chords:
    /// `handsFree` and `pushToTalk` (nil: the hands-free chord) stand in for a mode Wispr Flow gives no usable chord.
    /// Copy Last is left out: a dictation chord the owner saves turns its default off (`Chord.copyLast`).
    public init(
        shortcuts: [String: String], handsFree current: Chord, pushToTalk currentPushToTalk: Chord?, cleanup: Chord?,
        pasteLast: Chord?, polishLast: Chord?
    ) {
        func found(_ action: String) -> Found? {
            let keys = shortcuts.filter { $0.value == action }.keys.sorted()
            guard !keys.isEmpty else { return nil }
            // Wispr Flow can hold more than one chord for an action: the first kotoba can read, in a fixed order.
            return keys.lazy.compactMap(Self.chord(wisprKeys:)).first.map(Found.usable) ?? .unusable
        }
        var handsFree = found("popo")
        var pushToTalk = found("ptt")
        func problem(_ handsFree: Found?, _ pushToTalk: Found?) -> ChordProblem? {
            Chord.problem(
                handsFree: handsFree?.chord ?? current, pushToTalk: pushToTalk?.chord ?? currentPushToTalk,
                cleanup: cleanup, pasteLast: pasteLast, polishLast: polishLast)
        }
        if problem(handsFree, pushToTalk) != nil {
            // Hands-free comes first: it is kept when it works with kotoba's own push-to-talk chord, and push to talk
            // then goes. Else push to talk is kept when it works with kotoba's own hands-free chord.
            if handsFree?.chord != nil, problem(handsFree, nil) == nil {
                pushToTalk = .unusable
            } else {
                if handsFree?.chord != nil { handsFree = .unusable }
                if pushToTalk?.chord != nil, problem(nil, pushToTalk) != nil { pushToTalk = .unusable }
            }
        }
        self.init(handsFree: handsFree, pushToTalk: pushToTalk)
    }

    /// The chords to save, hands-free first.
    public var chords: [(ChordRole, Chord)] {
        [(ChordRole.handsFree, handsFree?.chord), (.pushToTalk, pushToTalk?.chord)].compactMap { role, chord in
            chord.map { (role, $0) }
        }
    }

    /// The chords Welcome takes when it shows (owner QA 2, R1): each usable one whose way to dictate still has
    /// kotoba's own chord (`handsFree` the default, `savedPushToTalk` nil), so a chord the owner changed stays.
    public func chordsToTake(handsFree: Chord, savedPushToTalk: Chord?) -> [(ChordRole, Chord)] {
        chords.filter { role, _ in role == .handsFree ? handsFree == .defaultHandsFree : savedPushToTalk == nil }
    }

    /// `chord`, the one `role` has now, is Wispr Flow's: Welcome says it was imported.
    public func isImported(_ role: ChordRole, chord: Chord?) -> Bool {
        chords.contains { $0 == role && $1 == chord }
    }

    /// One Wispr Flow shortcut ("55+58+59") as a chord: modifiers with at most one key or mouse button. Wispr's left
    /// modifier codes (and a plain ⇧, ⌥, ⌃, ⌘) become either side, as kotoba's own chords are; its right ones stay right
    /// only. Nil for keys kotoba cannot hold: two keys, Wispr's double fn (179) or aux button (65535).
    static func chord(wisprKeys: String) -> Chord? {
        var modifiers: ModifierKeys = []
        var trigger: Chord.Trigger?
        for part in wisprKeys.split(separator: "+") {
            guard let code = Int(part) else { return nil }
            if let modifier = modifierCodes[code] {
                modifiers.formUnion(modifier)
                continue
            }
            guard trigger == nil else { return nil }
            if wisprMouseButtons.contains(code) {
                trigger = .mouseButton(code - wisprMouseButtons.lowerBound + Chord.middleMouseButton)
            } else if (0...127).contains(code) {
                trigger = .key(UInt16(code))
            } else {
                return nil
            }
        }
        guard !modifiers.isEmpty || trigger != nil else { return nil }
        var chord = Chord(modifiers: modifiers)
        chord.trigger = trigger
        return chord
    }

    /// macOS's modifier key codes, as Wispr Flow writes them.
    private static let modifierCodes: [Int: ModifierKeys] = [
        55: .command, 54: .rightCommand, 58: .option, 61: .rightOption, 59: .control, 62: .rightControl,
        56: .shift, 60: .rightShift, 63: .function,
    ]

    /// Wispr Flow's middle button (4098) to its Mouse 10 (4105), in CoreGraphics' order from the middle button.
    private static let wisprMouseButtons = 4098...4105
}

extension WisprShortcuts.Found {
    public var chord: Chord? {
        guard case .usable(let chord) = self else { return nil }
        return chord
    }
}
