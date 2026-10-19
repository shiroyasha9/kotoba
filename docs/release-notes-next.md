## kotoba next

### Changed

- Your text comes about 0.2 s sooner with MAI-Transcribe-2 via OpenRouter: kotoba sends a fifth of the audio bytes it sent before, at the same accuracy. Your recordings in History stay as they were.

### Fixed

- Paste Last, Paste Again and Polish no longer paste into another app or the lock screen. When you go to another app or the screen locks just as you ask, the text waits on the clipboard, as for a dictation.
- When you start a recording just as Paste Last or Paste Again pastes, the recording pill stays.
- Learning from your edits waits while Polish rewrites your text, so its “learned” notice no longer covers the Polishing pill. It also waits while a second dictation is still being sent.
- When you start a recording just as kotoba sends a saved dictation again, that send waits until your new dictation is done, as it does when the recording started first.
