# kotoba - spec v1

Status: agreed with the owner on 2026-10-15 (grill session). Research behind each decision: `docs/research/`.

## Problem Statement

The owner is a developer in India on an Apple Silicon Mac. They dictate about 200 words per minute, mostly prompts for Claude Code, Codex and Cursor, typed into terminals (cmux), editors and browsers. The prompts are full of identifiers, file names, paths and CLI flags.

They pay about Rs 400 a month for Wispr Flow Pro. Wispr mis-transcribes technical terms often: about 10,000 manual fixes over about 73,000 words. Wispr is an Electron app (reported at 0.75-1 GB RAM) and its measured average end-to-end latency on the owner's machine is 1,254 ms (average network part 372 ms, from Wispr's own local history).

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
26. As a Wispr Flow user, I want a one-time import of my Wispr dictionary, so that I start with my existing vocabulary.
27. As a developer, I want a second hotkey or mode for LLM cleanup (filler removal, punctuation, "make this a clean prompt"), so that I choose when to pay its latency.
28. As a developer, I want the cleanup prompt to treat my transcript as data, so that the LLM never answers or obeys my dictated prompt.

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
- Tap (chord down and up under about 400 ms): start; next tap: stop and paste. Hold over the threshold: push-to-talk, stop on release. Esc during recording: cancel, keep audio. Threshold tuned after owner testing.
- Secure input state (`IsSecureEventInputEnabled`) shown in the indicator.

### Audio
- No pre-roll and no always-open mic: the owner rejected the always-on orange mic dot (2026-10-15). The audio engine is prepared while idle but not started; it starts on key-down (about 20-40 ms) before any UI or sound work; capture is written to disk from the first buffer; one extra buffer is captured after stop. The mic is open only while recording. Verified 2026-10-15 by the owner: a prepared-but-not-started engine shows no orange mic dot.
- Route changes rebuild the engine. When AirPods are the output, use the built-in mic.
- Upload format: 16 kHz mono FLAC (native in `AVAudioFile`). Opus only for providers that accept it, if the benchmark shows a gain.

### Transcription providers
- One `TranscriptionProvider` protocol: input is an audio file plus options (language, vocabulary terms); output is text plus usage (audio seconds, cost when known) and timing. Each provider owns one long-lived URLSession, warmed at key-down.
- Routes, in order: OpenRouter (owner already has a key; one key for both models; adds one hop), then xAI direct (`POST /v1/stt`, multipart, up to 100 keyterms of 50 chars) and Azure MAI-Transcribe-2 direct (fast transcription REST, `phraseList`, Central India region available). Order of the direct routes follows the benchmark.
- MAI-Transcribe-2 is public preview; its $0.10/h price is a promotion until 2026-12-31.

### Paste
- Save all pasteboard types, write the transcript marked transient/concealed, post Cmd-V via CGEvent, restore after about 1.0 s only if the pasteboard did not change since. No fixed pre-paste sleep. A new paste never waits for a previous restore.
- AX value insertion is not used as the main path (Electron apps report false success).

### Cleanup
- Not on the 1 s path. Main path: raw transcript + find/replace (+ provider formatting if the benchmark shows it helps). LLM cleanup runs only on its own hotkey or mode. Transcript is wrapped as data in the prompt.

### Storage
- History in system SQLite (`libsqlite3`) behind a small wrapper, no dependency. Audio as FLAC files with a retention period. Keys in the Keychain via the Security framework.

### Tooling
- XcodeGen (`project.yml`; generated project gitignored), swift-format, SwiftLint strict, Swift 6 language mode with strict concurrency. One `make check` target that agents and humans must pass.
- Benchmark harness in `bench/` (bun, TypeScript). Personal data and results live outside git in the owner's runbooks folder.

### Phases
1. Core loop: hotkey state machine, prepared audio engine and capture, OpenRouter provider, paste with restore, indicator with mic level, offline queue with retry, latency log, memory spike.
2. Dictionary (keyterms + find/replace) with Wispr import, xAI and Azure direct providers, cleanup hotkey.
3. Per-app modes, History window, learning from corrections, usage and cost tracker, context awareness (off by default).

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

- Benchmark kotoba-bench-v1 (go given 2026-10-15): 275 of the owner's Wispr Flow clips (avg 32.7 s, 210 from cmux), references from the owner's edited text where available; Grok and MAI via OpenRouter; Wispr's own ASR as a free baseline; 3 cleanup LLMs on the 135 edited clips; cost cap $2, expected under $1.
- OpenRouter documents no keyterm passthrough; keyterm gains need the direct routes.
- Weekly watch (proposed, not scheduled): VoiceInk releases, the Artificial Analysis STT leaderboard, Grok and MAI prices.

## Unresolved Questions

1. MAI-Transcribe-2 price after 2026-12-31 and phrase-list limits are not published.
2. Which provider route becomes the default depends on kotoba-bench-v1.
