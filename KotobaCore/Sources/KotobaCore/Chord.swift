/// A shortcut the owner records: modifiers alone (⌃⌥⌘, fn, right ⌥) or modifiers with one key (⌥Space).
public struct Chord: Sendable, Hashable {
    /// For each modifier kind in the chord, the sides that count: both sides set means either side.
    public var modifiers: ModifierKeys
    /// The macOS virtual key code pressed with the modifiers; nil for a modifier-only chord.
    public var keyCode: UInt16?

    public init(modifiers: ModifierKeys, keyCode: UInt16? = nil) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// Hands-free, and push to talk until the owner records its own.
    public static let defaultHandsFree = Self(modifiers: [.control, .option, .command])
    /// A Caps Lock "Hyper" key also presses all four, in any order.
    public static let defaultCleanup = Self(modifiers: [.control, .option, .shift, .command])

    /// A modifier-only chord is down while all of its modifiers are; other modifiers held with it do not matter.
    func isHeld(by held: ModifierKeys) -> Bool {
        keyCode == nil && modifiers.isSatisfied(by: held)
    }

    /// A key chord is pressed when its key goes down with exactly its modifier kinds held, so ⌥⇧Space is not ⌥Space.
    func isPressed(by pressed: UInt16, with held: ModifierKeys) -> Bool {
        pressed == keyCode && held.kinds == modifiers.kinds && modifiers.isSatisfied(by: held)
    }

    /// How many keys the chord holds: when two chords are held at once, the press follows the one with more.
    var rank: Int {
        modifiers.kindCount + (keyCode == nil ? 0 : 1)
    }
}

/// What a chord does: start a dictation hands-free or push to talk, start a cleanup dictation, or paste the last
/// dictation again.
public enum ChordRole: Sendable, Hashable {
    case handsFree
    case pushToTalk
    case cleanup
    case pasteLast
}

/// Why a recorded chord is refused.
public enum ChordProblem: Sendable, Equatable {
    /// A key with no ⌃, ⌥, ⌘ or fn (⇧ alone types a capital): the key would stop typing.
    case noModifier
    /// One left or either-side ⌃, ⌥, ⇧ or ⌘ alone: it is part of most shortcuts and of typing. Push to talk may use ⌃
    /// or ⌥ alone: a shortcut press is shorter than the hold threshold, so it is dropped. ⇧ and ⌘ stay refused: they
    /// are held longer than the threshold, while typing capitals and while pausing before a shortcut.
    case commonModifierAlone
    /// Exactly two modifiers, one of them ⌘ (⌘⇧, ⌥⌘, ⌃⌘, fn⌘): many app shortcuts start with them, and the mic
    /// would open for a moment on each. Push to talk too: ⌘ is held while the owner pauses before a shortcut.
    case commandPair
    /// macOS or kotoba itself uses it: Spotlight, the app switcher, screenshots, ⌘V for the paste.
    case reserved
    /// Esc cancels a dictation.
    case escape
    /// The cleanup chord is the dictation chord of `role` (hands-free or push to talk). The two dictation chords may
    /// be one chord.
    case sameAsCleanup(ChordRole)
    /// Each press of the dictation chord of `role` also completes the cleanup chord, so no dictation could skip
    /// cleanup.
    case dictationIncludesCleanup(ChordRole)
    /// The Paste Last chord has no key: modifiers alone would paste each time they are pressed for another shortcut.
    case needsKey
    /// The Paste Last chord is the chord of `role` (hands-free, push to talk or cleanup).
    case pasteLastSameAs(ChordRole)
    /// The Paste Last chord holds the modifier-only chord of `role` on the way to its key, so it would start a
    /// dictation first. Its key is not another key typed during that press, so nothing drops the dictation.
    case pasteLastIncludes(ChordRole)
}

