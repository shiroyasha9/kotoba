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

    public static let defaultDictation = Self(modifiers: [.control, .option, .command])
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
}

/// Why a recorded chord is refused.
public enum ChordProblem: Sendable, Equatable {
    /// A key with no ⌃, ⌥, ⌘ or fn (⇧ alone types a capital): the key would stop typing.
    case noModifier
    /// One left or either-side ⌃, ⌥, ⇧ or ⌘ alone: it is part of most shortcuts and of typing.
    case commonModifierAlone
    /// Exactly two modifiers, one of them ⌘ (⌘⇧, ⌥⌘, ⌃⌘, fn⌘): many app shortcuts start with them, and the mic
    /// would open for a moment on each.
    case commandPair
    /// macOS or kotoba itself uses it: Spotlight, the app switcher, screenshots, ⌘V for the paste.
    case reserved
    /// Esc cancels a dictation.
    case escape
    /// It is the other chord.
    case sameAsOther
    /// Each press of the dictation chord also completes the cleanup chord, so no dictation could skip cleanup.
    case dictationIncludesCleanup
}

extension Chord {
    /// Two modifiers alone: an app shortcut that starts with them opens the mic for a moment before the press is
    /// discarded. The recorder says so.
    public var opensMicBriefly: Bool {
        keyCode == nil && modifiers.kindCount == 2
    }

    /// The first reason the pair cannot be saved, or nil. A chord's own problem comes before a clash.
    public static func problem(dictation: Chord, cleanup: Chord?) -> ChordProblem? {
        if let problem = dictation.ownProblem { return problem }
        guard let cleanup else { return nil }
        if let problem = cleanup.ownProblem { return problem }
        if dictation == cleanup { return .sameAsOther }
        if cleanup.keyCode == nil, cleanup.modifiers.isImplied(by: dictation.modifiers) {
            return .dictationIncludesCleanup
        }
        return nil
    }

    private var ownProblem: ChordProblem? {
        guard let keyCode else {
            if modifiers.isEmpty { return .noModifier }
            let isOneKind = ModifierKeys.allKinds.contains(modifiers.kinds)
            let isRightOnly = modifiers.isSubset(of: .rightSides)
            if isOneKind, modifiers != .function, !isRightOnly { return .commonModifierAlone }
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
        case .keyUp, .chordKeyReleased, .posted:
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
