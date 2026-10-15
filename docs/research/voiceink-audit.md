# VoiceInk fork audit

Audit date: 2026-10-15 (IST).
Repo: https://github.com/Beingpax/VoiceInk, clone at commit `3a4b3e9` (2026-10-15 15:16 IST, "Merge pull request #1009").
Clone path: `scratchpad/src/VoiceInk`.
The cloud providers live in a separate package, `Beingpax/LLMkit` (MIT), pinned at `37100b2`. I cloned it read-only next to the app at `.../scratchpad/src/LLMkit`.

All paths below are relative to the VoiceInk clone unless they start with `LLMkit/`.
"Inferred" marks a statement that I did not read directly in code or in an issue.
I did not build or run anything.

---

## Verdict (short)

VoiceInk is a usable reference but a heavy fork base for a cloud-only, low-RAM, low-latency app.

- It has almost every feature on the list, and the GPL-3.0 licence permits a personal fork. The licence gate is a compile flag away (`LOCAL_BUILD`).
- It is a 72.5k-line app with 3 local-ASR stacks, a local-LLM XPC service, CloudKit sync, Sparkle, onboarding, dashboards and an "assistant" mode. Most of that is dead weight for the target.
- The hot path has known latency faults: no audio pre-roll, the panel shows before capture starts, a fixed 200 ms pre-paste sleep, a new URLSession (new TCP+TLS) per cloud request, and screen OCR on every recording.
- There are no unit tests in the repo, so a large removal has no safety net.

My recommendation: build a new minimal app, and copy specific parts from VoiceInk (GPL applies to copied code if you distribute). If you fork, plan a large deletion pass first (see "Top 5 changes").

---

## 1. Licence, paid licence check, offline behaviour

**Licence file.** `LICENSE` is 29 lines: the GPL v3 header and preamble, then the line "[For the complete license text, please visit: https://www.gnu.org/licenses/gpl-3.0.txt]" (`LICENSE:29`). README states GPL v3 (`README.md`, "License" section). GitHub's detector reports `NOASSERTION` because the file is truncated. The intent is GPL-3.0.
- `LLMkit` (the provider package) is MIT (`LLMkit/LICENSE:1`).

**What GPL-3.0 means for a personal fork.** You can fork, change and run it privately with no obligations. If you distribute binaries (also to friends), you must give the source of the whole derived work under GPL-3.0. Code that you copy into a new app makes that new app a derived work under the same rule. Private use has no obligation. (General GPL reading, not legal advice.)

**Paid licence check: yes, but soft.**
- Polar.sh licence API, org id hardcoded: `VoiceInk/Infrastructure/Licensing/PolarService.swift:14-15` (`https://api.polar.sh`, endpoints `/v1/customer-portal/license-keys/validate|activate|deactivate` at lines 58, 98, 137, 163).
- State machine: `VoiceInk/Features/Licensing/State/LicenseViewModel.swift`. 7-day trial (line 29). Licence key, activation id and trial start date are in Keychain (`VoiceInk/Infrastructure/Licensing/LicenseManager.swift:38-41`).
- **The only enforcement**: after the trial, every paste gets a prefix "Your trial has ended. Upgrade to VoiceInk Pro at tryvoiceink.com/buy" (`LicenseViewModel.swift:165-175`, applied in `VoiceInk/Features/Recording/Workflows/TranscriptionDelivery.swift:190-200`). Transcription still runs.
- Network calls to Polar happen only when the user enters, validates or deactivates a key (call sites: `LicenseManagementView.swift:57,186`, `LicenseView.swift:20,34`, `OnboardingFlowController.swift:246`). There is **no** periodic or per-transcription online check. If a key is stored, the state is `.licensed` offline (`LicenseViewModel.swift:466-470`). If Keychain is unavailable, the app fails open to `.licensed` (`LicenseViewModel.swift:449-458`).

**Issue #1010 (offline / Zscaler).** Opened 2026-10-15, open, no comments. The reporter suspects the Polar licence check. The code says otherwise:
- The reported model "Whisper Large v3 Turbo" is the **Groq cloud** model (`VoiceInk/Infrastructure/Providers/Transcription/Cloud/GroqProvider.swift:14-16`). The local whisper.cpp model has the display name "Large v3 Turbo" (`TranscriptionModelRegistry.swift:190`).
- The error text "A network error occurred: ..." comes from `CloudTranscriptionError.networkError` (`CloudTranscriptionService.swift:32-33, 84-85`).
- So the root cause is that Zscaler blocks `api.groq.com`, not Polar (inferred from code, not confirmed by the reporter). A licensed user stays licensed offline.

**How hard to remove the licence code in a personal build: trivial.**
- `make local` builds with `LocalBuild.xcconfig`, which adds the `LOCAL_BUILD` flag (`LocalBuild.xcconfig:14`). With that flag, `LicenseViewModel.init` sets `.licensed` and skips Keychain (`LicenseViewModel.swift:76-81`), `resolvedState` returns `.licensed` (`:462-464`), onboarding skips the licence screen (`OnboardingCoordinator.swift:97,147`, `OnboardingFlowController.swift:345`, `OnboardingView.swift:171`), and CloudKit is off (`VoiceInk/App/VoiceInk.swift:247-252`).
- Full deletion: about 2.4k lines in `VoiceInk/Features/Licensing/` (1,935) and `VoiceInk/Infrastructure/Licensing/` (475), plus about 10 call sites. About 1-2 hours.

---

## 2. Architecture and transcription abstraction

**Main modules** (Swift LOC per folder):

