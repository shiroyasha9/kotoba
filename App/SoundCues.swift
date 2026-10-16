import AppKit
import KotobaCore

/// The start and stop cues of the chosen voice: one pair, loaded at the first cue and again only when the owner
/// picks another voice in General. Nothing loads at launch.
///
/// The sounds are kotoba's own (App/Sounds, made by design/sounds), never system sounds: each system sound is also a
/// choice of alert sound (Tink is the default), so a cue would sound like the focused app's beep.
@MainActor
final class SoundCues {
    private struct Pair {
        let voice: CueVoice
        let start: NSSound?
        let stop: NSSound?
    }

    private var pair: Pair?

    /// Saved at once; a voice that sounded before loads its new pair now, so the preview that follows plays without
    /// a wait.
    var voice: CueVoice {
        get { AppDefaults.cueVoice }
        set {
            AppDefaults.cueVoice = newValue
            if let pair, pair.voice != newValue {
                self.pair = Self.load(newValue)
            }
        }
    }

    /// Nothing plays while the owner has sounds off. A cue still sounding from a quick earlier dictation starts over:
    /// `NSSound.play()` does nothing while the same sound plays.
    func play(_ cue: CueVoice.Cue) {
        guard AppDefaults.areSoundCuesOn else { return }
        let pair = pair ?? Self.load(voice)
        self.pair = pair
        guard let sound = cue == .start ? pair.start : pair.stop else { return }
        sound.stop()
        sound.play()
    }

    private static func load(_ voice: CueVoice) -> Pair {
        Pair(voice: voice, start: sound(voice.soundName(.start)), stop: sound(voice.soundName(.stop)))
    }

    /// Nil, logged, for a sound the bundle lacks: the cue stays silent and dictation goes on.
    private static func sound(_ name: String) -> NSSound? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
            let sound = NSSound(contentsOf: url, byReference: true)
        else {
            Log.app.error("Cannot load the sound \(name, privacy: .public)")
            return nil
        }
        return sound
    }
}

extension CueVoice {
    /// The menu title in General.
    var title: String {
        switch self {
        case .nylon: "Nylon"
        case .low: "Low"
        case .steel: "Steel"
        }
    }
}
