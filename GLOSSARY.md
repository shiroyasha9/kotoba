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