| Folder | LOC | Content |
|---|---:|---|
| `Features/ModelLibrary` | 8,269 | Model catalog, download managers (Whisper, FluidAudio, TranscribeCpp), provider UI |
| `Features/Dictionary` | 7,742 | Vocabulary, word replacement, Auto Learn (AX diff + LLM review) |
| `Infrastructure/Providers` | 7,104 | Transcription providers (cloud, whisper, FluidAudio, TranscribeCpp, Apple), enhancement (chat, Ollama, local CLI, VoiceInk Refine XPC) |
| `Features/Modes` | 6,057 | Per-app / per-URL "Modes" (formerly Power Mode) |
| `Features/Onboarding` | 5,266 | Onboarding flow |
| `Features/Recording` | 4,790 | `VoiceInkEngine` state machine, pipeline, delivery, streaming, recorder panels |
| `Features/Dashboard` | 4,501 | Stats dashboard |
| `Features/History` | 3,897 | History UI, audio player, retry |
| `App` | 3,250 | App entry, menu bar, updates, windows |
| `Features/Shortcuts` | 3,214 | Hotkeys (CGEventTap) |
| `Infrastructure/Audio` | 3,120 | CoreAudio AUHAL recorder, sounds, device manager |
| `Infrastructure/SystemIntegration` | 2,454 | Paste, context capture, browser URL, media control, launch at login |
| `Features/Enhancement` | 2,307 | AI enhancement service and prompts |
| `Features/Licensing` + `Infrastructure/Licensing` | 2,410 | Polar licence |
| `VoiceInkRefineXPC` | 498 | XPC service that runs a local MLX LLM |

**Transcription abstraction.** Three layers:
1. `protocol TranscriptionService { func transcribe(audioURL:model:context:) async throws -> String }` (`VoiceInk/Features/Recording/Workflows/TranscriptionService.swift:26-36`). File-based, one method.
2. `TranscriptionServiceRegistry.service(for:)` switches on `ModelProvider` (`TranscriptionServiceRegistry.swift:37-50`). All cloud providers go to `CloudTranscriptionService`.
3. `protocol CloudProvider` (`VoiceInk/Infrastructure/Providers/Transcription/Cloud/CloudProvider.swift:4-19`): `transcribe(audioData:fileName:apiKey:model:language:customVocabulary:timeout:)`, `makeStreamingProvider`, `verifyAPIKey`, plus `models`, `languageCodes`, `isStreamingOnly`. Registry list at `CloudProvider.swift:34-47`.
- Streaming: `protocol TranscriptionSession` with `FileTranscriptionSession` and `StreamingTranscriptionSession` (streaming with automatic batch fallback) (`TranscriptionSession.swift:6-15, 52-173`). Streaming providers implement `StreamingTranscriptionProvider` (`Infrastructure/Providers/Transcription/Contracts/StreamingTranscriptionProvider.swift`).
- The dictionary is passed as `customVocabulary: [String]`, read from SwiftData per request (`CloudTranscriptionService.swift:77, 110-127`). Limitation: `CloudProvider` gets only one `apiKey: String`. There is no slot for a region or endpoint.

