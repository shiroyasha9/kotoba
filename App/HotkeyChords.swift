import Carbon
import Foundation
import KotobaCore
import Observation

/// The owner's dictation and cleanup chords, saved in UserDefaults. Every text that names a chord reads it
/// here, so views redraw when the owner records a new one, and the hotkey tap follows each change at once.
@MainActor
@Observable
final class HotkeyChords {
    enum Role {
        case dictation
        case cleanup
    }

    static let shared = HotkeyChords(defaults: .standard)

    private(set) var dictation: Chord
    /// nil turns cleanup dictation off.
    private(set) var cleanup: Chord?
    /// On while a shortcut recorder listens: the tap ignores both chords, so the press reaches the recorder.
    var isRecording = false {
        didSet { apply() }
    }

    /// The tap, told about every change; `HotkeyTap.init` sets it.
    @ObservationIgnored var tap: HotkeyTap? {
        didSet { apply() }
    }
    /// nil for snapshots: nothing is read or saved.
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?, dictation: Chord = .defaultDictation, cleanup: Chord? = .defaultCleanup) {
        self.defaults = defaults
        self.dictation = defaults.flatMap { Self.load(Key.dictationChord, from: $0) }.flatMap { $0 } ?? dictation
        self.cleanup = defaults.flatMap { Self.load(Key.cleanupChord, from: $0) } ?? cleanup
    }

    func chord(_ role: Role) -> Chord? {
        role == .dictation ? dictation : cleanup
    }

    /// Saves `chord` (nil turns cleanup off) unless the pair cannot work; then returns why and keeps the old one.
    func save(_ chord: Chord?, as role: Role) -> ChordProblem? {
        let pair = role == .dictation ? (chord ?? .defaultDictation, cleanup) : (dictation, chord)
        if let problem = Chord.problem(dictation: pair.0, cleanup: pair.1) {
            return problem
        }
        (dictation, cleanup) = pair
        defaults?.set(dictation.storedValue, forKey: Key.dictationChord.rawValue)
        defaults?.set(cleanup?.storedValue ?? Self.off, forKey: Key.cleanupChord.rawValue)
        apply()
        return nil
    }

    private func apply() {
        tap?.setChords(dictation: dictation, cleanup: cleanup, isPaused: isRecording)
    }

    private typealias Key = AppDefaults.Key
    private static let off = "off"

    /// A missing or unreadable value gives nil, so the default applies; "off" gives `.some(nil)`.
    private static func load(_ key: Key, from defaults: UserDefaults) -> Chord?? {
        guard let value = defaults.string(forKey: key.rawValue) else { return nil }
        switch value {
        case off: return .some(nil)
        // Before the recorder, the cleanup chord was a choice of three.
        case "shift": return .some(.defaultCleanup)
        case "function": return .some(Chord(modifiers: [.function, .control, .option, .command]))
        default: return Chord(storedValue: value).map { .some($0) }
        }
    }
}

extension Chord {
    /// "<modifiers>" or "<modifiers>:<key code>", as decimal numbers.
    var storedValue: String {
        keyCode.map { "\(modifiers.rawValue):\($0)" } ?? "\(modifiers.rawValue)"
    }

    init?(storedValue: String) {
        let parts = storedValue.split(separator: ":")
        guard let raw = parts.first.flatMap({ UInt16($0) }), parts.count <= 2 else { return nil }
        let keyCode = parts.count == 2 ? UInt16(parts[1]) : nil
        if parts.count == 2, keyCode == nil { return nil }
        self.init(modifiers: ModifierKeys(rawValue: raw), keyCode: keyCode)
    }

    /// The chord in key symbols, as menus and buttons show it: "⌃⌥⌘", "fn", "right ⌥", "⌥Space".
    var title: String {
        let parts = modifierParts(symbol: \.symbol)
        let modifiers = parts.contains { $0.contains(" ") } ? parts.joined(separator: " ") : parts.joined()
        guard let keyCode else { return modifiers }
        return modifiers + Self.keyName(keyCode)
    }

    /// Whether `title` shows a symbol (⌃ ⌥ ⇧ ⌘ or a key such as ↩) that `spokenTitle` spells out.
    var hasSymbols: Bool {
        !modifiers.kinds.subtracting(.function).isEmpty || keyCode.map { Self.specialKeys[Int($0)]?.count == 1 } == true
    }

    /// The chord in words, once in onboarding: "Control-Option-Command", "right Option", "Option-Space".
    var spokenTitle: String {
        (modifierParts(symbol: \.name) + (keyCode.map { [Self.keyName($0)] } ?? [])).joined(separator: "-")
    }

    private func modifierParts(symbol: KeyPath<ModifierKeys, String>) -> [String] {
        ModifierKeys.allKinds.compactMap { kind in
            let sides = modifiers.intersection(kind)
            guard !sides.isEmpty else { return nil }
            let side = sides == kind ? "" : sides.isSubset(of: .rightSides) ? "right " : "left "
            return side + kind[keyPath: symbol]
        }
    }

    /// Names a key as the current keyboard layout types it: "K", "Space", "F5", "↩".
    private static func keyName(_ keyCode: UInt16) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        return typedCharacter(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20", kVK_ANSI_KeypadEnter: "⌤",
    ]

    /// What the key types with no modifier in the current layout.
    private static func typedCharacter(_ keyCode: UInt16) -> String? {
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { bytes -> String? in
            guard let layout = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }
}

extension ModifierKeys {
    /// Called on one kind with both sides (`ModifierKeys.allKinds`).
    var symbol: String {
        switch self {
        case .function: "fn"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        default: "⌘"
        }
    }

    var name: String {
        switch self {
        case .function: "Fn"
        case .control: "Control"
        case .option: "Option"
        case .shift: "Shift"
        default: "Command"
        }
    }
}
