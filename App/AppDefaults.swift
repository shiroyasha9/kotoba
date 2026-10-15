import Foundation

/// The App's own settings in UserDefaults, with their keys in one place. Provider settings live in
/// `TranscriptionSettings`; `IndicatorPanel` reads and writes the indicator keys.
enum AppDefaults {
    enum Key: String {
        case soundCues
        case dictationChord = "hotkey.dictationChord"
        case cleanupChord = "hotkey.cleanupChord"
        case microphoneOrder = "microphone.order"
        case submitPhrase = "paste.submitPhrase"
        case learnsFromEdits = "dictionary.learnsFromEdits"
        case indicatorAnchor = "indicator.anchor"
        case indicatorVisibility = "indicator.visibility"
    }

    /// The values a setting has until the owner changes it, registered once at launch (`main.swift`) before anything
    /// reads a setting, so no reader repeats a default.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.soundCues.rawValue: true,
            Key.submitPhrase.rawValue: true,
            Key.learnsFromEdits.rawValue: true,
        ])
    }

    static var areSoundCuesOn: Bool {
        get { UserDefaults.standard.bool(forKey: Key.soundCues.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: Key.soundCues.rawValue) }
    }

    /// "press enter" or "press return" as the last words sends Return after the paste. On by default.
    static var isSubmitPhraseOn: Bool {
        get { UserDefaults.standard.bool(forKey: Key.submitPhrase.rawValue) }
        set { UserDefaults.standard.set(newValue, forKey: Key.submitPhrase.rawValue) }
    }

    /// "Learn from my edits": after a paste, kotoba follows the field and adds the words the owner fixes. On by
    /// default; read on each paste, from any thread.
    static var isLearningFromEdits: Bool {
        UserDefaults.standard.bool(forKey: Key.learnsFromEdits.rawValue)
    }
}
