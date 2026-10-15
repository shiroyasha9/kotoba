# Mac dictation: fork vs. build - landscape and macOS facts

Research date: 2026-10-15. Method: read-only GitHub API (`gh api`, `gh issue list`, `gh search`), web search, Apple docs. Nothing was cloned, built or run. GitHub numbers (stars, last push) are from `gh api repos/<repo>` on 2026-10-15. "UNCONFIRMED" marks claims that come from one secondary or vendor source, or from my own calculation.

Owner's target: cloud STT only (xAI Grok Voice Transcribe 2.0 + Microsoft MAI-Transcribe-2 on Azure), idle RAM under ~50 MB, ~1 s key-up to paste, Fn / modifier-only hold + toggle, zero-clip start, paste with clipboard restore, notch/floating level indicator, dictionary (keyterms + find/replace), optional LLM cleanup with per-app prompts, history with audio, learn-from-corrections, menu bar only, keep audio and retry on network failure, usage/cost tracker, keys in Keychain, no accounts or telemetry.

---

## Part A - alternatives landscape

### A.1 Summary table (open source)

| App | Repo | License | Stack | Stars | Last push (UTC) | Cloud STT BYO key | Custom provider | Fn / PTT | Idle RAM reported |
|---|---|---|---|---|---|---|---|---|---|
| Jot (Google Gemini demo) | https://github.com/google-gemini/jot-gemini-transcribe-macOS | Apache-2.0 | Swift native (SwiftUI + JotCore package) | 492 | 2026-08-27 | Gemini only (`gemini-3.5-transcribe`) | Code change needed | Fn hold, fn+Space lock, Esc cancel | ~90 MB idle, measured by the author |
| FreeFlow | https://github.com/zachlatta/freeflow | MIT | Swift native, no SPM deps, `swiftc` Makefile | 2,908 | 2026-10-12 | Groq default; any OpenAI-compatible URL | Base URL + model only | Fn hold, Cmd-Fn toggle, custom | Not reported |
| TypeWhisper | https://github.com/TypeWhisper/typewhisper-mac | GPL-3.0 | Swift native, plugin SDK | 1,855 | 2026-10-15 | Groq, OpenAI, xAI/Grok STT, Microsoft AI (MAI), Soniox, Cohere, others | Plugin SDK | PTT, toggle, hybrid; single-modifier keys; Fn issue fixed | Not reported (local-LLM leak issues only) |
| VoiceInk | https://github.com/Beingpax/VoiceInk | GPL-3.0 (GitHub shows NOASSERTION) | Swift native, SwiftData | 6,816 | 2026-10-15 | Groq, ElevenLabs, Deepgram, Mistral, Gemini, Soniox, Speechmatics, AssemblyAI, xAI (Grok Voice Transcribe 2.0), Cartesia, OpenRouter | `CloudProvider` protocol + custom OpenAI-compatible models | PTT + hybrid, Fn | Not reported |
| Hex (legacy Swift) | https://github.com/kitlangton/Hex | MIT | Swift native (TCA) | 2,901 | 2026-10-14, archived | None (local only) | n/a | Modifier-only hold | Not reported |
| HEX (new) | https://github.com/anomalyco/hex | MIT | Rust + Swift bits | 335 | 2026-10-15 | None for dictation (local models) | n/a | Option hold | Not reported |
| Handy | https://github.com/cjpais/Handy | MIT | Tauri (Rust + webview) | 33,840 | 2026-10-15 | None (offline only) | n/a | Hold or toggle; Fn only on Apple keyboards | No figure found |
| OpenWhispr | https://github.com/OpenWhispr/openwhispr | MIT | Electron 41 + React + Swift helpers | 9,446 | 2026-10-15 | OpenAI, Groq, xAI (Grok STT), Mistral, Gemini, Deepgram, AssemblyAI, Corti, Tinfoil | Self-hosted / custom ASR shim | Globe key listener | No figure found |
| Whispering / Epicenter | https://github.com/EpicenterHQ/epicenter (apps/whispering) | Mixed (NOASSERTION) | Tauri + Svelte | 4,823 | 2026-10-15 | One OpenAI-compatible endpoint | Base URL + model | Current rewrite: none | n/a |
| VoiceTypr | https://github.com/ideaplexa/voicetypr | AGPL-3.0 | Tauri + Rust + React | 735 | 2026-10-12 | Soniox, OpenAI, Groq, Deepgram, Cohere | OpenAI-compatible for formatting | PTT + toggle | Not reported |
| FluidVoice | https://github.com/altic-dev/FluidVoice | GPL-3.0 | Swift native | 12,175 | 2026-10-13 | None for STT (local only); cloud only for AI cleanup | Custom LLM providers | Global hotkey | Not reported |
| BetterWispr | https://github.com/opennookorg/betterwispr | Apache-2.0 | Swift native | 334 | 2026-10-15 (created 2026-10-07) | Sarvam, Smallest, any OpenAI-compatible | URL + model | Option-Space hold/toggle | Not reported |