extension Chord {
    /// One or two modifiers alone (fn has its own note): an app shortcut that uses them opens the mic for a moment
    /// before the press is dropped. The recorder says so.
    public var opensMicBriefly: Bool {
        keyCode == nil && modifiers != .function && (1...2).contains(modifiers.kindCount)
    }

    /// The first reason the chords cannot be saved, or nil. A chord's own problem comes before a clash. A nil
    /// `pushToTalk` is the hands-free chord.
    ///
    /// A cleanup or hands-free chord may hold the push-to-talk chord on the way (⌃⌥⇧⌘ holds ⌥): the press follows the
    /// chord with more keys before the dictation shows (`HotkeyClassifier`), as cleanup follows ⇧ today.
    public static func problem(
        handsFree: Chord, pushToTalk: Chord? = nil, cleanup: Chord?, pasteLast: Chord? = nil
    ) -> ChordProblem? {
        if let problem = handsFree.ownProblem(as: .handsFree) { return problem }
        if let problem = pushToTalk?.ownProblem(as: .pushToTalk) { return problem }
        let dictation = [(handsFree, ChordRole.handsFree)] + (pushToTalk.map { [($0, .pushToTalk)] } ?? [])
        if let cleanup {
            if let problem = cleanup.ownProblem(as: .cleanup) { return problem }
            for (chord, role) in dictation {
                if chord == cleanup { return .sameAsCleanup(role) }
                if cleanup.keyCode == nil, cleanup.modifiers.isImplied(by: chord.modifiers) {
                    return .dictationIncludesCleanup(role)
                }
            }
        }
        guard let pasteLast else { return nil }
        guard pasteLast.keyCode != nil else { return .needsKey }
        return pasteLast.ownProblem(as: .pasteLast) ?? pasteLast.clash(with: dictation + [(cleanup, .cleanup)])
    }

    /// The push-to-talk chord to keep after the owner saves `chord` (nil: Reset) as `role`; nil is the hands-free
    /// chord. Push to talk saved as the hands-free chord, or reset, keeps none, so it follows the hands-free chord. A
    /// push-to-talk chord the owner set stays when the hands-free chord changes, even to the same chord.
    public static func pushToTalk(afterSaving chord: Chord?, as role: ChordRole, handsFree: Chord, kept: Chord?)
        -> Chord?
    {
        guard role == .pushToTalk else { return kept }
        return chord == handsFree ? nil : chord
    }

    /// How this Paste Last chord clashes with a dictation or cleanup chord. The classifier tries those first, so a key
    /// press that matches one, or that holds one of them on the way, never reaches Paste Last.
    private func clash(with others: [(Chord?, ChordRole)]) -> ChordProblem? {
        for (other, role) in others {
            guard let other else { continue }
            if other.keyCode == nil, other.modifiers.isSatisfied(by: modifiers) { return .pasteLastIncludes(role) }
            if other.keyCode == keyCode, other.modifiers.kinds == modifiers.kinds { return .pasteLastSameAs(role) }
        }
        return nil
    }

    private func ownProblem(as role: ChordRole) -> ChordProblem? {
        guard let keyCode else {
            if modifiers.isEmpty { return .noModifier }
            let isOneKind = ModifierKeys.allKinds.contains(modifiers.kinds)
            let isRightOnly = modifiers.isSubset(of: .rightSides)
            // Push to talk drops a shortcut press, shorter than the hold threshold, so ⌥ or ⌃ alone can be its chord.
            // ⇧ and ⌘ are held longer: while typing capitals, and while pausing before a shortcut.
            let isHeldLong = !modifiers.isDisjoint(with: [.shift, .command])
            if isOneKind, modifiers != .function, !isRightOnly, role != .pushToTalk || isHeldLong {
                return .commonModifierAlone
            }
            let isCommandPair = modifiers.kindCount == 2 && !modifiers.isDisjoint(with: .command)
            return isCommandPair && !isRightOnly ? .commandPair : nil
        }
        if keyCode == KeyCode.escape { return .escape }
        if modifiers.kinds.subtracting(.shift).isEmpty { return .noModifier }
        let isReserved = Self.reserved.contains { $0.keyCode == keyCode && $0.modifiers == modifiers.kinds }
        return isReserved ? .reserved : nil
    }

