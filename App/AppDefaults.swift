import Foundation

/// The App's own settings in UserDefaults, with their keys in one place. Provider settings live in
/// `TranscriptionSettings`, the indicator position in `IndicatorPanel`.
enum AppDefaults {
    enum Key: String {
        case soundCues
        case cleanupChord = "hotkey.cleanupChord"
        case microphoneOrder = "microphone.order"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [Key.soundCues.rawValue: true])
    }

    static var areSoundCuesOn: Bool {
        get { UserDefaults.standard.bool(forKey: Key.soundCues.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: Key.soundCues.rawValue) }
    }
}
