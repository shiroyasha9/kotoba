import Carbon
import Foundation
import KotobaCore
import Observation

/// The owner's hands-free, push-to-talk, cleanup and Paste Last chords, saved in UserDefaults. Every text that names a
/// chord reads it here, so views redraw when the owner records a new one, and the hotkey tap follows each change at once.
@MainActor
@Observable
final class HotkeyChords {
    typealias Role = ChordRole

    static let shared = HotkeyChords(defaults: .standard)

    private(set) var handsFree: Chord
    /// The push-to-talk chord the owner recorded; nil (the default) uses the hands-free chord and follows a new one.
    /// A recorded chord stays when the hands-free chord changes (`Chord.pushToTalk(afterSaving:as:handsFree:kept:)`).
    private(set) var savedPushToTalk: Chord?
    /// nil turns cleanup dictation off.
    private(set) var cleanup: Chord?
    /// Unset (nil) by default: a default chord could take a shortcut another app uses. The menu item works without it.
    private(set) var pasteLast: Chord?
    /// On while a shortcut recorder listens: the tap ignores every chord, so the press reaches the recorder.
    var isRecording = false {
        didSet { apply() }
    }

    /// The tap, told about every change; `HotkeyTap.init` sets it.
    @ObservationIgnored var tap: HotkeyTap? {
        didSet { apply() }
    }
    /// nil for snapshots: nothing is read or saved.
    @ObservationIgnored private let defaults: UserDefaults?

    init(
        defaults: UserDefaults?, handsFree: Chord = .defaultHandsFree, pushToTalk: Chord? = nil,
        cleanup: Chord? = .defaultCleanup, pasteLast: Chord? = nil
    ) {
        self.defaults = defaults
        self.handsFree = defaults.flatMap { Self.load(Key.handsFreeChord, from: $0) }.flatMap { $0 } ?? handsFree
        savedPushToTalk = defaults.flatMap { Self.load(Key.pushToTalkChord, from: $0) }.flatMap { $0 } ?? pushToTalk
        self.cleanup = defaults.flatMap { Self.load(Key.cleanupChord, from: $0) } ?? cleanup
        self.pasteLast = defaults.flatMap { Self.load(Key.pasteLastChord, from: $0) } ?? pasteLast
    }

    var pushToTalk: Chord { savedPushToTalk ?? handsFree }

    /// Push to talk while it is another chord than hands-free; nil while one chord does both, as before the split (tap
    /// to toggle, hold for push to talk).
    var separatePushToTalk: Chord? { pushToTalk == handsFree ? nil : pushToTalk }

    func chord(_ role: Role) -> Chord? {
        switch role {
        case .handsFree: handsFree
        case .pushToTalk: pushToTalk
        case .cleanup: cleanup
        case .pasteLast: pasteLast
        }
    }

    /// Saves `chord` (nil turns cleanup or Paste Last off, and gives push to talk the hands-free chord) unless the
    /// chords cannot work together; then returns why and keeps the old one.
    func save(_ chord: Chord?, as role: Role) -> ChordProblem? {
        var new = (handsFree: handsFree, pushToTalk: savedPushToTalk, cleanup: cleanup, pasteLast: pasteLast)
        switch role {
        case .handsFree: new.handsFree = chord ?? .defaultHandsFree
        case .pushToTalk: break
        case .cleanup: new.cleanup = chord
        case .pasteLast: new.pasteLast = chord
        }
        new.pushToTalk = Chord.pushToTalk(afterSaving: chord, as: role, handsFree: new.handsFree, kept: savedPushToTalk)
        let problem = Chord.problem(
            handsFree: new.handsFree, pushToTalk: new.pushToTalk, cleanup: new.cleanup, pasteLast: new.pasteLast)
        if let problem { return problem }
        (handsFree, savedPushToTalk, cleanup, pasteLast) = new
        defaults?.set(handsFree.storedValue, forKey: Key.handsFreeChord.rawValue)
        if let savedPushToTalk {
            defaults?.set(savedPushToTalk.storedValue, forKey: Key.pushToTalkChord.rawValue)
        } else {
            defaults?.removeObject(forKey: Key.pushToTalkChord.rawValue)
        }
        defaults?.set(cleanup?.storedValue ?? Self.off, forKey: Key.cleanupChord.rawValue)
        defaults?.set(pasteLast?.storedValue ?? Self.off, forKey: Key.pasteLastChord.rawValue)
        apply()
        return nil
    }

    private func apply() {
        tap?.setChords(
            handsFree: handsFree, pushToTalk: savedPushToTalk, cleanup: cleanup, pasteLast: pasteLast,
            isPaused: isRecording)
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
        let parts = modifierParts
        let modifiers = parts.contains { $0.contains(" ") } ? parts.joined(separator: " ") : parts.joined()
        guard let keyCode else { return modifiers }
        return modifiers + Self.keyName(keyCode)
    }

    private var modifierParts: [String] {
        ModifierKeys.allKinds.compactMap { kind in
            let sides = modifiers.intersection(kind)
            guard !sides.isEmpty else { return nil }
            let side = sides == kind ? "" : sides.isSubset(of: .rightSides) ? "right " : "left "
            return side + kind.symbol
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
}
