/// The step the pipeline is in: what is live now. Only a step a dictation or Polish stays in goes here; a one-shot
/// outcome is a `DictationNotice` (lint `dictation_phase_cases`).
public enum DictationPhase: Sendable, Equatable {
    case idle
    /// `isLong` turns on after `Settings.longRecordingWarning`; recording never stops on its own.
    /// `isSilent` is on while the mic gives no sound (`NoSoundPolicy`); it clears when sound arrives.
    /// `isCleaned`: the dictation will be cleaned up, by the cleanup chord or by the mode of the app in front at
    /// key-down; the app in front at the stop decides in the end.
    /// `isPushToTalk`: the release of the press that started it stops it (a hold past the threshold); off, the next
    /// press stops it (hands-free: a tap, the hands-free chord of a split pair, the pill, an Undo).
    case recording(isLong: Bool, isSilent: Bool = false, isCleaned: Bool = false, isPushToTalk: Bool = false)
    case transcribing
    /// The transcript is with the cleaner (LLM cleanup, 1.6 s p50 in kotoba-bench-v1); the paste follows.
    case cleaning
    /// Esc cancelled the recording and the mic is off. Undo (or a chord tap) resumes it until
    /// `Settings.undoWindow` passes; then the cancel is final.
    case undoable
    /// Polish sent the last dictation to the LLM; the paste follows.
    case polishing

    /// The owner is still in a dictation or a Polish: it records, waits in its Undo window, is in flight or is
    /// rewritten. What waits for the owner's dictation to end (learning from edits, a development build's menu) asks
    /// this, never a list of phases (lint `phase_is_live`).
    public var isLive: Bool {
        switch self {
        case .idle: false
        case .recording, .transcribing, .cleaning, .undoable, .polishing: true
        }
    }

    public var isRecording: Bool {
        if case .recording = self { true } else { false }
    }
}