### A.2 Per-app notes

**Jot (google-gemini/jot-gemini-transcribe-macOS)**
- Apache-2.0, "not an officially supported Google product", Swift menu bar app; created 2026-08-19, last commit 2026-08-27, release v0.4.0 on 2026-08-27 (`gh api`). Looks like a finished demo, not an active product. https://github.com/google-gemini/jot-gemini-transcribe-macOS
- Design matches the owner's list closely (README "How it works"): Fn hold, fn+Space hands-free, Esc cancel; audio to CAF on disk from t=0; FLAC at key-up; AX -> guarded paste -> "copied" chip insertion ladder with clipboard restore; offline queue that drains on reconnect; Retry from History; dictionary terms sent with the audio; per-app tone; key in Keychain; "no account, no analytics". https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/README.md
- Measured: "idle 0.0% CPU / ~90MB; recording ~13% CPU"; capture prewarm 75-147 ms -> 22-25 ms. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/docs/design/latency-audit-2026-08-19.md
- Dependencies (plan): KeyboardShortcuts, Sauce, Sparkle, GRDB - all MIT; FLAC via CoreAudio, no libopus. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/docs/design/PLAN.md
- Gaps for the owner: Gemini-only client; no cost tracker; per-app tone is a fixed bundle-ID map, not free per-app prompts; no learn-from-corrections; ~90 MB idle is above target.
- Fit: best architecture donor and the cleanest fork base. Swap the transcription client for xAI + Azure.

**FreeFlow (zachlatta/freeflow)**
- MIT, Swift, built with `swiftc` from a Makefile, signs dev builds with a local "FreeFlow Dev" identity. https://github.com/zachlatta/freeflow/blob/main/Makefile , https://github.com/zachlatta/freeflow/blob/main/CONTRIBUTING.md
- Groq by default; "OpenAI-compatible providers: ... configure a custom model and API URL"; Fn hold, Cmd-Fn toggle; custom vocabulary; context-aware cleanup; edit mode; "There is no FreeFlow server". https://github.com/zachlatta/freeflow/blob/main/README.md
- Code facts: CGEventTap `.defaultTap` on `.cgSessionEventTap` for flagsChanged/keyDown/keyUp, re-enables on `tapDisabledByTimeout` (Sources/GlobalShortcutBackend.swift L45-L107); snapshot of all pasteboard items, transient/concealed markers, Cmd-V via CGEvent, restore after `clipboardRestoreDelay = 1.0` s if changeCount unchanged or clipboard still holds the transcript (Sources/AppState.swift L65-L120, L241, L3229-L3358); history keeps 20 items with audio (AppState.swift L242, L729). https://github.com/zachlatta/freeflow/tree/main/Sources
- Audio: starts an `AVCaptureSession` on key-down, no pre-roll buffer (Sources/AudioRecorder.swift L569-L690).
- Gaps: xAI `/v1/stt` (multipart with `keyterm` fields) and Azure MAI are not OpenAI-compatible, so new clients are needed (UNCONFIRMED whether xAI also offers an OpenAI-compatible transcription route). `AppState.swift` is 145 KB, a monolith. Open issue: Groq uploads time out at the 20 s default and retried transcriptions never paste. https://github.com/zachlatta/freeflow/issues/331
- Fit: good small MIT base; more surgery than Jot for zero-clip and offline queue.

**TypeWhisper (TypeWhisper/typewhisper-mac)**
- GPL-3.0, Swift. Cloud engines include "Groq Whisper, OpenAI Whisper, Soniox, Smallest Pulse, xAI/Grok STT ..."; push-to-talk, toggle, hybrid; single-modifier hotkeys; notch/overlay indicators; dictionary terms + corrections + auto-learn; per-app/per-website workflows; history with retention; Dictation Recovery keeps failed recordings 24 h for retry; usage statistics. https://github.com/TypeWhisper/typewhisper-mac/blob/main/README.md
- Has a Microsoft AI plugin that calls Azure `speechtotext/transcriptions:transcribe` with MAI models and a phrase list. https://github.com/TypeWhisper/typewhisper-mac/blob/main/TypeWhisperPluginSDK/Plugins/MicrosoftAIPlugin/MicrosoftAIPlugin.swift
- Fn/Globe in PTT and hybrid mode was broken and is closed (2026-04-16). https://github.com/TypeWhisper/typewhisper-mac/issues/310
- "Correction learning" and iCloud sync are Premium (Polar license); GPL allows removing the gate in a private fork. README L163-L176, L259.
- Heavy: links WhisperKit, FluidAudio, MLX, mlx-audio, onnxruntime, MCP SDK, Sparkle (Package.resolved). https://github.com/TypeWhisper/typewhisper-mac/blob/main/TypeWhisper.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved . Idle RAM with only cloud engines: no data (UNCONFIRMED). Reported RAM issues concern local LLMs: https://github.com/TypeWhisper/typewhisper-mac/issues/800
- Fit: the only app that already supports both target providers. Best "use as-is now" option; poor base for a lean fork (1,146 files).

