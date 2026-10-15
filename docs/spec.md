# kotoba - spec v1

Status: agreed with the owner on 2026-10-15 (grill session). Research behind each decision: `docs/research/`.

## Problem Statement

The owner is a developer in India on an Apple Silicon Mac. They dictate about 200 words per minute, mostly prompts for Claude Code, Codex and Cursor, typed into terminals (cmux), editors and browsers. The prompts are full of identifiers, file names, paths and CLI flags.

They pay about Rs 400 a month for Wispr Flow Pro. Wispr mis-transcribes technical terms often. (Wispr's own counter shows about 10,000 corrected words over about 73,000 words, but that counter includes its formatter's changes; the owner's real edits are far fewer, see `docs/research/auto-learning.md`.) Wispr is an Electron app (reported at 0.75-1 GB RAM) and its measured average end-to-end latency on the owner's machine is 1,254 ms (average network part 372 ms, from Wispr's own local history).

Cloud speech-to-text through the owner's own API key costs about $0.10 per hour of audio. No existing app combines: native and light, cloud-only, own keys, top-accuracy models (xAI Grok Voice Transcribe 2.0, Microsoft MAI-Transcribe-2), fast release-to-paste, and a permissive licence.

## Solution

A native macOS menu-bar dictation app, kotoba. The owner taps a chord, speaks, taps again, and the text appears in the focused app within about one second. Transcription runs in the cloud with the owner's own keys, stored in the Keychain. There are no accounts and no telemetry. The app is small in memory, starts capturing at the instant of the key press, never loses a dictation, and improves technical accuracy through a personal dictionary sent to the model as keyterms.

The app is open-source (Apache-2.0) and distributed as a notarized DMG on GitHub Releases once the MVP passes its gates.

## User Stories

### Recording and hotkey
1. As a developer, I want to tap Ctrl+Opt+Cmd to start recording and tap it again to stop, so that I can dictate long prompts without holding keys.
2. As a developer, I want a hold of the chord longer than about 400 ms to act as push-to-talk, so that short dictations need one gesture.
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
35. As a user, I want a menu-bar app with no Dock icon, so that it stays out of the way.
36. As a user, I want launch at login, so that dictation is always available.
37. As a user, I want onboarding that grants Microphone, Accessibility and Input Monitoring permissions and explains each, so that setup works the first time.
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
- Minimum macOS 26. Bundle ID `tech.teensy.kotoba`. Signed with the owner's Developer ID (team 7U6G55576W), notarized. Every development build is signed with the same identity so TCC permissions and Keychain access survive rebuilds.
- AppKit `NSStatusItem` for the menu bar; the recording indicator is an AppKit panel using `NSGlassEffectView`.
- SwiftUI only for windows that open on demand (Settings, History). Measured 2026-10-15 (`docs/research/memory-spike.md`): status item + glass panel + prepared engine idles at about 17 MB; a SwiftUI window adds about 15 MB that stays after close. The owner accepts SwiftUI for these windows for now; AppKit replacement is a later option if memory matters.
- No WebKit, no SwiftData, no local speech models. `NSSupportsAutomaticTermination` off.

### Gates
- Latency gate: from stop tap to Cmd-V sent, for 10-20 s clips on the owner's home network: p50 <= 1.0 s, p90 <= 1.5 s. Measured by the in-app latency log.
- Memory: soft target, performance is a top-tier priority. Original aim was under 50 MB idle; no comparable app reaches it (Jot about 90 MB). A day-1 spike (empty status item + prepared audio engine) measures the floor with `footprint`.

### Hotkey state machine
- Chord: Ctrl+Opt+Cmd (modifier-only, so it works during secure input). Captured with a CGEventTap on flagsChanged, callback kept short and off the main thread, tap re-enabled when the system disables it.
- Tap (chord down and up under about 400 ms): start; next tap: stop and paste. Hold over the threshold: push-to-talk, stop on release. Esc during recording: cancel, keep audio. After Esc the indicator shows Undo for 5 s (mic off during the window); clicking Undo or tapping the chord in that window resumes the same recording, appending to the same audio file, and the next stop transcribes the whole recording. After 5 s the cancel is final. Threshold tuned after owner testing.
- Secure input state (`IsSecureEventInputEnabled`) shown in the indicator.
- Indicator position (phase 2, like Wispr Flow): three anchors, on the screen that holds the focused window. Bottom center (default): a horizontal pill just above the Dock or the screen bottom. Left edge and right edge: a vertical pill at mid-height while listening or transcribing; states with text (warnings, Cancelled + Undo, errors) stay a horizontal pill at the edge. Drag the indicator; during the drag the three anchors show as drop targets, and on release it snaps to the nearest one. The anchor is saved in UserDefaults. An "Indicator Position" submenu sets it too. The pill respects the visible frame (Dock, menu bar, notch).

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
- History in system SQLite (`libsqlite3`) behind a small wrapper, no dependency. Audio as FLAC files with a retention period. Keys in the Keychain via the Security framework.

### Tooling
- XcodeGen (`project.yml`; generated project gitignored), swift-format, SwiftLint strict, Swift 6 language mode with strict concurrency. One `make check` target that agents and humans must pass.
- Benchmark harness in `bench/` (bun, TypeScript). Personal data and results live outside git in the owner's runbooks folder.

### Phases
1. Core loop: hotkey state machine, prepared audio engine and capture, OpenRouter provider, paste with restore, indicator with mic level, offline queue with retry, latency log, memory spike.
2. Dictionary (keyterms + find/replace) with Wispr import, microphone choice and preference order, indicator position (bottom center, left, right), xAI and Azure direct providers, cleanup hotkey.
3. Per-app modes, History window, learning from corrections, usage and cost tracker, context awareness (off by default).

### Polish and learning (phase 2.5, lead decisions 2026-10-15; owner may override)

Plans: `docs/research/ux-polish.md` (49 items, IDs used below) and `docs/research/auto-learning.md`. Text rules: `CODING_STANDARDS.md`, "User-facing text".
- Onboarding is its own window, 6 steps (Welcome, Microphone, Accessibility, key with "Get a Key…" and a free key check, Try It, Done with launch at login). It opens on first launch and from "Finish Setting Up kotoba…"; no permission prompt appears before its step. The dictation chord stays ⌃⌥⌘ (no picker in v1). Price text: "a few cents per hour" plus the provider's pricing link.
- Readiness (mic access, Accessibility, key/endpoint) is one App value used by the menu status line, onboarding and the menu bar icon.
- Settings panes: General, Speech (was Providers), Dictionary, Microphone. General holds the cleanup chord and model, launch at login (default on), sounds and indicator position; the menu keeps status, Microphone and Speech Model.
- xAI direct and Azure direct sit under "Advanced" in the Speech pane, with no "untested" label.
- Error pills carry one action button and stay 8 s (hover pauses). `rejected` carries a reason (no credit, empty transcript, other).
- Failed dictations retry by themselves when the network returns (story 22, not built in phase 1).
- Learning (story 32), first build: a pure `CorrectionDetector` in KotobaCore, a `dictionary_suggestions` table, a Suggestions section in the Dictionary pane with a menu count, and "Fix Last Dictation…" (edit the last transcript, learn from the diff, copy the fixed text; no re-paste). Suggest and confirm, never auto-add. Identifiers, names and acronyms are learned; paths, URLs and numbers are not. A common heard word gives a term only, never a rule (applies to the Wispr import too). No LLM review until the local filters measure under 80% precision on the Wispr pairs.
- Later learning steps, in order: Accessibility readback after paste (after a spike on the owner's apps), history mining (with the History window), context sources (off by default).

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