    /// System and kotoba shortcuts a chord must not take, whatever side the modifiers are on.
    private static let reserved: [Chord] = [
        Chord(modifiers: .command, keyCode: KeyCode.space),
        Chord(modifiers: .control, keyCode: KeyCode.space),
        Chord(modifiers: [.control, .option], keyCode: KeyCode.space),
        Chord(modifiers: [.control, .command], keyCode: KeyCode.space),
        Chord(modifiers: [.option, .command], keyCode: KeyCode.space),
        Chord(modifiers: .command, keyCode: KeyCode.tab),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.tab),
        Chord(modifiers: .command, keyCode: KeyCode.grave),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.grave),
        Chord(modifiers: .command, keyCode: KeyCode.ansiQ),
        Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiQ),
        Chord(modifiers: .command, keyCode: KeyCode.ansiW),
        Chord(modifiers: .command, keyCode: KeyCode.ansiH),
        Chord(modifiers: [.option, .command], keyCode: KeyCode.ansiH),
        Chord(modifiers: .command, keyCode: KeyCode.ansiM),
        Chord(modifiers: .command, keyCode: KeyCode.ansiA),
        Chord(modifiers: .command, keyCode: KeyCode.ansiC),
        Chord(modifiers: .command, keyCode: KeyCode.ansiV),
        Chord(modifiers: .command, keyCode: KeyCode.ansiX),
        Chord(modifiers: .command, keyCode: KeyCode.ansiZ),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansiZ),
        Chord(modifiers: [.control, .command], keyCode: KeyCode.ansiF),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansi3),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansi4),
        Chord(modifiers: [.shift, .command], keyCode: KeyCode.ansi5),
        Chord(modifiers: [.control, .shift, .command], keyCode: KeyCode.ansi3),
        Chord(modifiers: [.control, .shift, .command], keyCode: KeyCode.ansi4),
    ]
}

/// The macOS virtual key codes (Carbon's `kVK_*`) that the rules name; this module does not link Carbon.
public enum KeyCode {
    public static let ansiA: UInt16 = 0x00
    public static let ansiH: UInt16 = 0x04
    public static let ansiZ: UInt16 = 0x06
    public static let ansiX: UInt16 = 0x07
    public static let ansiC: UInt16 = 0x08
    public static let ansiV: UInt16 = 0x09
    public static let ansiF: UInt16 = 0x03
    public static let ansiQ: UInt16 = 0x0C
    public static let ansiW: UInt16 = 0x0D
    public static let ansi3: UInt16 = 0x14
    public static let ansi4: UInt16 = 0x15
    public static let ansi5: UInt16 = 0x17
    public static let ansiM: UInt16 = 0x2E
    public static let tab: UInt16 = 0x30
    public static let space: UInt16 = 0x31
    public static let grave: UInt16 = 0x32
    public static let `return`: UInt16 = 0x24
    public static let escape: UInt16 = 0x35

    /// Keys whose events macOS marks with the fn flag although fn is up: arrows, F1-F20, Help, Home, End, Page Up,
    /// Page Down and Forward Delete.
    static func carriesFunctionFlag(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 0x7B...0x7E, 0x72...0x79, 0x7A, 0x60...0x65, 0x67, 0x69...0x6B, 0x6D, 0x6F, 0x71, 0x40, 0x4F, 0x50, 0x5A:
            true
        default: false
        }
    }
}

/// What the shortcut recorder makes of the keys pressed while it listens. Modifiers alone are recorded when the
/// last one goes up, as the most that were down at once; a key is recorded as it goes down, with the modifiers
/// held then. A side counts only when the right key alone was used: left ⌥ or both make "either ⌥".
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
        case .keyUp, .chordKeyReleased, .posted, .mouseDown:
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