**VoiceInk (Beingpax/VoiceInk)**
- GPL-3.0 per README badge; "not accepting pull requests"; macOS 15+. https://github.com/Beingpax/VoiceInk/blob/main/README.md
- Cloud provider registry includes `XAIProvider` with model `grok-voice-transcribe-2.0` (batch + streaming) and custom vocabulary as `keyterm` fields. https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Infrastructure/Providers/Transcription/Cloud/XAIProvider.swift , https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Infrastructure/Providers/Transcription/Cloud/CloudProvider.swift . No Azure/MAI provider (code search for "azure" and "MAI-Transcribe" returned nothing).
- 7-day trial + Polar license in code; `make local` uses a `LOCAL_BUILD` flag (UNCONFIRMED that this removes the license gate). https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Licensing/State/LicenseViewModel.swift , https://github.com/Beingpax/VoiceInk/blob/main/BUILDING.md
- Stability complaints from a Pro user (2026-09-28): Esc leaks to the frontmost app, emoji shortcut hijacked while VoiceInk runs. https://github.com/Beingpax/VoiceInk/issues/983 . Cloud transcription blocked by license validation behind a corporate proxy. https://github.com/Beingpax/VoiceInk/issues/1010
- Heavy deps: whisper.cpp, FluidAudio, MLX, swift-transformers, Sparkle, SwiftData. Package.resolved in repo.
- Fit: big, GPL, single-maintainer, closed to PRs. Useful as a reference for xAI request shape.

**Hex (kitlangton/Hex, legacy Swift) and HEX (anomalyco/hex)**
- Legacy Swift repo is archived; "New app and source: github.com/anomalyco/hex" (`gh api`). New HEX is Rust, local-first, Option hold, on-device models. https://github.com/anomalyco/hex
- Legacy Swift code has a "Super Fast Mode": warm AVAudioEngine, 1.0 s ring buffer, 0.45 s pre-roll prepended; UI text says "macOS will keep showing the microphone indicator while this mode is armed." https://github.com/kitlangton/Hex/blob/main/Hex/Clients/SuperFastCaptureController.swift (L57-L58, L325-L330), https://github.com/kitlangton/Hex/blob/main/Hex/Features/Settings/GeneralSectionView.swift (L74-L80)
- Fit: no cloud STT. Parts donor only (MIT).

**Handy (cjpais/Handy)**
- MIT, Tauri. "This happens on your own computer without sending any information to the cloud." No cloud STT. README "fn and Globe Key Shortcuts": Fn works only on Apple keyboards. README "Bluetooth Headset Microphones": use the built-in mic to avoid HFP quality drop. https://github.com/cjpais/Handy/blob/main/README.md
- Fit: wrong (local only, webview).

**OpenWhispr**
- MIT, Electron 41, React; "No data collection, no telemetry"; but also has OpenWhispr Cloud, notes sync, team spaces. https://github.com/OpenWhispr/openwhispr/blob/main/README.md
- Provider registry includes `xai` / `grok-stt`, Groq, OpenAI, Mistral, Gemini, Deepgram, AssemblyAI. https://github.com/OpenWhispr/openwhispr/blob/main/src/models/modelRegistryData.json
- Its Swift Globe listener sets `AppleFnUsageType` to "Do Nothing" through the private `TISUpdateFnUsageType` while it owns the key. https://github.com/OpenWhispr/openwhispr/blob/main/resources/macos-globe-listener.swift (L57-L79)
- Fit: Electron fails the RAM target. Reference only.

**Whispering / Epicenter**
- Whispering moved into the Epicenter monorepo. https://github.com/braden-w/whispering . The current `apps/whispering` README lists under "What is not supported": "System-wide dictation: global shortcuts, push-to-talk ... delivering text to the cursor". https://github.com/EpicenterHQ/epicenter/blob/main/apps/whispering/README.md . Last v7 release with the old feature set: v7.11.0, 2025-12-27 (`gh api .../releases`).
- Fit: none.

**VoiceTypr** - AGPL-3.0, Tauri; local default, lifetime license after trial; cloud STT Soniox, OpenAI, Groq, Deepgram, Cohere. https://github.com/ideaplexa/voicetypr/blob/main/README.md . Fit: low (Tauri, licensing, no xAI/Azure).