**xAI / Grok provider (PR #951, merged 2026-09-19 14:29 IST, by the maintainer).** PR #951 changed 4 files: renamed the model id to `grok-voice-transcribe-2.0`, passed vocabulary to streaming, bumped LLMkit.
- App side: `VoiceInk/Infrastructure/Providers/Transcription/Cloud/XAIProvider.swift:5-51`. Model `grok-voice-transcribe-2.0`, `supportsStreaming: true` (lines 17-25). Batch calls `XAIClient.transcribe(... format: true, customVocabulary:)` (lines 29-42).
- **Batch** (`LLMkit/Sources/LLMkit/Transcription/XAIClient.swift:19-66`):
  - Endpoint `POST https://api.x.ai/v1/stt` (line 30), `Authorization: Bearer` (line 58).
  - `multipart/form-data`. The `model` field is omitted on purpose, so xAI picks its default STT model (line 34). Optional `language`, and `format=true` only when a language is set (lines 36-41).
  - **Keyterms**: one `keyterm` field per term, terms over 50 chars dropped, max 100 terms (lines 43-49).
  - Audio: the recorded file as-is, sent as `audio/wav` (line 52). The recorder writes 16 kHz mono 16-bit PCM WAV (`CoreAudioRecorder.swift:70, 488-490, 664-668`). About 32 KB/s, so a 15 s clip is about 480 KB. No compression (no FLAC/Opus).
  - Response: JSON `{text}` (lines 64-65, 101-103).
- **Streaming** (default for xAI, see section 8) (`LLMkit/Sources/LLMkit/Streaming/XAIStreamingClient.swift`):
  - `wss://api.x.ai/v1/stt` with query `sample_rate=16000&encoding=pcm&interim_results=true&endpointing=100&smart_turn=0.5`, plus `language` and `keyterm`s (lines 42-66).
  - Waits for `transcript.created` before it returns (lines 85-103). Sends raw PCM16 in 100 ms frames of 3,200 bytes (lines 10, 110-121). Ends with `{"type":"audio.done"}` (lines 123-144).
- **Connection reuse: none.**
  - Batch: `performUpload` builds a **new `URLSessionConfiguration.ephemeral` session for every attempt** and invalidates it after (`LLMkit/Sources/LLMkit/HTTPClient.swift:78-79, 106-113`). Each request pays DNS + TCP + TLS again. HTTP/2 multiplexing and keep-alive across dictations cannot happen.
  - Streaming: a new `URLSession(configuration: .default)` per connect (`XAIStreamingClient.swift:75`).
  - Retries: up to 2 retries on network errors or HTTP 429/5xx, with 1 s and 2 s backoff (`HTTPClient.swift:62-104`). The default cloud timeout is 30 s (`VoiceInk/App/Configuration/AppDefaults.swift:15-22`). Worst case before failure is about 93 s (inferred: 3 x 30 s + 3 s).

---

## 3. Effort to add MAI-Transcribe-2 (Azure Speech, custom REST, phrase list)

Assumption (inferred, verify against Microsoft docs): a single multipart POST to a regional Azure Speech endpoint, with an `Ocp-Apim-Subscription-Key` header, an audio part and a JSON `definition` part that carries locale and phrase list. I did not verify the exact MAI-Transcribe-2 request schema.

Files to change:

| File | Change | Lines (est.) |
|---|---|---:|
| new `VoiceInk/Infrastructure/Providers/Transcription/Cloud/AzureMAIProvider.swift` | `CloudProvider` conformer: build multipart (LLMkit's `MultipartFormData` is `internal`, so write a small copy or make it public in an LLMkit fork), map `customVocabulary` to the phrase list, decode the response, `verifyAPIKey` | 150-200 |
| `VoiceInk/Features/ModelLibrary/Models/TranscriptionModel.swift:4-20` | add `case azureMAI` to `ModelProvider` | 1-3 |
| `VoiceInk/Infrastructure/Providers/Transcription/Cloud/CloudProvider.swift:35-47` | register the provider | 1 |
| `VoiceInk/Features/ModelLibrary/Views/ProviderCloudManagementView.swift:46, 135, 170` | add to the provider list, icon, console URL | 5-10 |
| Region/endpoint setting | `CloudProvider` passes only `apiKey` (`CloudProvider.swift:13-16`). Add an endpoint field in `UserDefaults` plus a small text field in the provider UI, or widen the protocol | 40-80 |
| `Assets.xcassets/provider-*.imageset`, `OnboardingCoordinator.swift:269` (optional) | icon and onboarding list | small |

Total: about 250-350 lines, **4-8 hours** including manual tests (inferred). Batch only. A streaming variant would add 250-350 lines (compare `XAIStreamingClient.swift`, 233 lines).
In a new minimal app the same provider is about 150 lines, because there is no registry, model catalog or onboarding to update (inferred).

---

## 4. Local models: linking, load time, compile-out

**All Swift Package dependencies** (`VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, 28 pins):

| Package | Pin | Direct product used by |
|---|---|---|
| Sparkle | 2.9.2 | VoiceInk (updates) |
| mediaremote-adapter (Beingpax) | branch `master` @cf30c4f | VoiceInk (pause media) |
| Zip | 2.1.2 | VoiceInk (whisper CoreML encoder zips) |
| swift-atomics | 1.3.0 | VoiceInk |
| Transcribe-cpp-swift (Beingpax) | 0.2.0-dev.856d7c1 | VoiceInk (local ASR) |
| SelectedTextKit (Beingpax) | branch `performance/off-main-menu-action` | VoiceInk (selected-text context) |
| swift-markdown-ui | 2.4.1 | VoiceInk |
| FluidAudio | branch `main` @762baf6 | VoiceInk (Parakeet, CoreML) |
| LLMkit (Beingpax) | revision 37100b2 | VoiceInk (all cloud STT + LLM clients) |
| mlx-swift-lm, mlx-swift, swift-huggingface, swift-transformers | rev cd1ab3d / 0.31.6 / 0.9.0 / 1.3.0 | VoiceInkRefineXPC only |
| Transitive | AXSwift 0.3.7, EventSource 1.4.1, KeySender 0.0.5, NetworkImage 6.0.1, swift-argument-parser, swift-asn1, swift-cmark, swift-collections, swift-crypto, swift-jinja, swift-nio, swift-numerics, swift-syntax, swift-system, yyjson, (+ atomics) | via the packages above |

Target mapping: main app products at `project.pbxproj:262-272`. XPC products (MLX) at `project.pbxproj:339-345`. Two products pin to moving branches (FluidAudio `main`, SelectedTextKit feature branch), so builds are not reproducible.

**whisper.cpp** is a prebuilt `whisper.xcframework`, linked and embedded in the main app (`project.pbxproj:20-21, 88`). The path is `$(HOME)/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`. `make whisper` clones whisper.cpp HEAD and runs its build script (`Makefile`, `whisper` target). `LibWhisper.swift:4-8` contains `#error` if the module is missing, so whisper is a hard build dependency.

**Load time.**
- Frameworks: whisper.xcframework, FluidAudio, TranscribeCpp and LLMkit link into the main binary, so dyld loads them at launch (inferred: standard dynamic/static linking; code pages map but stay mostly clean).
- Models: loaded **only when selected**. Whisper context loads on first recording (`VoiceInkEngine.swift:373-386`). The prewarm service runs 3 s after launch and on wake, but only for `.whisper` and `.fluidAudio` (`App/Lifecycle/ModelPrewarmService.swift:41-47, 106-130`). Cloud models are skipped (line 127).
- MLX runs in a separate XPC process (`VoiceInkRefineXPC`), started only when "VoiceInk Refine" enhancement is used.
- `TranscriptionServiceRegistry` creates local services lazily (`TranscriptionServiceRegistry.swift:13-29`). But `App/VoiceInk.swift:124-125` creates `WhisperModelManager` and `FluidAudioModelManager` at launch. The whisper manager scans the models directory (`WhisperModelManager.swift:117-136`).

**Can they compile out cleanly? No, not cleanly.** There are no `#if` feature flags for local models. About 40 files reference `FluidAudio`, `WhisperModelManager` or `TranscribeCpp`. `VoiceInkEngine.init` takes `WhisperModelManager` (`VoiceInkEngine.swift:127-131`), and `TranscriptionServiceRegistry` takes a `WhisperModelProvider` (`:31`). Local-model code is about 6.8k lines (Whisper 1,325, FluidAudio 1,849, TranscribeCpp 1,244, AppleSpeech 466, VoiceInkRefine 1,945), plus much of `Features/ModelLibrary` (8,269). Removal estimate: 1-2 days of careful work, without a test suite (inferred).

---

## 5. Audio capture path and issue #996

**API: CoreAudio AUHAL** (`kAudioUnitSubType_HALOutput`), not AVAudioEngine and not AVAudioRecorder (`VoiceInk/Infrastructure/Audio/CoreAudioRecorder.swift:390-410`).
- The render callback converts to 16 kHz mono Int16 and writes with `ExtAudioFileWrite` during recording (`:1049-1126`). The same callback feeds streaming chunks through `onAudioChunk` (`:1126`).
- **Prepared at idle**: `Recorder.init` calls `schedulePrepareForCurrentDevice`. That creates and initializes the AUHAL (`AudioUnitInitialize`) but does not start it (`Recorder.swift:38-49, 153-177`; `CoreAudioRecorder.swift:138-171`). The mic is not running at idle. Added 2026-06-06 in commit `e5524fc` "Prewarm recorder with safer AUHAL prep".
- The prepared unit is **discarded** on audio device change, system sleep and system wake (`Recorder.swift:40-46, 179-184`). It is also discarded after a recording shorter than 150 ms (`CoreAudioRecorder.swift:235-245`), and when the device sample rate changed (`:725-750`, from PR #955, merged 2026-10-13). After a discard, the next key-down rebuilds the AUHAL in the start path.
- **Pre-roll: none.** The engine starts at key-down. No ring buffer runs before key-down.
  - `RealtimeAudioChunkGate` (`VoiceInkEngine.swift:8-82`) only buffers chunks between capture start and WebSocket connect. It is not a pre-roll.

**Order of operations at key-down** (push-to-talk, panel hidden):
1. CGEventTap callback on the main run loop, then `handleShortcutDown`, then `toggleRecorderPanel` (`RecordingShortcutManager.swift:420-424`).
2. `SoundManager.shared.playStartSound()`, then `isRecorderPanelVisible = true`. The `didSet` **creates and shows the NSPanel synchronously on the main actor**, and only after that does `engine.toggleRecord` run (`RecorderUIManager.swift:244-247, 49-58, 87-141`).
3. `toggleRecord`: `passesRecordingPreflight` (await), then `ActiveWindowService.beginApplyingConfiguration` starts (mode detection, may query the browser URL), then `recorder.startRecording` (`VoiceInkEngine.swift:235-260`).
4. `Recorder.startRecording` resolves the device, starts media pause and a mute task (mute fires after 220 ms, `Recorder.swift:18, 135-143`), then hops to `audioSetupQueue` and calls `CoreAudioRecorder.startRecording` (`Recorder+RecordingDeviceSetup.swift:18-33`). That function calls `prepare` again (it rebuilds if not prepared), creates the WAV file, then `AudioOutputUnitStart` (`CoreAudioRecorder.swift:184-206`).

**Root cause of #996** (opened 2026-10-09, **open, no comments, not fixed**; reporter on 2.21 with a Bose QC45 Bluetooth headset, about 0.5 s every time and seconds after idle):
- (a) **Capture starts only after the UI work.** The start sound plays and the panel shows first. Audio start waits for panel creation and the preflight awaits on the main actor (`RecorderUIManager.swift:245-247`). Issue #572 (2026-03-07, still open) measured about 255 ms to show the panel and about 940 ms to the first captured audio on an older build without AUHAL prewarm.
- (b) **No pre-roll.** Any device start latency becomes lost speech. `AudioOutputUnitStart` returns before the hardware delivers frames. On Bluetooth, opening the mic forces an A2DP-to-HFP profile switch, which typically takes hundreds of ms (inferred, a known macOS Bluetooth behaviour; the reporter also suspects it).
- (c) **"Longer after idle"**: sleep/wake discards the prepared AUHAL (`Recorder.swift:40-46`) and destroys idle recorder panels (`RecorderUIManager.swift:178-199, 305-321`). The first dictation after the Mac sleeps must rebuild both the AUHAL and the panel window on the key-down path (inferred from code, matches the report).
- (d) The start sound plays on the output device at the same moment as the input switch. On a Bluetooth headset this can extend the profile switch (inferred).
- Status: the code has no pre-roll and no "indicator only when live" gate. `recordingState = .recording` is set after `startRecording` returns (`VoiceInkEngine.swift:279`), but the panel and sound come earlier. The issue stays open. A user in #572 reports that the third-party tool `macos-mic-keepwarm` fixes the delay, which supports (b).

---

## 6. Hotkeys

- **Library: none.** A custom `CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap)` on the **main run loop** (`VoiceInk/Features/Shortcuts/Coordination/ShortcutMonitor.swift:99-145`). Mask: keyDown, keyUp, flagsChanged, other-mouse down/drag/up (`:500-509`). The tap is active and can swallow events (`:115-116`). It re-enables itself after `tapDisabledByTimeout` (`:107-113`). No KeyboardShortcuts, no Carbon `RegisterEventHotKey`, no NSEvent monitors.
- **Fn and modifier-only**: supported. `kVK_Function` is in the modifier key set, with the display name "Fn" (`VoiceInk/Features/Shortcuts/Models/Shortcut.swift:187, 235-236`). Modifier-only shortcuts such as Right Cmd (`Shortcut.swift:60-75`). Mouse buttons too.
- **Modes**: `toggle`, `pushToTalk`, `hybrid` (a hold of 0.5 s or more acts as push-to-talk, a tap acts as toggle) and `doubleTap` (0.7 s window) (`RecordingShortcutManager.swift:46-58, 319-321, 406-475`). Cooldown between presses: 0.5 s (`:319, 391-395`). Primary and secondary shortcuts, plus per-mode shortcuts (`ModeShortcutManager.swift`).
- Risk: the tap runs on the main thread. Main-thread stalls (SwiftUI, SwiftData saves) delay key-up handling and can trigger `tapDisabledByTimeout` (inferred).

---

## 7. Paste implementation and every hardcoded delay

**Paste** (`VoiceInk/Infrastructure/SystemIntegration/Paste/CursorPaster.swift`):
1. Snapshot every pasteboard item and every type as `Data` (`:71, 121-130`).
2. `ClipboardManager.setClipboard`: clear, set the string, add the `org.nspasteboard.TransientType`/`AutoGeneratedType` markers and a session-id type, then read back to verify (`ClipboardManager.swift:15-36`).
3. **Sleep 200 ms** (`prePasteDelay`, `CursorPaster.swift:25, 84`).
4. Post Cmd down, V down, V up, Cmd up through `CGEvent(... ).post(tap: .cghidEventTap)` with a private event source, with **10 ms between each event** (3 x 10 ms) (`:26, 238-262`). An AppleScript "System Events keystroke v" option also exists (`:134-135, 201-226`).
5. Restore the clipboard after `clipboardRestoreDelay`, clamped to 0.25-5.0 s, **default 2.0 s** (`:27, 148-168`; default at `AppDefaults.swift:133-134`). The restore runs only if the pasteboard still holds this session's text.
- **No AX insertion** (`kAXSelectedTextAttribute`) for paste. AX is used only by Auto Learn to read back the text after paste.
- **Serialisation hazard**: each paste waits for the previous paste's clipboard-restore task (`pasteQueueTask`, `CursorPaster.swift:45-54`). Two dictations within 2 s: the second paste waits up to the remaining restore delay of the first (default 2 s).

**All hardcoded delays in the record -> transcribe -> paste path:**

| Where | Value | On hot path? |
|---|---|---|
| `RecordingShortcutManager.swift:319` press cooldown | 0.5 s | blocks a re-press only |
| `RecordingShortcutManager.swift:320-321` hybrid / double-tap thresholds | 0.5 s / 0.7 s | mode logic |
| `Recorder.swift:18, 139` mute system audio after start | 220 ms | async, not blocking |
| `PlaybackController.swift:98, 145` media pause/resume polling | 50 ms / 25 ms | only if pause-media is on (default off) |
| `MediaController.swift:48`, `PlaybackController.swift:154` audio resumption | user `audioResumptionDelay`, default 0 | after stop, async |
| `CoreAudioRecorder.swift:1026-1030` wait for render callbacks | 1 ms poll loop | stop path, short |
| `VoiceInkEngine.swift:814` VoiceInk Refine (local LLM) warm debounce | 450 ms | only with the local Refine provider |
| `BrowserURLService.swift:171` browser URL read | 50 ms | during start, in parallel |
| `ScreenCaptureService.swift:243` OCR timeout helper | `captureTimeout` | during recording, parallel |
| `StreamingTranscriptionService.swift:443, 477` final transcript wait | 10 s timeout | streaming stop (upper bound) |
| `LLMkit/HTTPClient.swift:27, 74-76` retry backoff | 1 s, 2 s | cloud failure only |
| `AIEnhancementService.swift:35, 99-107` client rate limit between LLM calls | 1.0 s minimum gap | enhancement on |
| `AIEnhancementService.swift:~322-379` LLM retry backoff | 1 s, doubling; 3 attempts; 7 s timeout (`EnhancementRequestSettings.swift:4-8`) | enhancement failure |
| `CursorPaster.swift:25, 84` pre-paste | **200 ms** | **yes, always** |
| `CursorPaster.swift:26, 255-259` between key events | **3 x 10 ms** | **yes, always** |
| `CursorPaster.swift:27, 148-156` clipboard restore | 2.0 s default (0.25-5 s) | after paste; blocks the next paste |
| `TranscriptionDelivery.swift:142, 181` before "send" key (Enter) | 150 ms | only with auto-send |
| `RecorderUIManager.swift:181` panel invalidation debounce | 400 ms | after wake / display change |

---

## 8. Release -> paste latency budget (from code)

There are two paths. **For xAI the default is streaming**: `ModeConfig.isRealtimeTranscriptionEnabled = true` (`ModeConfig.swift:53`), and `TranscriptionRealtimeSupport.isEnabled` returns true for any model with `supportsStreaming` (`TranscriptionRealtimeSupport.swift:16-21`). xAI sets `supportsStreaming: true` (`XAIProvider.swift:23`). For batch with keyterms, the user must turn off realtime in the mode.

Sequential steps after key-up (batch path; the streaming path differs at step 5):
1. CGEventTap on the main run loop, then `Task`, then `handleShortcutUp`, then `toggleRecorderPanel`, then `toggleRecord` (`RecordingShortcutManager.swift:447-451`, `RecorderUIManager.swift:226-228`).
2. `await recorder.stopRecording()`: hop to `audioSetupQueue`. There: `AudioOutputUnitStop`, a 1 ms poll for in-flight callbacks, `AudioUnitReset`, a sync drain of the processing queue, a frame-count check, `ExtAudioFileDispose` (WAV header finalised) (`Recorder.swift:105-133`, `CoreAudioRecorder.swift:209-248`). Tens of ms at most (inferred). No format conversion after stop, because conversion happens live.
3. SwiftData `insert` + `save()` of a pending `Transcription` on the main actor, and a notification post (`VoiceInkEngine.swift:194-202`).
4. `pipeline.run`, then `session.transcribe` or `serviceRegistry.transcribe` (`TranscriptionPipeline.swift:105-113`).
5. Batch: `Data(contentsOf:)` reads the whole WAV (about 480 KB for 15 s) (`CloudTranscriptionService.swift:91-96`). A SwiftData fetch of vocabulary (`:110-127`). A Keychain read of the API key (`:98-103`). The multipart body is built in memory. **A new ephemeral URLSession, so DNS + TCP + TLS handshake each time** (`HTTPClient.swift:78, 106-113`). Upload, server processing, JSON decode.
   - Streaming: drain buffered chunks, send the last frame and `audio.done`, wait for `transcript.done` (10 s cap) (`StreamingTranscriptionService.swift:201-240, 431-480`; `XAIStreamingClient.swift:123-144`). On any error: full batch upload (`TranscriptionSession.swift:145-172`).
6. `TranscriptionOutputFilter.filter`, trim, trigger-word mode switch, `ParagraphFormatter.format` (NLTokenizer; on by default, `AppDefaults.swift:147`), `WordReplacementService.applyReplacements` (SwiftData fetch + regex) (`TranscriptionPipeline.swift:114-142`).
7. `await AudioFileMetadata.duration` (an `AVURLAsset` load) **before** enhancement and paste (`TranscriptionPipeline.swift:145`; `VoiceInkEngine.swift:904-910`).
8. Optional enhancement: state change, context snapshot, `enhance()` with a 1 s minimum gap between calls, 7 s timeout and retries (`TranscriptionPipeline.swift:172-223`).
9. Delivery: set state idle, play the stop sound, dismiss the panel, then `CursorPaster` (queue wait, clipboard snapshot, set, **200 ms**, **3 x 10 ms** key events) (`TranscriptionDelivery.swift:165-173`).
10. After paste: SwiftData save, session metric, `cleanupResources` (`TranscriptionPipeline.swift:246-296`; `VoiceInkEngine.swift:639-653, 871-879`). Auto Learn `pasteDidFinish` is awaited inside the paste session but after Cmd-V (`CursorPaster.swift:93-102`).

Fixed floor in the app: about 230 ms of sleeps plus one TLS handshake. For a 1 s target with a 10-20 s clip on batch, the network round trip and the server time must fit in about 600-700 ms (inferred). The handshake per request and the 200 ms pre-paste sleep are the first things to remove. Streaming moves upload time into the recording, but it adds a WebSocket handshake per recording and a final-transcript wait.

Other work on every recording that is not needed: **selected-text capture (AX, then menu-action copy, then AppleScript) and screen capture + Vision `.accurate` OCR start unconditionally at recording start.** OCR needs Screen Recording permission. These run even when enhancement is off (`VoiceInkEngine.swift:297, 520-526`; `RecordingContextSnapshot.swift:36-55`; `SelectedTextService.swift:10-14`; `ScreenCaptureService.swift:125, 211-212`). The mode flags `useScreenCapture` / `useSelectedTextContext` only gate whether the text is *used* (`ModeRuntimeConfiguration.swift:177-178`, `AIEnhancementService.swift:115-143`). The "menuAction" strategy may simulate a Copy in the focused app (inferred from the SelectedTextKit strategy name; not read in the package).

---

## 9. Feature state against the owner's list

| Owner requirement | State in VoiceInk | Evidence |
|---|---|---|
| Idle RAM < 50 MB, no local models | **Not met by design** (inferred). Links whisper, FluidAudio, TranscribeCpp, MLX deps (XPC), SwiftUI + 3 SwiftData stores, CloudKit in release | sections 4, 12 |
| ~1 s release -> paste | **At risk**: no connection reuse, 200 ms sleep, OCR per recording | sections 7, 8 |
| xAI Grok batch + keyterms | **Present** (batch and streaming) | `XAIProvider.swift`, `LLMkit/.../XAIClient.swift:43-49` |
| MAI-Transcribe-2 (Azure, phrase list) | **Missing**; 4-8 h | section 3 |
| Keys in Keychain | **Present**. Release builds use the data-protection keychain with `kSecAttrSynchronizable = true` (iCloud Keychain sync) by default | `KeychainService.swift:223-226`; `APIKeyManager.swift:35-50` |
| No telemetry / accounts | **No analytics SDK**. Polar licence, Sparkle, announcements, GitHub star check exist | section 11 |
| Push-to-talk + toggle, Fn / modifier-only | **Present** | section 6 |
| Paste with clipboard restore | **Present** (Cmd-V CGEvent, restore after 2 s) | section 7 |
| Zero clipping at start | **Missing**: no pre-roll; #996 and #572 open | section 5 |
| Floating / notch indicator with mic level | **Present**: `notch` and `mini` panels, `AudioVisualizerView` from `audioMeterSnapshot` | `RecorderUIManager.swift:7-26`; `Recorder.swift:186-228` |
| Dictionary as keyterms + find/replace | **Present**: `VocabularyWord` sent as `customVocabulary`; `WordReplacement` rules with regex | `CloudTranscriptionService.swift:110-127`; `WordReplacementService.swift` |
| Optional LLM cleanup with per-app prompts | **Present**: many providers (OpenAI, Anthropic, Gemini, Groq, Cerebras, OpenRouter, Mistral, Ollama, local CLI, custom, local MLX) | `Features/Enhancement`, `ModeConfig.swift:50-60` |
| Per-app modes | **Present**: "Modes" (formerly Power Mode) with app bundle ids, URLs, trigger words, per-mode model / prompt / language / realtime / output | `ModeConfig.swift:43-64, 207-224` |
| History with audio retention | **Present**: SwiftData `Transcription` with `audioFileURL`; WAVs in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings`; auto-delete off by default (7 days when on) | `Transcription.swift:11-32`; `VoiceInkEngine.swift:146-148`; `AudioCleanupManager.swift`; `AppDefaults.swift:158-161` |
| Learn from corrections | **Present but buggy**: Auto Learn reads the field back through AX, diffs it, and asks an LLM to propose replacements. It is **on by default**. #985 (open since 2026-09-29): manual review loses the correction; "Immediately" learns nothing | `Features/Dictionary/AutoLearn/*` (about 2.5k LOC); `AppDefaults.swift:154` |
| Menu bar only | **Present**: `IsMenuBarOnly` (default false) | `MenuBarManager.swift:7-18, 57` |
| Launch at login | **Present**: `SMAppService.mainApp` | `LaunchAtLoginManager.swift:94-100` |
| Sound cues | **Present**: start/stop/esc, custom sounds | `SoundManager.swift:36-49`; `CustomSoundManager.swift` |
| Keep audio on network failure + retry | **Partial**: the WAV is kept and the failed row is saved; LLMkit retries 2 times; streaming falls back to batch; "Retry last transcription" is manual. No automatic offline queue and no reachability monitor (grep for `NWPathMonitor` finds nothing) | `TranscriptionPipeline.swift:227-244`; `LastTranscriptionService.swift:101-113` |
| Usage / cost tracker | **Partial**: `SessionMetric` stores words, audio duration, model, speed, estimated enhancement tokens, and a dashboard shows them. **No money cost** | `SessionMetric.swift:4-19`; `EstimatedTokenCounter.swift` |
| History storage tech | **SwiftData** (6 `@Model` uses, 3 stores: transcripts, dictionary (CloudKit private DB in release), stats). No Core Data | `VoiceInk.swift:227-260` |

---

## 10. Code quality and activity

- **Swift LOC: 72,523** in 375 files (`find . -name '*.swift' | xargs wc -l | tail -1`). LLMkit adds 5,439 lines.
- **Largest files**: `Infrastructure/Audio/CoreAudioRecorder.swift` 1,368; `Features/Dashboard/Views/DashboardContent.swift` 1,035; `Infrastructure/Providers/Enhancement/VoiceInkRefine/VoiceInkRefineModelDownloader.swift` 950; `Features/ModelLibrary/Views/CustomProviderManagementView.swift` 921; `Features/Recording/Workflows/VoiceInkEngine.swift` 911; `Features/Licensing/Views/LicenseManagementView.swift` 872; `Features/Enhancement/State/AIService.swift` 864; `Infrastructure/Persistence/Statistics/DashboardStatsLoader.swift` 727; `Features/Dictionary/AutoLearn/AutoLearnService.swift` 716; `Features/History/Components/AudioPlayerView.swift` 702.
- **Tests: effectively none.** 2 files, 76 lines, both Xcode UI-test templates (`Tests/VoiceInkUITests/*.swift`). The `VoiceInkTests` unit-test target points to a group that is not in the repo (`project.pbxproj:278-298`). LLMkit has 1 test file (`OllamaClientTests.swift`).
- **Singletons**: 46 `static let/var shared`. Examples: `LicenseViewModel.shared`, `AutoLearnService.shared`, `WordReplacementService.shared`, `APIKeyManager.shared`, `ActiveWindowService.shared`, `ModeManager.shared`, `SoundManager.shared`, `NotificationManager.shared`.
- **UI mix**: 169 files import SwiftUI, 70 import AppKit. NSPanel-based recorder windows host SwiftUI. 222 `@MainActor` annotations.
- **Smells**:
  - 242 direct `UserDefaults.standard` uses with string keys. 70 `NotificationCenter` posts used as an event bus. 151 `try?`.
  - `VoiceInkEngine.toggleRecord` is a 260-line method with nested tasks (`VoiceInkEngine.swift:178-438`).
  - `requestRecordPermission` is a stub that always returns true (`:440-442`).
  - Branch-pinned dependencies (FluidAudio `main`, SelectedTextKit feature branch).
  - The licence and trial code is mixed into delivery.
  - The app auto-runs the user's `gh` CLI (section 11).
  - Screen OCR on every recording (section 8).
  - CONTRIBUTING says no PRs are accepted (`README.md`, Contributing section), but a few external PRs were merged (#955, #1005).
- **Commit activity, last 90 days** (`git log --since=2026-07-17`; shallow clone of 200 commits reaches back to 2026-04-10, so the window is covered): 267 commits (211 non-merge). 257 by Prakash Joshi Pax. 10 other authors with 1-2 commits each. Very active, single maintainer.
- **Contributors**: 45 (GitHub API, including anonymous).
- **Open issues: 118. Open PRs: 27.** Stars 6,816, forks 955.
- **Latest release**: `v2.21` (Latest), 2026-09-28 20:00 IST. Pre-release `v2.22` "Diagnostic Release", 2026-10-01 14:46 IST.

---

## 11. Telemetry, analytics, outbound hosts

- **No analytics or crash SDK.** Grep for analytics, telemetry, Sentry, PostHog, Mixpanel, TelemetryDeck, Amplitude, Firebase, Crashlytics, Segment, Plausible and Aptabase finds no SDK or call (the only hits are the word "amplitude" in `AudioVisualizerView.swift` and "plausible" in an LLM prompt).
- **App-initiated outbound calls that are not user content:**
  - Polar licence: `https://api.polar.sh` (`PolarService.swift:15`). Only on licence actions.
  - Sparkle appcast: `https://beingpax.github.io/VoiceInk/appcast.xml` (`Info.plist:7-8`). `SUEnableAutomaticChecks` is false (`Info.plist:13-14`) and the updater starts with `startingUpdater: false` (`UpdaterViewModel.swift:22-23, 43`). `checkForUpdatesIfDue` runs when the dashboard appears, if the user setting allows it (`UpdaterViewModel.swift:64-76`).
  - Announcements: `https://beingpax.github.io/VoiceInk/announcements.json`, fetched 5 s after launch when `enableAnnouncements` is true (default true) (`AnnouncementsService.swift:13, 30, 43`; `AppDefaults.swift:130`).
  - **GitHub star check through the user's own `gh` CLI**: after a usage threshold, 3 s after the main window shows, the app runs `gh api --include user/starred/<repo>`, and `gh api -X PUT` on click (`GitHubStarPromptCoordinator.swift:37, 55-87, 108`; `GitHubCLIStarService.swift:13-33`). It uses your GitHub token without a prompt for the check.
  - Model downloads: `https://huggingface.co` (whisper, TranscribeCpp, Refine) (`WhisperModelManager.swift:17, 28`; `TranscribeCppModelCatalog.swift:18`; `VoiceInkRefineModelDownloader.swift:479`).
  - CloudKit: private DB `iCloud.com.prakashjoshipax.VoiceInk` for the dictionary in release builds (`VoiceInk.swift:249-251`). iCloud Keychain sync for API keys (`KeychainService.swift:226`).
- **Provider hosts** (only when that provider is used): `api.x.ai` / `wss://api.x.ai`, `api.groq.com`, `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com` (https + wss), `api.mistral.ai` (https + wss), `api.deepgram.com` (https + wss), `api.elevenlabs.io` (https + wss), `api.assemblyai.com`, `wss://streaming.assemblyai.com`, `api.soniox.com`, `wss://stt-rt.soniox.com`, `asr.api.speechmatics.com`, `wss://eu2.rt.speechmatics.com`, `api.cartesia.ai` (https + wss), `openrouter.ai`, `api.cerebras.ai`, `http://localhost` (Ollama, local CLI).
- Link-only hosts (opened in a browser, no app traffic): `tryvoiceink.com`, `polar.sh`, console URLs of each provider, `github.com`, `discord.gg`, `youtube.com`, `i.ytimg.com`, `cookbook.openai.com`, `www.google.com` (custom-command template).

---

## 12. Idle RAM: what issues say

- **No issue or discussion gives a number for VoiceInk's own idle footprint.** I searched issues for memory, RAM, MB, "memory leak", "memory usage", footprint, "Activity Monitor", idle and GB. A discussions search for "memory" returned 0.
- Related reports:
  - #574 (closed): the MediaRemoteAdapter Perl helper leaked about 942 MB over 48 h. Fixed. The helper runs only when "pause media" is on (`PlaybackController.swift:36-62`; default off).
  - #760 (open): a stuck Sparkle updater made `launchservicesd` grow to 2.38 GB over 10 days (VoiceInk 1.79). The maintainer doubts the cause.
  - #138 (closed): `com.apple.cmio.registerassistantservice` used about 1 GB after Apple native transcription was tried.
  - #266 (closed), #634 (closed), #642 (closed), #672 (open, 2026-04-27): high idle CPU / battery drain. #672 is open with no root cause.
  - #389, #467 (closed): observer and listener leaks, fixed.
  - #1003 (open): Parakeet Unified reloads its model each session, about 50 s first dictation after idle (local model only).
- Inference: with whisper.xcframework, FluidAudio (CoreML), TranscribeCpp, Sparkle, SwiftUI windows, 3 SwiftData stores and CloudKit in one process, idle RSS will likely be well above 50 MB even with a cloud model selected. This is unmeasured. Measure a `make local` build with `footprint`/`vmmap` before you decide.

---

## Top 5 changes a fork would need

1. **Cut the app down to a cloud-only core.** Remove whisper.xcframework, FluidAudio, TranscribeCpp, Apple Speech, VoiceInkRefineXPC (MLX), Ollama/local CLI, model library UI, onboarding, dashboard, assistant mode, licensing, Sparkle, announcements, GitHub-star prompt and CloudKit. That is about 30-40k lines. This is the only route to the RAM target, and it has no test net.
2. **Fix capture start (zero clipping).** Keep a warm input with a short ring-buffer pre-roll (for example 300-500 ms), or at least start the AUHAL before the panel and sound. Do not discard the prepared unit on wake without a fast rebuild. Show "recording" only when the first frames arrive. This fixes #996 / #572.
3. **Fix the network path.** Use one long-lived `URLSession` per provider (HTTP/2, keep-alive), and warm the connection at key-down. Consider FLAC/Opus instead of 16-bit WAV. Choose batch-with-keyterms versus streaming per mode explicitly, because streaming is currently the default for xAI. Add an offline retry queue on top of the kept WAV.
4. **Remove fixed waits and per-recording side work from the hot path.** Remove the 200 ms pre-paste sleep (or make it adaptive). Do not chain the next paste behind the 2 s clipboard restore. Move the duration probe, SwiftData saves and Auto Learn after paste. Start selected-text, clipboard and screen OCR capture only when the active mode's enhancement uses them.
5. **Add the missing features**: an Azure MAI-Transcribe-2 provider with phrase list and a region/endpoint setting (the `CloudProvider` protocol needs more than `apiKey`); a cost tracker (price per audio second and per token per provider over `SessionMetric`); and a working Auto Learn (#985), or a simpler correction capture.

---

## Unresolved questions

- What is the exact MAI-Transcribe-2 REST schema (endpoint, phrase-list field name, size limits)? I did not verify it against Microsoft docs.
- What is VoiceInk's real idle RSS on a cloud-only setup? There is no measurement in issues; it needs a local build and `footprint`, which this audit did not do.
- Does xAI's batch `/v1/stt` endpoint support HTTP/2 and connection reuse, and how much latency does a warm connection save? Not measured.
- Do you plan to distribute your build to anyone? That decides whether GPL obligations apply to code copied from VoiceInk.
- Does SelectedTextKit's `menuAction` strategy touch the clipboard of the focused app? I did not read that package.
