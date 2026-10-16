# kotoba - spec v1

Status: agreed with the owner on 2026-10-15 (grill session). Research behind each decision: `docs/research/`.

## Problem Statement

The owner is a developer in India on an Apple Silicon Mac. They dictate about 200 words per minute, mostly prompts for Claude Code, Codex and Cursor, typed into terminals (cmux), editors and browsers. The prompts are full of identifiers, file names, paths and CLI flags.

They pay about Rs 400 a month for Wispr Flow Pro. Wispr mis-transcribes technical terms often. (Wispr's own counter shows about 10,000 corrected words over about 73,000 words, but that counter includes its formatter's changes; the owner's real edits are far fewer, see `docs/research/auto-learning.md`.) Wispr is an Electron app (reported at 0.75-1 GB RAM) and its measured average end-to-end latency on the owner's machine is 1,254 ms (average network part 372 ms, from Wispr's own local history).

Cloud speech-to-text through the owner's own API key costs about $0.10 per hour of audio. No existing app combines: native and light, cloud-only, own keys, top-accuracy models (xAI Grok Voice Transcribe 2.0, Microsoft MAI-Transcribe-2), fast release-to-paste, and a permissive licence.

## Solution

A native macOS dictation app, kotoba, in the Dock and the menu bar. The owner taps a chord, speaks, taps again, and the text appears in the focused app within about one second. Transcription runs in the cloud with the owner's own keys, stored in the Keychain. There are no accounts and no telemetry. The app is small in memory, starts capturing at the instant of the key press, never loses a dictation, and improves technical accuracy through a personal dictionary sent to the model as keyterms.

The app is open-source (Apache-2.0) and distributed as a notarized DMG on GitHub Releases once the MVP passes its gates.

## User Stories

### Recording and hotkey
1. As a developer, I want to tap Ctrl+Opt+Cmd to start recording and tap it again to stop, so that I can dictate long prompts without holding keys.
2. As a developer, I want a hold of the chord longer than about 400 ms to act as push-to-talk, so that short dictations need one gesture.
2a. As a developer coming from Wispr Flow, I want separate Hands-free and Push to talk shortcuts, and ⌥ alone for push to talk, so that each gesture has its own key (owner, 2026-10-16). By default both are ⌃⌥⌘ and work as stories 1-2 say; an existing install keeps its chord as Hands-free, and Push to talk uses it until the owner records another.
3. As a developer, I want audio capture to start at the instant of the key press, with no clipped first word, so that I do not repeat myself.
4. As a developer, I want the last word kept when I stop, so that the end of a sentence is not cut.
5. As a developer, I want Esc to cancel a recording and keep its audio in history, so that I can abort without losing it.
5a. As a developer, I want an Undo for 5 s after Esc that resumes the same recording, so that an accidental Esc does not lose what I said so far (like Wispr Flow).
6. As a developer, I want a warning after 10 minutes of recording (no automatic stop), so that I notice a forgotten recording.
7. As a developer, I want the start sound to play only after capture has started, so that the sound means "you can speak now".
8. As a developer, I want to turn sound cues off, so that I can dictate in quiet places.
9. As a developer, I want the hotkey to keep working when a password field has turned on secure input, so that dictation never silently fails.
10. As a developer using AirPods, I want kotoba to use the built-in mic when AirPods are the output, so that the Bluetooth call-mode switch does not garble my first words.
11. As a developer, I want kotoba to recover when the audio route changes (headset plugged in or out), so that the next dictation works without a restart.

### Indicator
12. As a developer, I want a small floating indicator with the recording state and the mic level, so that I know kotoba hears me.
13. As a developer, I want the indicator to show "transcribing", "failed - retry" and "secure input on" states, so that I know what happens after I stop.
14. As a developer, I want the indicator to use native Liquid Glass when it costs little memory, so that it looks native on macOS 26.
14a. As a developer, I want the indicator at the bottom center of the screen by default, and I want to drag it to the left or right edge (phase 2), so that it does not cover what I work on.

### Transcription and paste
15. As a developer, I want text pasted into the focused app (cmux, Terminal, Cursor, Codex, browsers, Slack) within about one second of the stop tap, so that dictation is faster than typing.
16. As a developer, I want my clipboard restored after the paste, so that dictation does not destroy what I copied.
17. As a developer, I want clipboard managers to skip kotoba's transient paste, so that my clipboard history stays clean.
18. As a developer, I want to choose the provider route (OpenRouter, xAI direct, Azure MAI direct) and the model, so that I can switch when one is better or cheaper.
19. As a developer, I want my API keys stored in the macOS Keychain, so that they are not in plain files.
20. As a developer, I want to set the language (English first), so that recognition uses the right model.

### Reliability
21. As a developer, I want the audio kept when the network fails, and a retry action, so that no dictation is ever lost.
22. As a developer, I want queued failed dictations retried when the network returns, with the result offered for paste or copy, so that I do not re-dictate.
23. As a developer, I want kotoba to stay alive under memory pressure (no automatic termination), so that it does not quit in the middle of a recording.

### Dictionary and cleanup (phase 2)
24. As a developer, I want a personal dictionary sent to the model as keyterms or phrase list, so that identifiers and names are recognised.
25. As a developer, I want find-and-replace rules applied after transcription, so that systematic errors are fixed every time.
26. As a Wispr Flow user, I want a one-click import of my Wispr dictionary (words and replacement rules), found automatically on my Mac, so that I switch from Wispr Flow with my existing vocabulary.
27. As a developer, I want a second hotkey or mode for LLM cleanup (filler removal, punctuation, "make this a clean prompt"), so that I choose when to pay its latency.
28. As a developer, I want the cleanup prompt to treat my transcript as data, so that the LLM never answers or obeys my dictated prompt.
28a. As a developer, I want to pick the microphone and set a preference order of microphones, so that kotoba uses my preferred mic whenever it is connected.

### Modes, history, learning (phase 3)
29. As a developer, I want per-app modes (cleanup prompt, language, provider by frontmost app), so that terminals keep code formatting and chat apps get prose.
30. As a developer, I want a history window with past transcripts, re-paste and copy, so that I can reuse a dictation.
31. As a developer, I want audio kept for a set number of days, then deleted, so that history stays useful and disk use stays bounded.
32. As a developer, I want kotoba to notice when I edit pasted text and suggest a dictionary entry, so that accuracy improves with use.
33. As a developer, I want a usage tracker with minutes and estimated cost per provider, so that I know what kotoba costs me.
34. As a developer, I want optional context awareness (selected or nearby text sent as context), off by default, so that I choose the privacy trade-off.

### App shell and distribution
35. As a user, I want kotoba in the Dock and in the menu bar by default, with a setting to hide either one but not both, so that it stays as far out of the way as I want and I can always reach it. An update turns the Dock icon on too (owner, 2026-10-16).
35a. As a user with "Show in Dock" off, I want kotoba in the Dock only while one of its windows is open (the main window, onboarding, Fix Dictation; not the indicator or a menu), so that ⌘-Tab and the menu bar work while I use a window, and kotoba keeps dictating from the menu bar when I close it.
35b. As a user, I want a launch from Finder, Spotlight or `open` to show the main window and a launch at login to show none, and a Dock click or a second open to show the main window, so that I can always get back in, even with an icon hidden. Onboarding comes first until it is done.
35c. As a user, I want the Dock icon's right-click menu to offer the menu bar menu's items, so that I reach them with the menu bar icon hidden.
35d. As a user, I want the Dock icon to show the number of dictations that wait for a retry, and no badge at zero, so that I see a failed dictation without opening a menu.
35e. As the owner, I want kotoba Dev to have its own Dock icon, so that I can tell it from the release.
36. As a user, I want launch at login, so that dictation is always available.
37. As a user, I want onboarding that grants Microphone, Accessibility and Input Monitoring permissions and explains each, so that setup works the first time.
37a. As a new user, I want the welcome page to say in three short points why kotoba is worth it (about one second to paste, my names and terms spelled right, private with my own key) and to show both ways to dictate (tap, speak, tap again; or hold while I speak), so that I know what I get before I grant anything (owner, 2026-10-16).
37b. As a new user, I want each permission step to show the grant and wait for my Continue, so that the window never moves on by itself. The Microphone and Accessibility steps have no Skip: kotoba cannot record without the mic, and the hotkey tap cannot start without Accessibility, so kotoba cannot hear the chord (owner question, answered by the lead 2026-10-16).
37c. As a user, I want a saved key to show as saved (the masked key, such as "sk-or-v1-…a1b2", with Change… and Remove) in onboarding and in Settings > Speech, so that I never think I must paste it again. The key itself never comes back to the screen.
37d. As a Wispr Flow user, I want onboarding to offer the Wispr dictionary import as an optional step when Wispr Flow is on my Mac, with the same preview and one-click import as Settings > Dictionary, so that my words carry over before my first dictation.
38. As a user, I want permissions to survive app updates, so that I do not re-grant them after each release.
39. As a user, I want a notarized DMG from GitHub Releases, so that macOS opens it without warnings.
40. As a privacy-minded user, I want no accounts, no analytics and no outbound calls other than to my chosen provider, so that my dictation stays mine.

### Owner and maintainer
41. As the owner, I want a latency log with timestamps for key-down, first audio buffer, key-up, upload start, response, and Cmd-V sent, so that I can see where each millisecond goes.
42. As the owner, I want a benchmark harness that scores providers on my real clips (WER, technical-term recall, latency, cost), so that provider and prompt choices are measured, not guessed.
43. As the owner, I want an idle-memory check, so that memory regressions are visible.
44. As a contributor, I want one `make check` command (format, lint, type check, tests), so that every change meets the same bar.

## Implementation Decisions

### Approach
- Build a new app. Do not fork VoiceInk: 72.5k lines with no unit tests, three local speech stacks linked into the main binary, and latency faults in the hot path (new connection per request, fixed 200 ms pre-paste sleep, paste chained behind a 2 s clipboard restore, OCR on every recording).
- Copy or adapt only MIT or Apache-2.0 code, with notices kept: Jot (Apache-2.0, main reference design: prepared engine, write-from-key-down, FLAC upload, offline queue, guarded paste), Hex (MIT, pre-roll and hotkey logic), FreeFlow (MIT). Never copy GPL code (VoiceInk, TypeWhisper); reading it for ideas is fine.
- kotoba licence: Apache-2.0.

### Platform and UI
- Minimum macOS 26. Bundle ID `tech.teensy.kotoba`; Debug builds are a separate install, `tech.teensy.kotoba.dev` ("kotoba Dev"), with their own settings, data and keys (`App/Install.swift`). Signed with the owner's Developer ID (team 7U6G55576W), notarized. Every development build is signed with the same identity so TCC permissions and Keychain access survive rebuilds.
- kotoba is a Dock app by default ("Show in Dock", General). The Info.plist keeps `LSUIElement`, and the first step of the launch sets the `.regular` policy from the setting (`App/DockAndMenuBar.swift`, the only caller of `setActivationPolicy`), so no launch shows a Dock icon by mistake; a change applies at once, without a relaunch. The AppKit `NSStatusItem` menu bar icon has its own setting; the two cannot both be off. The main menu has the kotoba app menu first (About, Settings…, Hide, Quit). The recording indicator is an AppKit panel using `NSGlassEffectView`; it never activates kotoba and never hides with it (`canHide` off).
- SwiftUI only for windows that open on demand: the main window (one sidebar with Home, History, Insights, Usage and the settings; since 0.3.0), onboarding and Fix Last Dictation. Measured 2026-10-15 (`docs/research/memory-spike.md`): status item + glass panel + prepared engine idles at about 17 MB; a SwiftUI window adds about 15 MB that stays after close. The owner accepts SwiftUI for these windows for now; AppKit replacement is a later option if memory matters.
- No WebKit, no SwiftData, no local speech models. `NSSupportsAutomaticTermination` off.

### Gates
- Latency gate: from stop tap to Cmd-V sent, for 10-20 s clips on the owner's home network: p50 <= 1.0 s, p90 <= 1.5 s. Measured by the in-app latency log.
- Memory: soft target, performance is a top-tier priority. Original aim was under 50 MB idle; no comparable app reaches it (Jot about 90 MB). A day-1 spike (empty status item + prepared audio engine) measures the floor with `footprint`.

### Hotkey state machine
- Chord: Ctrl+Opt+Cmd (modifier-only, so it works during secure input). Captured with a CGEventTap on flagsChanged, callback kept short and off the main thread, tap re-enabled when the system disables it.
- Tap (chord down and up under about 400 ms): start; next tap: stop and paste. Hold over the threshold: push-to-talk, stop on release. This is the rule while Hands-free and Push to talk are one chord (the default).
- Separate chords (owner, 2026-10-16), each strict. Hands-free: a press starts, the next press stops and pastes; a long hold does not stop at its release. Push to talk: capture starts at key-down as for every press; the indicator and start cue come at the threshold; the release stops and pastes; a release under the threshold drops the press with no cue and nothing kept. For both, a key typed or a mouse button pressed (left, right or other) during the starting press before the announcement drops it as a shortcut, so a ⌘-click or ⌥-drag never records; a click after the announcement changes nothing. Mouse-downs come from AppKit event monitors (a global one for other apps, a local one for kotoba's windows except the pill, whose click is a chord tap): they only observe, so no click waits for kotoba, and they need no permission beyond Accessibility. They run only while the hotkey tap runs and is enabled, and no shortcut recorder listens. The cleanup chord keeps the tap-or-hold rule.
- The edit session that follows the last paste ends at the announcement of the next dictation, not at its key-down: a dropped press (⌥⌫ after a paste, with ⌥ for push to talk) leaves the session on, so the owner's edit is still learned.
- A press follows the chord held with the most keys, until its announcement: with ⌥ for push to talk, pressing ⌃⌥⌘ starts as push to talk at ⌥ and becomes hands-free at ⌘; ⌃⌥⇧⌘ becomes cleanup. A press never goes back to a chord with fewer keys.
- A press of either dictation chord stops a running recording, whichever chord started it, so the owner is never stuck with the mic on (decided 2026-10-16). With ⌥ alone for push to talk, an ⌥ shortcut typed during a hands-free dictation stops it. In the Undo window only a tap of a chord that can tap resumes; a push-to-talk press does nothing there.
- Esc during recording: cancel, keep audio. After Esc the indicator shows Undo for 5 s (mic off during the window); clicking Undo or tapping the chord in that window resumes the same recording, appending to the same audio file, and the next stop transcribes the whole recording. After 5 s the cancel is final. Threshold tuned after owner testing.
- A stop with less than 0.5 s of audio (`Settings.minimumRecording`; an accidental double tap) discards the dictation: no request, no audio file, no history row, no paste and no error; the pill goes back to idle (owner, 2026-10-16). The audio written decides, the part an Undo resumed included, not the key times. A longer silent recording is sent, and its empty answer shows "No speech heard" at once, with no automatic retry.
- Secure input state (`IsSecureEventInputEnabled`) shown in the indicator.
- Indicator position (phase 2, like Wispr Flow): three anchors, on the screen that holds the focused window. Bottom center (default): a horizontal pill just above the Dock or the screen bottom. Left edge and right edge: a vertical pill at mid-height while listening or transcribing; states with text (warnings, Canceled + Undo, errors) stay a horizontal pill at the edge. Drag the indicator; during the drag the three anchors show as drop targets, and on release it snaps to the nearest one. The anchor is saved in UserDefaults. An "Indicator Position" submenu sets it too. The pill respects the visible frame (Dock, menu bar, notch).

### Audio
- No pre-roll and no always-open mic: the owner rejected the always-on orange mic dot (2026-10-15). The audio engine is prepared while idle but not started; it starts on key-down (about 20-40 ms) before any UI or sound work; capture is written to disk from the first buffer; capture ends with the hardware cycle that holds the stop moment (AVAudioSinkNode, about 10.7 ms cycles; stop wait worst case 13 ms, measured 2026-10-15). The mic is open only while recording. Verified 2026-10-15 by the owner: a prepared-but-not-started engine shows no orange mic dot.
- Route changes rebuild the engine. When AirPods are the output, use the built-in mic.
- Microphone choice (phase 2): a "Microphone" submenu lists the connected inputs with the current one checked, for a quick switch; Settings holds a drag-to-order preference list, saved by device UID. kotoba records from the first connected device in the list; when none is connected, it uses the system default input. Only an owner action adds a mic to the list (a menu pick, or a drag into the list); other connected mics show apart and are never saved by accident. A mic that connects during a recording takes over at the next dictation. The Bluetooth-to-built-in rule applies only when kotoba follows the system default; a Bluetooth mic the owner put in the list is used as listed.
- Upload format: 16 kHz mono FLAC (native in `AVAudioFile`). Opus only for providers that accept it, if the benchmark shows a gain.

### Transcription providers
- One `TranscriptionProvider` protocol: input is an audio file plus options (language, vocabulary terms); output is text plus usage (audio seconds, cost when known) and timing. Each provider owns one long-lived URLSession, warmed at key-down.
- Routes, in order: OpenRouter (owner already has a key; one key for both models; adds one hop), then xAI direct (`POST /v1/stt`, multipart, up to 100 keyterms of 50 chars) and Azure MAI-Transcribe-2 direct (fast transcription REST, `phraseList`, Central India region available). Order of the direct routes follows the benchmark.
- MAI-Transcribe-2 is public preview; its $0.10/h price is a promotion until 2026-12-31.

### Paste
- Snapshot all pasteboard types and the changeCount at chord-down (off the hot path); before writing, take a new snapshot only if the changeCount changed since. Write the transcript marked transient/concealed, post Cmd-V via CGEvent, restore after about 1.0 s only if the pasteboard did not change since. No fixed pre-paste sleep. A new paste never waits for a previous restore.
- AX value insertion is not used as the main path (Electron apps report false success).

### Wispr Flow import (phase 2)
- Wispr Flow keeps its dictionary locally in its SQLite database: table `Dictionary` (`phrase`, `replacement`, `isDeleted`); the owner's backup of 2026-10-14 has 36 live entries, 2 with a replacement.
- One click in Settings: find Wispr's database on disk, APFS-clone `flow.sqlite` and `flow.sqlite-wal` into a temp folder and read the clone (SQLite never opens Wispr's own files, and edits still in the WAL are included; `immutable=1` would skip the WAL). If either source file changes during the clone, clone again (at most 3 tries). Delete the clone after, import live entries: `phrase` only -> dictionary term; `phrase` + `replacement` -> find/replace rule; `source='user_edits'` + `observedSource` (Wispr's learned corrections) -> term plus a rule `observedSource` -> `phrase`. Personal and team-dictionary rows both import; `isSnippet=1` rows are counted but not imported (snippets are a later feature). De-duplicate case-insensitively, inside the import too (the backup has duplicates such as `zod`) and against existing entries; show a count before applying.
- History import is not in scope.

### Cleanup
- Not on the 1 s path. Main path: raw transcript + find/replace (+ provider formatting if the benchmark shows it helps). LLM cleanup runs only on its own hotkey or mode. Transcript is wrapped as data in the prompt.

### Storage
- History in system SQLite (`libsqlite3`) behind a small wrapper, no dependency. Audio as FLAC files with a retention period (lead, 2026-10-16): a transcribed dictation keeps its audio 1, 7 (default) or 30 days or forever, counted from its transcript; then only the file goes, never the row, its text or the usage ledger. Audio without a transcript (queued, failed, cancelled, refused) stays until it is transcribed or the owner deletes it. Retention runs on events only: at launch after the hotkey tap starts, after each transcribed dictation (live or by a retry), and when the setting changes; it works in batches, and each batch reads the setting as it is then. A new install gets 7 days; an install that already has dictations when retention first runs gets Forever, so an update never deletes audio unasked. A shorter period asks before it deletes. Only files inside the audio folder are removed, and a file that cannot be removed keeps its row unmarked. Keys in the Keychain via the Security framework.

### Tooling
- XcodeGen (`project.yml`; generated project gitignored), swift-format, SwiftLint strict, Swift 6 language mode with strict concurrency. One `make check` target that agents and humans must pass.
- Benchmark harness in `bench/` (bun, TypeScript). Personal data and results live outside git in the owner's runbooks folder.

### Phases
1. Core loop: hotkey state machine, prepared audio engine and capture, OpenRouter provider, paste with restore, indicator with mic level, offline queue with retry, latency log, memory spike.
2. Dictionary (keyterms + find/replace) with Wispr import, microphone choice and preference order, indicator position (bottom center, left, right), xAI and Azure direct providers, cleanup hotkey.
3. Per-app modes, History window, learning from corrections, usage and cost tracker, context awareness (off by default).

### Polish and learning (phase 2.5, lead decisions 2026-10-15; owner may override)

Plans: `docs/research/ux-polish.md` (49 items, IDs used below) and `docs/research/auto-learning.md`. Text rules: `CODING_STANDARDS.md`, "User-facing text".
- Onboarding is its own window: Welcome, Microphone, Accessibility, key with "Get a Key…" and a free key check, Wispr Flow import (only when Wispr Flow is installed and the dictionary is open), Try It, Done with launch at login. The order and the footer buttons are `OnboardingFlow` in KotobaCore. It opens on first launch and from "Finish Setting Up kotoba…"; no permission prompt appears before its step. A grant shows on its step and the owner clicks Continue; the permission steps have no Skip (0.3.0, stories 37a-37d). Keys show as symbols only. Price text: "a few cents per hour" plus the provider's pricing link.
- Readiness (mic access, Accessibility, key/endpoint) is one App value used by the menu status line, onboarding and the menu bar icon.
- Settings panes: General, Speech (was Providers), Dictionary, Microphone. General holds the cleanup chord and model, launch at login (default on), sounds and indicator position; the menu keeps status, Microphone and Speech Model.
- xAI direct and Azure direct sit under "Advanced" in the Speech pane, with no "untested" label.
- Error pills carry one action button and stay 8 s (hover pauses). `rejected` carries a reason (no credit, empty transcript, other).
- Failed dictations retry by themselves when the network returns (story 22, not built in phase 1).
- Learning (story 32), first build: a pure `CorrectionDetector` in KotobaCore, a `dictionary_suggestions` table, a Suggestions section in the Dictionary pane with a menu count, and "Fix Last Dictation…" (edit the last transcript, learn from the diff, copy the fixed text; no re-paste). Suggest and confirm, never auto-add. Identifiers, names and acronyms are learned; paths, URLs and numbers are not. A common heard word gives a term only, never a rule (applies to the Wispr import too). No LLM review until the local filters measure under 80% precision on the Wispr pairs.
- Later learning steps, in order: Accessibility readback after paste (after a spike on the owner's apps), history mining (with the History window), context sources (off by default).

### Owner round 2026-10-16 (phase 2.6; overrides phase 2.5 where they differ)

- No patchwork: each feature is built as the root design, event-driven, with no work at idle (no polling timers where an event exists). Each change reports its measured cost (idle footprint, hot path).
- Dictation chord is user-set (overrides "⌃⌥⌘ fixed"). A shortcut recorder in General and in onboarding accepts modifier-only chords (⌃⌥⌘, fn, a right-side modifier) and modifier + key. Tap/hold rules do not change. The cleanup chord uses the same recorder. A chord that clashes with the other chord is refused with a reason.
- Hands-free and Push to talk are two recorders in General and onboarding (owner, 2026-10-16). Push to talk may be ⌥, ⌃, fn or any right-side modifier alone: a shortcut press is shorter than the threshold, so it is dropped; the recorder notes that such shortcuts open the mic for a moment. ⇧ alone and ⌘ alone (left or either side) are refused, because people hold ⇧ while they type capitals and hold ⌘ while they pause before a shortcut, longer than the threshold (lead review, 2026-10-16); two modifiers with ⌘ are refused for the same reason, as for Hands-free. Push to talk saved as the Hands-free chord, or reset, is stored as none, so it follows a new Hands-free chord; a Push to talk chord the owner recorded stays when Hands-free changes, even to the same chord. Clash rules cover both: neither may be the cleanup chord or hold the whole cleanup chord, and Paste Last may not be either chord or hold either one on the way (its key does not count as a key typed during the press, so the dictation would start). Copy Last follows the Paste Last rules and may not be the Paste Last chord; it is ⌃⌘C by default, as the owner had it in Wispr Flow (lead, 2026-10-17), unless that clashes with the saved chords, and it copies at its press, since it posts no key. A cleanup or Hands-free chord may hold Push to talk on the way (⌃⌥⇧⌘ holds ⌥): the press follows the chord with more keys before the announcement, as ⇧ makes cleanup today; only a hold of ⌥ alone past the threshold before the other keys stays push to talk.
- Pills with an action and a timer (Esc Undo, error pills, learned word) show a bar that starts full and empties over the timer. Hover pauses the timer and the bar.
- Microphone: when Bluetooth is the output, the default stays the built-in mic. The user may still choose a Bluetooth mic (AirPods). kotoba then shows a warning (call-quality audio, it interrupts playback) in the menu and the Microphone pane. Capture opens only the chosen device and never changes the system default input or pulls AirPods into call mode when another mic is chosen.
- Learning is automatic (overrides "suggest and confirm, never auto-add" for strong candidates). After a paste, kotoba follows the focused text field through Accessibility notifications, for a bounded time, and detects the user's edit of the pasted text. A strong candidate is added to the dictionary at once, and the pill shows it with a sparkle icon, the word and Undo (bar rule). Weak candidates go to Suggestions. "Fix Last Dictation…" stays for apps without readable text (terminals).
- Indicator: more glass (Liquid Glass, measured cost). Setting "Show indicator": "While dictating" (default) or "Always". When shown at idle, a click starts and stops a dictation (tap semantics).
- Order after this round: History window; usage and cost tracker; audio retention; per-app modes (each dictation records its front app, which feeds usage); Insights page (words per minute, words dictated, fixes, apps, streak); the rest of phase 3. Research tracks: what makes kotoba better than Wispr Flow, accuracy, languages (only languages the chosen model supports, from a picked list; Hinglish if a model supports code-switching). Snippets last.
- From `docs/research/beyond-wispr.md` (owner, 2026-10-16 01:00 IST). Build now:
  - idea 3, submit after paste: Return sent after the paste, by a spoken end phrase or a stop gesture;
  - idea 4, a live "no sound" warning while recording;
  - idea 2 (optional to the owner, small): Paste Last, Copy Last, and Paste Raw after cleanup.
  Later:
  - idea 1, context terms from the active repo and session (privacy decision open: on or off by default, story 34);
  - idea 5, rank and cap dictionary terms per request (risk: it can drop a needed term).

### Wispr Flow gaps (lead, 2026-10-17)

From the Wispr Flow survey (`<runbooks>/2026-10-17-wispr-flow-survey/kotoba-plan.md`, items 2, 4, 5, 7, 10):
- Copy Last has its own chord, ⌃⌘C by default (Hotkey state machine above).
- History: Transcribe Again sends a row's kept audio once more, with the current speech model or another one whose key is saved, and keeps the new text in place of the old; nothing is pasted, and a miss keeps the old text. The toolbar's Retry does it for a selected row with text. Play plays a row's kept audio (Space too) and stops when a dictation starts; Show Audio in Finder selects the file.
- The Modes pane shows one example per mode: what the owner says and what that mode's cleanup pastes, from the first example in its prompt.
- The menu bar menu has Add Word…, which opens Dictionary with the add sheet.

### Per-app modes (story 29; lead decisions 2026-10-16)

Design and evidence: `docs/research/per-app-modes.md`.
- Two modes in v1, Code and Writing. A mode sets the cleanup prompt and "Clean up every dictation" (off by default for both). Apps map to a mode by bundle ID, from standard lists the owner edits; every other app uses Code. Only the owner's changes to the standard lists are saved, so a later build's new standard apps reach them too.
- The app in front at the stop decides the mode (the same rule as submit's Return); key-down only warms the cleaner and marks the pill. Esc keeps the app and the mode of the Esc. A retry cleans in the mode the record keeps.
- The cleanup chord cleans with the mode's prompt. A live cleanup has a 5 s deadline on the pipeline clock; past it the raw text pastes, the pill says so, and the late answer's cost still goes to the ledger. A retry has no paste waiting, so its cleanup waits for the cleaner's own timeout.
- Speech model, language and website rules per mode: later, not v1.
- The Writing prompt ships in a release only after its benchmark passes (`docs/release.md`).

### Wispr Flow transition
- The owner keeps Wispr Flow until kotoba passes the gates and one week of daily use.

## Testing Decisions

- Good tests check external behaviour through a seam: given events in, assert outcomes out (text pasted, clipboard restored, audio kept, latency recorded). They do not assert internal calls or private state.
- Main seam (confirmed by the owner 2026-10-15): the dictation pipeline core, a pure Swift module driven by injected ports - hotkey events in; audio source, transcription provider, paster, pasteboard, clock and store as ports. Fakes for each port let tests cover the state machine (tap vs hold, Esc, 10-minute warning), offline queue and retry, clipboard restore rules, and latency-log timestamps without a mic, network or Accessibility.
- Provider seam: the benchmark harness is the acceptance test for each `TranscriptionProvider` route against real APIs (paid; runs only with an explicit go). Unit tests cover request building and response parsing against recorded fixtures.
- System checks: an idle-memory probe (`footprint`) and a latency report (p50/p90 from the latency log) are scripts, run before each phase is declared done.
- Benchmark scorer (WER, term recall) has unit tests in `bench/`.
- No prior art in this repo (new project).

## Out of Scope

- Local or on-device speech models.
- Live words while speaking (streaming display). Streaming upload during speech is a fallback only if batch misses the latency gate.
- Mac App Store distribution (sandbox blocks the event tap and synthetic Cmd-V).
- Windows, Linux, iOS.
- Accounts, sync, telemetry, analytics, crash reporting services.
- Languages other than English in v1.
- Fn/Globe key as the default hotkey (owner uses Ctrl+Opt+Cmd).

## Further Notes

- Benchmark kotoba-bench-v1 (go given 2026-10-15): 275 of the owner's Wispr Flow clips (275 clips with audio, avg 21.9 s, 210 from cmux), references from the owner's edited text where available; Grok and MAI via OpenRouter; Wispr's own ASR as a free baseline; 3 cleanup LLMs on the 18 clips the owner really edited plus a 100-clip sample; cost cap $2, spent $1.00. Results: MAI + phraseList via OpenRouter best (WER 8.1%, term recall 73.2%, sequential latency p50 881 / p90 1461 ms for 10-20 s clips); Grok slower and less accurate; no cleanup LLM beat the raw transcript on WER. Report in the runbooks folder.
- OpenRouter passes provider options through (`provider.options.<tag>`): MAI phraseList and Grok keyterms both work through it (kotoba-bench-v1: MAI term recall 58.7% -> 73.2%), but this is not in OpenRouter's docs.
- Weekly watch (proposed, not scheduled): VoiceInk releases, the Artificial Analysis STT leaderboard, Grok and MAI prices.

## Unresolved Questions

1. MAI-Transcribe-2 price after 2026-12-31 and phrase-list limits are not published.
2. Default route (decided 2026-10-15 from kotoba-bench-v1 and `docs/research/mai-routing.md`): MAI-Transcribe-2 + phraseList via OpenRouter. Neither OpenRouter nor Vercel AI Gateway can pick an Azure region; direct Azure `centralindia` stays the fallback if real use misses the latency gate.
3. Wispr Flow's live database: `~/Library/Application Support/Wispr Flow/flow.sqlite` (+ `-wal`), found by a directory listing on 2026-10-15. `Dictionary.isDeleted` is TINYINT(1), integer 0/1 (backup copy, 2026-10-15). Resolved.
4. Azure direct sends no `transcribeStyle`, so Azure applies its default (`verbatim` per Microsoft's docs). Which style the OpenRouter route used in kotoba-bench-v1 is unknown. Check on the first live Azure test: compare the direct output with the OpenRouter output for the same clip.