**FluidVoice** - GPL-3.0, Swift; STT providers are all local (Parakeet, Nemotron, Whisper, Apple Speech, Cohere); cloud only for "AI Enhancement"; keys in Keychain. https://github.com/altic-dev/FluidVoice/blob/main/README.md . Fit: low.

**BetterWispr** - Apache-2.0, Swift, local-first, "optional Sarvam AI, Smallest AI or any OpenAI-compatible endpoint", created 2026-10-07. https://github.com/opennookorg/betterwispr . Fit: too new to judge.

### A.3 Closed-source apps

| App | Stack | BYO key | Notes | Source |
|---|---|---|---|---|
| Spokenly | Not stated (UNCONFIRMED native) | Free tier BYOK: OpenAI, Deepgram, Groq (+ Soniox per one post) | "not open source and is not available on GitHub" | https://spokenly.app/open-source , https://spokenly.app/llms.txt |
| Superwhisper | Native (UNCONFIRMED) | BYOK behind Pro ($8.49/mo, $84.99/yr, $249.99 lifetime) per competitor pages | Competitor review says API keys stored as plaintext JSON (UNCONFIRMED); user saw ~900 MB with local LLM loaded | https://www.getvoibe.com/resources/superwhisper-pricing/ , https://feedback.superwhisper.com/board/p/let-s1-mini-unload-when-superwhisper-is-idle |
| MacWhisper | Native Swift (UNCONFIRMED) | Pro: OpenRouter, ElevenLabs Scribe, Deepgram Nova (vendor listing); Groq unconfirmed | Gumroad listing | https://goodsnooze.gumroad.com/l/macwhisper/bff2025p |
| Aqua Voice | Not confirmed | No BYOK (competitor claim); own Avalon model, Avalon API $0.39/h | Pro $8/mo annual | https://spokenly.app/comparison/aqua-voice , https://aquavoice.com/vs/spokenly |
| Wispr Flow | Electron v42.11.2; 699 MB on disk (Apple Silicon) | No BYOK | Windows build ~800 MB RAM idle and 8% CPU (competitor summary of user reports); Mac ~1 GB while recording in tl;dv's test; Wispr recommends 8 GB RAM | https://desktopinsights.com/apps/wispr-flow , https://spokenly.app/blog/wispr-flow-review , https://tldv.io/blog/wispr-flow-notetaker-review/ , https://docs.wisprflow.ai/articles/1036674442-supported-devices-and-system-requirements |
| Willow | "native code rather than Electron" per one review (UNCONFIRMED) | No BYOK found | Fn hold; free 2,000 words/week, $12/mo annual | https://makerstack.co/reviews/willow-review/ , https://willowvoice.com/redesign/pricing |

Wispr Flow RAM: no first-party or Mac-specific idle figure found. All numbers come from competitors (Spokenly, tl;dv). Treat ~0.75-1 GB as indicative only.

Note: a search hit about "memory three times Wispr Flow" on shandianshuo.featurebase.app is about a different app (Shandianshuo), not VoiceInk.

---

## Part B - macOS implementation facts

### B.1 Fn / Globe and modifier-only hotkeys

