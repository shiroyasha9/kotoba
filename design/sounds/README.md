# kotoba sound cues

`generator/cues.ts` holds the voices and a plucked-string tone (Karplus-Strong). `bun generator/cues.ts` writes a start and a stop cue for each voice into `App/Sounds` (`nylon-DictationStart.caf`, `nylon-DictationStop.caf`, ...); the same seed gives the same files on every run. The start cue rises, the stop cue falls:

- nylon, the default: a soft nylon pluck, E3 to B3.
- low: the nylon pluck a fifth lower, A2 to E3.
- steel: a brighter steel string, E3 to B3.

The owner picks the voice in General ("Sound"); `SoundCues` loads the chosen pair. A new voice is a case in `CueVoice` (KotobaCore), an entry in `voices` and a title in `App/SoundCues.swift`.

The cues are kotoba's own on purpose: every file in `/System/Library/Sounds` is also a choice of system alert sound, and Tink is the default one ("Boop" in Sound settings). With Tink as the start cue, starting a dictation sounded like the alert beep (2026-10-16).
