# kotoba

Native macOS dictation: tap a chord, speak, tap again, and the transcript is pasted. These are the words the code, tests and docs use for its parts.

## Language

**Shell**:
What kotoba shows of itself besides the pill and its windows: the menu bar icon and its menu, the Dock icon's badge and menu, and the start and stop cues.
_Avoid_: chrome, status bar UI

### Audio capture

**Capture**:
One recording of the mic into one audio file, from its start to its end or cancel: a dictation's, or the Settings mic test's.
_Avoid_: session, recording session

**Mic in use**:
The microphone a capture records from, or the next dictation will: the first connected mic in the owner's order, else the system default with a Bluetooth default replaced by the built-in mic.
_Avoid_: current device, active input

**Upload copy**:
The same audio as a capture's FLAC, as Ogg Opus at 24 kbps, written while it records and sent instead of the FLAC by a route measured with it, in the first request only, which deletes it. After a cut it holds only the audio after the last cut. The FLAC stays the kept recording.
_Avoid_: compressed audio, opus file

**Segment**:
A part of a dictation's upload copy, cut at the first pause of 0.4 s that starts 15 s or more after the last cut, and sent while the dictation records.
_Avoid_: chunk (one buffer the capture writer converts), part, slice

**Segment upload**:
Sending a dictation's segments while it records, then at the stop the copy after the last cut, and joining their texts in order; any segment that fails sends the whole recording instead.
_Avoid_: streaming, chunked upload

**Input**:
The open connection to the mic in use. It is ready while idle and runs only during a capture, so the mic is on only while recording.
_Avoid_: engine, unit, stream

**Input lifecycle**:
The rules for when an input is built, started, stopped and built again, and which device changes wait for the end of a capture.
_Avoid_: audio state machine, route handling

**Rebuild**:
Closing the input and opening a new one on the mic in use, after a device, route or audio service change or a mic that did not start.
_Avoid_: reconfigure, restart

**Route change**:
A change of the mic in use's sample rate, or the mic going away, while its input is open.
_Avoid_: configuration change

**Settling mic**:
A mic whose format was read twice in the middle of a change; no input opens until its next change ends.
_Avoid_: pending device, unstable mic

**Recorder**:
What writes one capture's audio file at the input's sample rate.
_Avoid_: encoder

### Paste

**Paste transaction**:
One paste of kotoba's text into the owner's app: the check that it may paste, the text written over the owner's clipboard, the ⌘V (with Backspaces before it or a Return after it), and the owner's clipboard coming back after the app read the text. A dictation, Polish and its Undo, Paste Last and Paste Again each paste through one.
_Avoid_: clipboard guard, paste path

**Paste gate**:
What decides, right before the write, whether a paste transaction may go out: it waits for the chord's release, and says whether kotoba quits, the owner is away, or a dictation came first.
_Avoid_: before-paste check, paste choice

**Overtaken**:
Said of a Paste Again or Polish when a dictation started, waits or is sent since the owner asked (for Paste Again, also when a Polish runs): that one wins, and nothing is pasted or copied.

### Live dictations

**Live dictation**:
A dictation from its key-down until it ends: while it records, waits in its Undo window, or is in flight. It ends when it is finished, cancelled or dropped, or when quit keeps it for the next launch.
_Avoid_: active dictation, current dictation

**In flight**:
Said of a live dictation after its stop, while its audio is sent and its text is cleaned, pasted or saved. Quit waits a little for each one, so its billed text is kept.
_Avoid_: pending (a status in History), transcribing (one step of it)

**Billed work**:
A request whose cost goes to the usage ledger outside a dictation's send or a job: a primer, the segments a recording did not use, a late cleanup or Polish answer. Quit waits a little for it, as for a dictation in flight, so its cost is counted.
_Avoid_: background billing, usage task

**Phase**:
The step the pipeline is in now: idle, recording, transcribing, cleaning, the Undo window, or polishing. It says whether a dictation or Polish is live, also while a notice shows.
_Avoid_: state (the phase with its notice), status (a History row's)

**Notice**:
A one-shot outcome the pill and the menu show over the phase until the next phase change: an error, a warning, or how the text reached the owner (copied, recovered, polished).
_Avoid_: outcome state, error state, toast

**Quiet**:
No live dictation and no Polish: only then does Paste Again paste and a retry send begin. Transcribe Again and a retry send paste nothing, so they keep kotoba quiet.
_Avoid_: idle (what the pill shows), free
