import Foundation
import KotobaCore

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
        case audioRetention = "history.audioRetention"
        case modes = "modes.rules"
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

    /// How long a transcribed dictation keeps its audio (story 31). No registered default: launch stores the first
    /// choice once (`chooseAudioRetention(hadDictations:)`), so an update never applies 7 days to an older history.
    static var audioRetention: AudioRetention {
        get { storedAudioRetention ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.audioRetention.rawValue) }
    }

    /// Not `integer(forKey:)`: its 0 for a missing value is `.forever`.
    private static var storedAudioRetention: AudioRetention? {
        (UserDefaults.standard.object(forKey: Key.audioRetention.rawValue) as? Int).flatMap(AudioRetention.init)
    }

    /// The per-app modes (story 29) as JSON. A new install gets `ModeRules.standard`; so does a value this build cannot
    /// read, with a log line, so a bad value never stops a dictation.
    static var modeRules: ModeRules {
        get {
            guard let data = UserDefaults.standard.data(forKey: Key.modes.rawValue) else { return .standard }
            do {
                return try JSONDecoder().decode(ModeRules.self, from: data)
            } catch {
                Log.app.error("Cannot read the modes, using the standard ones: \(error)")
                return .standard
            }
        }
        set {
            do {
                UserDefaults.standard.set(try JSONEncoder().encode(newValue), forKey: Key.modes.rawValue)
            } catch {
                Log.app.error("Cannot save the modes: \(error)")
            }
        }
    }

    /// Stores the period of an install that has none yet, before any retention runs: Forever when the history already
    /// had dictations (an update), 7 days for a new install (`AudioRetention.firstChoice`).
    static func chooseAudioRetention(hadDictations: Bool) -> AudioRetention {
        if let stored = storedAudioRetention { return stored }
        let chosen = AudioRetention.firstChoice(hasEarlierHistory: hadDictations)
        audioRetention = chosen
        return chosen
    }
}
