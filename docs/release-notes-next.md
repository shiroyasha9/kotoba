## kotoba 0.4.0 (draft)

### New

- Polish rewrites your last dictation shorter and clearer, with nothing lost. Choose "Polish Last Dictation" in the menu, or record a shortcut for it in Settings > General (off until you do). Where kotoba can find the text, it replaces it in place, with Undo for 8 seconds; otherwise the polished text goes to your clipboard. It uses DeepSeek V4.1 Flash through OpenRouter, with Gemini 3.5 Flash-Lite as a fallback, on endpoints that keep no data.
- "View Changes…" in History shows, word by word, what cleanup and Polish changed.
- Copy Last copies your last dictation with ⌃⌘C; change it in Settings > General. If a dictation shortcut you recorded clashes with ⌃⌘C, Copy Last turns off and says why.
- Hands-free and Push to talk can use a middle or side mouse button, alone or with modifiers. Record it in Settings > General like a key. While it is your shortcut, apps no longer get that button.
- Double-tap your Push to talk shortcut to dictate hands-free, until your next press. This works when Push to talk has its own shortcut.
- History can play a dictation's saved audio (or press Space) and show the file in Finder.
- Transcribe Again in History sends a dictation's saved audio once more, with the current speech model or another one whose key you saved. The new text replaces the old; nothing is pasted.
- "Add Word…" in the menu bar menu opens the dictionary with a new word ready to type.
- The Modes pane shows an example of each mode: what you say and what kotoba pastes.
- VoiceOver: the indicator is a Start Dictating or Stop Dictating button, and Choose Mic… is its own button.

### Faster

- With MAI-Transcribe-2 through OpenRouter, kotoba warms the speech route while you speak. The route answered slowly after a quiet minute; each dictation now sends a short clip of silence when it starts, so the route is warm when you stop. Each clip costs one billed second (about $0.00003) and shows in Usage.

### Fixed

- Your clipboard comes back only after the app you dictate into has read the paste, so a busy app no longer pastes your old clipboard. If no app reads it within 10 seconds, the text stays on the clipboard and the indicator says "Copied. Press ⌘V to paste."
- A transcript that arrives after you switch apps, or while the screen is locked, goes to the clipboard and is never pasted into another app.
- Locking the screen, sleep or a user switch stops a recording, and kotoba transcribes what you said.
- A cleanup or Polish answer that was cut off is never pasted. A cut cleanup pastes the raw transcript instead.
- Automatic retries stop after 3 tries, then the dictation waits for your Retry. An answer kotoba cannot read is no longer sent again.
- Long recordings get more time to transcribe, and a slow answer says "OpenRouter took too long. Saved." instead of looking offline.
- Only one copy of kotoba runs. Opening it again brings up the running one.
- If you turn off Accessibility for kotoba, a dictation goes to the clipboard instead of pasting nowhere, and the shortcut works again as soon as you turn it back on.
- When the disk is full, the indicator says so, and kotoba pastes the part it saved.
- A clipboard over 64 MB is not kept: the dictation still pastes, and the indicator says the old clipboard was too large to keep.
- Paste works with the "Dvorak - QWERTY ⌘" keyboard layout and after you switch layouts.
- The microphone works again after it failed to start or after the macOS audio service restarted.
- kotoba no longer checks permissions every second while one of its windows is open.
- Setup: both ways to dictate are shown above the Try It field, the key links sit below the key field, and "Get a Key" is gone once a key is saved.
- Test Microphone says what it does before you click it. The transcribing indicator shows only the spinner.
