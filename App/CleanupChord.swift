import Foundation
import KotobaCore

/// The owner's choice of cleanup chord, saved in UserDefaults: ⌃⌥⌘⇧ by default, which a Caps Lock "Hyper"
/// key also presses (all four, in any order), or ⌃⌥⌘fn, or off.
enum CleanupChord: String, CaseIterable {
    case shift
    case function
    case off

    private static let key = AppDefaults.Key.cleanupChord.rawValue

    static var current: Self {
        get { UserDefaults.standard.string(forKey: key).flatMap(Self.init) ?? .shift }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    var modifiers: ModifierKeys? {
        switch self {
        case .shift: ModifierKeys.chord.union(.shift)
        case .function: ModifierKeys.chord.union(.function)
        case .off: nil
        }
    }

    var title: String {
        switch self {
        case .shift: StatusText.dictationChord + "⇧"
        case .function: StatusText.dictationChord + "fn"
        case .off: "Off"
        }
    }
}