- Fn shows up as `CGEventFlags.maskSecondaryFn` on keyboard and flagsChanged events, "found primarily on laptop keyboards". https://developer.apple.com/documentation/coregraphics/cgeventflags/masksecondaryfn
- Modifier-only keys produce `flagsChanged`, not keyDown/keyUp. FreeFlow, VoiceInk, Jot all use a CGEventTap with `flagsChanged` in the mask. FreeFlow GlobalShortcutBackend.swift L45-L80; VoiceInk ShortcutMonitor.swift L120, L503 (https://github.com/Beingpax/VoiceInk/blob/main/VoiceInk/Features/Shortcuts/Coordination/ShortcutMonitor.swift); Jot EventTapEngine.swift L148-L151.
- Permissions (Apple DTS, Quinn): a global NSEvent monitor needs Accessibility; a CGEventTap needs Input Monitoring; check/request with `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`. Another reply in the same thread: `.defaultTap` (can modify/consume) triggers the Accessibility prompt, `.listenOnly` triggers Input Monitoring. https://developer.apple.com/forums/thread/122492
- `CGRequestListenEventAccess()` does not always add the app to the Input Monitoring list (macOS 15 report, no answer). https://developer.apple.com/forums/thread/828052
- IOHIDManager also falls under Input Monitoring (UNCONFIRMED by an Apple page in this pass). Not needed: every app studied uses CGEventTap or NSEvent monitors.
- Fn exists only on Apple keyboards; third-party keyboards handle Fn in firmware and send nothing. https://github.com/cjpais/Handy/blob/main/README.md ("fn and Globe Key Shortcuts")
- Globe conflict: System Settings > Keyboard > "Press 🌐 key to" maps to `com.apple.HIToolbox AppleFnUsageType` (0 Do Nothing, 1 Change input source, 2 Emoji & Symbols, 3 Start Dictation). https://github.com/yannbertrand/macos-defaults/blob/main/docs/keyboard/applefnusagetype.md
  - Jot: the Fn short-press action "is handled at the IOHID layer and CANNOT be blocked by an event tap - the only fix is ... 'Do Nothing'". Jot reads the pref and deep-links `x-apple.systempreferences:com.apple.Keyboard-Settings.extension`, and warns if Karabiner is installed. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/JotCore/Sources/HotkeyEngine/FnUsageAdvisor.swift
  - OpenWhispr: same finding ("WindowServer ahead of every event tap"); it calls private `TISGetFnUsageType` / `TISUpdateFnUsageType` (dlsym from Carbon) to set Do Nothing while it owns the key and restores it later; writing the pref directly "is ignored until the user's next login". https://github.com/OpenWhispr/openwhispr/blob/main/resources/macos-globe-listener.swift L57-L79
  - VoiceInk users report the emoji shortcut breaks while VoiceInk runs. https://github.com/Beingpax/VoiceInk/issues/983
- Fn+other key: cancel bare-Fn PTT if another key goes down while Fn is held (Fn+Arrow = Home). OpenWhispr globe listener L328+. VoiceInk had the same bug class: https://github.com/Beingpax/VoiceInk/issues/720
- Tap health: macOS disables a tap whose callback is slow (`tapDisabledByTimeout`); re-enable it and keep the callback short. FreeFlow GlobalShortcutBackend.swift L104-L107; Jot runs the tap on a dedicated thread and says the callback "must return fast (<~30ms or the tap gets disabled)" (UNCONFIRMED threshold). https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/docs/design/architecture.md L163

### B.2 Zero-clip start

- Audio I/O always has a delay before the first cycle, "roughly 100 ms for some transports", larger for others, not predictable. https://developer.apple.com/forums/thread/829743
- Jot measurements (M-series, 2026-08-19): engine start 75-147 ms cold -> 22-25 ms with a prewarmed (prepared) graph; HAL spin-up "≥21.3 ms floor, ~100 ms typical"; tap buffers arrive in ~100 ms chunks; teardown dropped a mean 52 ms (max 104 ms) of the last word until they drained one buffer past stop. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/docs/design/latency-audit-2026-08-19.md
- Jot README: "Preparing is not recording: no audio flows and no mic indicator appears until you actually hold the key." (Jot's claim; UNCONFIRMED by Apple docs.) https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/README.md
- Keeping the engine running = permanent orange dot. Hex's Super Fast Mode says so in its UI text, keeps a 1.0 s ring buffer, prepends 0.45 s pre-roll, and suspends warm capture on screen lock/sleep. https://github.com/kitlangton/Hex/blob/main/Hex/Features/Settings/GeneralSectionView.swift L74-L80 ; https://github.com/kitlangton/Hex/blob/main/Hex/Clients/SuperFastCaptureController.swift L57-L58, L325-L330 ; RecordingClient.swift L343-L415
- The orange dot is drawn by macOS when the mic is in use; apps cannot hide it (Sonoma 14.4+ can hide it only on external displays in full screen). https://macrumors.com/how-to/menu-bar-dot-explanation , https://vdmx.vidvox.net/tutorials/tag/Orange+Dot
- Bluetooth (AirPods): mic use switches the headset to the call profile; vendors report 0.5-2 s wake/switch and garbled or lost first words. https://docs.wisprflow.ai/articles/3566082841-fix-missing-first-words-in-transcriptions , https://www.getvoibe.com/help/airpods-bluetooth , https://spokenly.app/blog/mac-dictation-not-working . Jot's repo numbers: "0.3-2 s on a Bluetooth HFP route"; its design: record to disk from t=0, full engine rebuild on `AVAudioEngineConfigurationChange`, HUD "mic warming" state. architecture.md L84; latency-audit L131-L132. Handy recommends selecting the built-in mic while AirPods stay the output. Handy README.
- Route changes: an engine can stop routing after a route change; creating a new engine was the only reliable fix in one report (iOS 14 beta era). https://developer.apple.com/forums/thread/658078 . Hex and Jot both tear down and rebuild the engine and keep appending to the same file (Hex SuperFastCaptureController.swift L191-L194).
- Speech usually begins a few hundred ms after a key press, so a prepared engine (20-40 ms) is enough on built-in mics; Bluetooth needs either "default to built-in mic" or the warm-engine + pre-roll mode with the orange dot. (My inference.)

### B.3 Pasting

- Pattern used by FreeFlow and Jot: snapshot every `NSPasteboardItem` type (string, property list, data), write the transcript plus `org.nspasteboard.TransientType` / `ConcealedType` / `AutoGeneratedType` so clipboard managers skip it, post Cmd-V with `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `.maskCommand`, then restore. FreeFlow AppState.swift L65-L120, L3229-L3330. Marker convention: http://nspasteboard.org (referenced via https://github.com/nicke5012/TransientPasteboardType in FreeFlow comments).
- Restore timing: both FreeFlow (`clipboardRestoreDelay = 1.0`) and Jot (`restoreDelay = 1.0`, "slow apps read the pasteboard late; a too-early restore pastes the user's OLD clipboard") landed on 1.0 s, and both restore only if `changeCount` is unchanged (Jot also checks a session-UUID marker type). FreeFlow AppState.swift L241, L3341-L3358; https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/JotCore/Sources/InsertionEngine/PasteInserter.swift L23-L81. FreeFlow relaxed the strict changeCount check because browsers and Universal Clipboard bump it.
- Keycode: look up the 'v' keycode for the current layout (`UCKeyTranslate`) so Dvorak/AZERTY work. FreeFlow AppState.swift L3243-L3268; Jot uses Sauce.
- Posting events needs Accessibility (`kTCCServicePostEvent`); APIs `CGPreflightPostEventAccess` / `CGRequestPostEventAccess`. https://developer.apple.com/documentation/coregraphics/cgrequestposteventaccess() . Jot notes to check post-event access separately from `AXIsProcessTrusted` on macOS 26 (UNCONFIRMED). architecture.md L112.
- Secure Event Input: when any process enables it, the system stops passing keyboard events to event taps, system-wide; detect with `IsSecureEventInputEnabled`. https://developer.apple.com/library/archive/technotes/tn2150/_index.html . Field reports: with secure input stuck on (loginwindow after lock/unlock), keyDown hotkeys stop working but modifier-only hotkeys (Fn, Right Option, Control, Command) still work. https://github.com/zachlatta/freeflow/issues/329 , https://github.com/cjpais/Handy/issues/1828 . Handy's Carbon-hotkey fallback lost the PTT release. https://github.com/cjpais/Handy/issues/1999 . Terminal "Secure Keyboard Entry" blocks injected keystrokes (2004 report, old). https://lists.apple.com/archives/cocoa-dev/2004/Nov/msg00642.html . TN2150 does not say whether `CGEventPost` into a secure field is blocked (UNCONFIRMED). OpenWhispr docs: some secure fields reject pasted text; the text stays on the clipboard. https://docs.openwhispr.com/platform/dictating-into-other-apps
- AX insertion: `AXUIElementCreateSystemWide` -> `kAXFocusedUIElementAttribute` -> set `kAXSelectedTextAttribute`. Electron apps need `AXManualAccessibility = true` first, and can report success without inserting, so read back and verify; Jot forces paste for terminals and Google Docs. Jot architecture.md L107-L110, L210; Electron docs https://www.electronjs.org/docs/latest/tutorial/accessibility ; false-failure fix https://github.com/electron/electron/pull/38102
- Terminals: Cmd-V paste works in Terminal/iTerm2/Ghostty; pasted text arrives as a bracketed paste when the shell/TUI enables it, so a trailing newline does not execute. Ghostty has `clipboard-paste-protection` ("Require confirmation before pasting text that appears unsafe") and `clipboard-paste-bracketed-safe` (bracketed pastes are safe by default). https://ghostty.org/docs/config/reference . OpenWhispr says "Terminals use a different paste shortcut" and switches when it recognises one (UNCONFIRMED which shortcut). Jot planned a matrix incl. Cursor, VS Code, iTerm2, Terminal with Secure Keyboard Entry (architecture.md L199) but the results file is not in the repo.
- Focus guard: capture frontmost app at key-up; if focus changed before paste, do not paste blind. Jot architecture.md L107. FreeFlow waits for the shortcut release before pasting (`pasteAtCursorWhenShortcutReleased`, AppState.swift ~L2806) so held modifiers do not turn Cmd-V into Cmd-Fn-V.

### B.4 Low RAM

- The only measured number for a comparable app: Jot (SwiftUI menu bar app + GRDB + Sparkle, cloud STT, no local models) idles at ~90 MB. Jot's own release target was "RAM < 80MB". latency-audit-2026-08-19.md L14; architecture.md L193.
- No published measurement found that compares a minimal `MenuBarExtra` app with an `NSStatusItem` app (searched). One developer moved a menu from SwiftUI to NSStatusItem/NSMenu and reported "significantly less memory", no numbers (UNCONFIRMED). https://dev.to/heocoi/what-i-learned-building-a-native-macos-menu-bar-app-4im6
- What inflates it: dirty memory = heap, decoded images, framework data (Apple WWDC21 "Detect and diagnose memory issues"). https://developer.apple.com/videos/play/wwdc2021/10180 . WKWebView runs in separate WebContent processes whose memory is counted apart from the app; a bare WKWebView measured ~112 MB vs ~215 MB Electron (2020, macOS Catalina). https://developer.apple.com/forums/thread/21956 , https://git.2li.ch/keeweb/keeweb/wiki/Electron-alternatives . Local models: Superwhisper user saw ~900 MB with a local LLM resident. TypeWhisper local LLM leaks reached GBs (issue 800). Linked-but-unused CoreML/MLX frameworks: impact unknown (UNCONFIRMED).
- Practical plan (inference): AppKit `NSStatusItem` + `NSMenu`; one `NSPanel` for the indicator drawn with Core Animation; build Settings/History windows on demand and release them on close; SQLite via the C API or plain files instead of SwiftData; no WebKit; no Sparkle. Measure with `footprint <pid>` / Activity Monitor "Memory" after 10 min idle.
- Lifecycle risk: an `LSUIElement` app with no windows open is eligible for Automatic Termination; FreeFlow lost long dictations this way until it set `NSSupportsAutomaticTermination = NO`. https://github.com/zachlatta/freeflow/issues/178

### B.5 Audio encoding for upload

- FLAC encode is native: `AVAudioFile(forWriting:settings:[AVFormatIDKey: kAudioFormatFLAC, ...])` works on macOS 26; Jot measured CAF -> FLAC in 5 ms / 14 ms / 231 ms for 5 s / 30 s / 10 min. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/JotCore/Sources/TranscriptionClient/FLACEncoder.swift . `kAudioFormatFLAC` available macOS 10.13+. https://developer.apple.com/documentation/coreaudiotypes/kaudioformatflac
- Opus: `kAudioFormatOpus` exists since macOS 10.13 / iOS 11. https://ffmpeg.org/pipermail/ffmpeg-trac/2018-June/044789.html . An Apple engineer's accepted answer encodes PCM -> Opus with `AVAudioConverter` (48 kHz mono, 960 frames/packet), raw packets, no container, iOS-style sample. https://developer.apple.com/forums/thread/763362 . No native Ogg/WebM muxer; CAF-with-Opus -> Ogg needs your own repackager (example: https://paste.sr.ht/~singpolyma/5e8dc598ce9384e8cae2ce3ee598d08c2a63aade). Whether `AVAudioFile` writes Opus-in-CAF directly: UNCONFIRMED.
- Provider input: Azure MAI-transcribe accepts WAV, MP3, FLAC (under 300 MB); Opus not listed. https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe . xAI batch endpoint `https://api.x.ai/v1/stt`, multipart `file` + repeated `keyterm`, format detected from content (VoiceInk's client). https://github.com/Beingpax/LLMkit/blob/main/Sources/LLMkit/Transcription/XAIClient.swift . xAI's full format list: UNCONFIRMED (docs page not reachable; a mirror says 12 formats).
- Sizes for 20 s, 16 kHz mono (my calculation):
  - PCM 16-bit WAV: 32,000 B/s x 20 = 640,000 B (+44 B header) ≈ 625 KiB.
  - FLAC: speech typically ~50-65% of PCM -> ~320-420 KB (UNCONFIRMED ratio; measure).
  - Opus 24-32 kbps: 60-80 KB.
- Raw transfer time at 20 / 50 Mbps up (2.5 / 6.25 MB/s): WAV 0.26 / 0.10 s; FLAC ~0.15 / 0.06 s; Opus ~0.03 / 0.01 s.
- On a cold connection the transfer is RTT-bound, not bandwidth-bound: TCP slow start from ~14.6 KB initial window needs ~6 RTTs for 640 KB, ~5 for FLAC, ~3 for Opus. At 250 ms RTT (India -> US, UNCONFIRMED) that is ~1.5 s / ~1.25 s / ~0.75 s plus TLS setup. Mitigations: keep a warm HTTP/2 connection (Jot fires a HEAD on key-down - architecture.md L96), pick the nearest Azure region that offers MAI (TypeWhisper code has an `unsupportedMAIRegion` check, so not every region has MAI), and use FLAC.

### B.6 Distribution for personal use, TCC and signing

- Apple TN3127: TCC stores the app's designated requirement (DR) and checks each launch against it. "Unsigned code has no DR. Ad hoc signed code ... has a DR but it's tied to that specific version of the code. In both cases macOS can't reliably track the identity of the code." Signing with an Apple Development identity gives a default DR that stays stable across builds. https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements
- Result: every ad-hoc rebuild looks like a new app to Accessibility, Input Monitoring and Microphone; stale entries can block prompts until removed (`tccutil reset <service> <bundle-id>`). VoiceInk BUILDING.md: "Ad-hoc builds may require macOS permissions again after rebuilding." FreeFlow CONTRIBUTING: use "a consistent local code-signing identity and app path". https://github.com/Beingpax/VoiceInk/blob/main/BUILDING.md , https://github.com/zachlatta/freeflow/blob/main/CONTRIBUTING.md
- Fix: create a self-signed code-signing certificate in Keychain Access (Certificate Assistant, type "Code Signing") or use the free Apple Development certificate from Xcode with a personal team; sign every build with it; keep bundle ID and install path (/Applications) fixed. FreeFlow does exactly this with a "FreeFlow Dev" identity (Makefile L5, L88).
- Running a locally built app: no Gatekeeper quarantine for files you build yourself (quarantine is set by download tools) - UNCONFIRMED in this pass. Jot notes apps run from a mounted DMG are translocated and grants "will not stick". Jot README "Install".

### B.7 Launch at login and Keychain

- `SMAppService.mainApp.register()` (macOS 13+): the main app launches at later logins; already registered -> `kSMErrorAlreadyRegistered`. https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp , https://developer.apple.com/documentation/servicemanagement/smappservice/register() . Status can be `.requiresApproval` (user must allow in Login Items) or reported as `.notFound` after the user disables it. https://origin-devforums.apple.com/forums/thread/760186
- Keychain without libraries: `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` with `kSecClassGenericPassword`, `kSecAttrService`, `kSecAttrAccount`. TN3137: SecItem defaults to the file-based keychain (ACL-based, ACL tied to code identity -> "allow" prompts after a re-sign); the data protection keychain (`kSecUseDataProtectionKeychain = true`) needs keychain-access-group entitlements "authorized by a provisioning profile". https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains . With a self-signed cert you get the file-based keychain; with a stable cert the ACL prompt appears once (inference). FluidVoice tells users to click "Always allow". FluidVoice README L180. Jot's KeychainStore is ~100 lines with no deps. https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/main/JotCore/Sources/Support/KeychainStore.swift

---

## Ranked fork candidates

| # | Candidate | Why | Main work |
|---|---|---|---|
| 1 | Jot (Apache-2.0, Swift) | Architecture already matches: Fn hold/lock, prepared engine, CAF from t=0, FLAC, offline queue + Retry, AX->paste->chip with 1 s guarded restore, dictionary, history with audio, Keychain, no telemetry | Replace Gemini client with xAI + Azure MAI; add cost tracker, per-app prompts, correction learning; cut SwiftUI/GRDB weight to reach 50 MB; project looks dormant since 2026-08-27 |
| 2 | FreeFlow (MIT, Swift) | Small, no deps, active, Fn hold + Cmd-Fn toggle, proven clipboard code, history with audio, OpenAI-compatible cleanup | New STT clients; add prepare/pre-roll and offline queue; untangle 145 KB AppState |
| 3 | TypeWhisper (GPL-3.0, Swift) | Already has xAI + Microsoft MAI, PTT/toggle/hybrid, notch indicator, dictionary, auto-learn corrections, recovery, stats | Strip local engines (WhisperKit/MLX/onnx) and Premium gates; RAM unknown; large codebase |
| 4 | VoiceInk (GPL-3.0, Swift) | Has Grok Voice Transcribe 2.0 batch + streaming, modes per app/URL, notch recorder | No Azure; license gate; closed to PRs; stability complaints; heavy deps |
| 5 | Hex legacy Swift (MIT, archived) | Parts donor: Super Fast pre-roll ring buffer, hotkey processor with tests | No cloud STT; archived |

Not fit: Handy (local only, Tauri), OpenWhispr (Electron), Whispering (no system-wide dictation now), VoiceTypr (Tauri, AGPL, license), FluidVoice (local STT only), all closed apps.

---

## Unresolved questions

1. xAI STT: full list of accepted audio formats (FLAC? Opus?) and whether an OpenAI-compatible `/v1/audio/transcriptions` route exists - docs page was not reachable.
2. MAI-Transcribe-2 on Azure: exact model name, regions (India?), and whether it takes a phrase list / keyterms - only MAI-1/1.5 docs and the MAI-2 model card were found.
3. RTT from the owner's network to `api.x.ai` and to the nearest Azure MAI region - this decides whether WAV vs FLAC matters for the 1 s target.
4. Real idle footprint of a minimal AppKit `NSStatusItem` app vs `MenuBarExtra` on macOS 26/27 - no published measurement; needs a local test.
5. Does `AVAudioEngine.prepare()` without `start()` really avoid the orange dot on macOS 26/27, as Jot states?
6. Does a CGEvent Cmd-V reach a field while Secure Event Input is on (e.g. `sudo` prompt in Terminal)? TN2150 covers taps only.
7. macOS 27 privacy pane naming: one FreeFlow issue mentions "Device Control and Data Access"; not confirmed by Apple sources.
8. Whether VoiceInk's `LOCAL_BUILD` flag removes the trial/license gate.
