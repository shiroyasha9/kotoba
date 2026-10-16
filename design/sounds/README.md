# kotoba sound cues

`generator/cues.ts` holds the notes and a plucked-string tone (Karplus-Strong); `bun generator/cues.ts` writes `App/Sounds/DictationStart.caf` and `App/Sounds/DictationStop.caf`, which the app plays when recording starts and stops (`AppDelegate.playCue`): a soft nylon pluck, E3 to B3 rising at the start, falling at the stop. `bun generator/cues.ts --all <folder>` writes every voice in `voices` (nylon, a lower A2 to E3, a brighter steel) to compare them.

The cues are kotoba's own on purpose: every file in `/System/Library/Sounds` is also a choice of system alert sound, and Tink is the default one ("Boop" in Sound settings). With Tink as the start cue, starting a dictation sounded like the alert beep (2026-10-16).
