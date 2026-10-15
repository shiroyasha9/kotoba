# Coding standards

`make check` enforces what a tool can check (`.swift-format`, `.swiftlint.yml`, Swift 6 with warnings as errors). This file covers the rest.

## Naming

- Types are nouns from the spec's vocabulary: dictation, chord, tap, hold, transcript, keyterm, provider, route. One word per concept across code, tests and docs.
- Port protocols name the role (`Paster`); app adapters name the technology plus the role (`CGEventPaster`, `NSPasteboardAdapter`). Test doubles start with `Fake` (`FakePaster`).
- Booleans read as assertions (`isRecording`, `hasMicAccess`).

## Concurrency

- Swift 6 language mode, complete strict concurrency. Silence nothing: `@unchecked Sendable` and `nonisolated(unsafe)` need a comment that names the lock or queue that makes them safe.
- Mutable shared state lives in an actor (`DictationPipeline`) or behind a `Mutex` (Synchronization). AppKit types stay on `@MainActor`.
- Real-time callbacks (audio tap, CGEventTap) do no allocation, locking or logging beyond a constant-time hand-off, then return. Heavy work moves to a task.
- Every `Task` has an owner that keeps a handle and cancels it. Ports are `async` and `Sendable`.

## Error handling

- Each module throws its own typed errors (`enum ProviderError: Error`) with the data needed to act: HTTP status, retryable or not.
- A failed dictation keeps its audio and becomes `.failed` in the `Store`; it is retried, never dropped. User-facing failures appear in the indicator, not in an alert.
- `try?` only where failure is truly irrelevant, with a comment saying why.

## Logging and latency

- Log with `os.Logger`, subsystem `tech.teensy.kotoba`, one category per module (`Log.pipeline`). Transcripts and keys are logged `privacy: .private`; never log an API key.
- Each `LatencyMark` (keyDown, firstAudioBuffer, stop, uploadStart, response, pasteSent) is recorded in the dictation's `LatencyLog` as an offset from key-down, emitted as a signpost on `Log.signposter` (points of interest), logged as one line on `Log.latency`, and stored in the `latency_marks` table that `make latency` reads. A new hot-path step gets a mark.

## Layout

- Colocate by concern: a type, constant or small helper lives in the file of the function that owns it. A separate file only when several modules share it, to break an import cycle, or for an integration of 60+ lines.
- Plain file names after the main type (`DictationPipeline.swift`), no dotted suffixes.
- Platform code lives in `App/`; decisions live in `KotobaCore/`, which imports only Foundation, os and Synchronization. If an adapter starts to decide something, move the decision into the core behind a port.

## Windows and text entry

- kotoba is `LSUIElement` (no Dock icon, no visible menu bar), but it keeps a hidden main menu with a standard Edit menu (Undo, Redo, Cut, Copy, Paste, Select All). Without it, Cmd-X/C/V/A/Z do nothing in any text field and macOS beeps. Never remove it; a new window with text entry needs no extra wiring.
- Every new window or pane with a text field gets a manual test row in `docs/testing/phase2-manual.md` for Cmd-V and Cmd-A, because snapshots and unit tests cannot catch a missing responder action.

## User-facing text

Reference: the copy deck in `docs/research/ux-polish.md` (sections 4.1-4.6). A new string follows these rules; review checks them, and `.swiftlint.yml` enforces 3, 5 and 8 on UI-building lines.

1. Brand: always "kotoba", lowercase, also at the start of a sentence.
2. Capitalisation (Apple HIG): Title Case for menu items, buttons, window and pane titles, section headers. Sentence case for toggle and field labels, footers, help text, pill messages and status lines.
3. Ellipsis "…" (one character) only on an item that opens a window or needs more input ("Settings…"). Never "...".
4. Keys: modifier symbols ⌃ ⌥ ⌘ ⇧ fn and ⌘V in UI. Onboarding spells the names once.
5. No internal terms in UI: route, keyterm, ZDR, zero-data-retention, needsSetup, provider slugs, API parameter names, "untested", owner-specific numbers, file paths (unless the user must act on one).
6. An error says what happened and what to do next, names the service ("Couldn't reach OpenRouter"), says when the audio is saved, and puts the fix on a button. Never blame the user.
7. A pill message fits the 360 pt pill (about 34 characters); the snapshot run fails on truncation. The menu status line uses the same text.
8. No " - " between phrases: two sentences, a colon, or "·" for a value after a state.
9. One word per concept: Listening (live state), dictation, speech model, key, word, replacement, suggestion.
10. Counts inflect (`AttributedString(localized: "^[…](inflect: true)")`); hide a zero count instead of "(0)".
11. Pill and menu status strings live in `App/StatusText.swift` only.
12. Every new window, pane and `DictationState` gets a snapshot in `App/Snapshots.swift` (light and dark).

## Tests

- Tests sit in `KotobaCore/Tests/KotobaCoreTests/`, one file per concern (`PipelineHotkeyTests.swift`, `PipelineClipboardTests.swift`) sharing `Fakes.swift`, using Swift Testing (`@Test`, `#expect`).
- Drive the public seam with events and assert outcomes on fakes: text pasted, clipboard restored, audio kept, latency recorded. Control time with `ManualClock.advance(by:)`.
- Provider request building and response parsing are tested against recorded fixtures. Live API calls belong to `bench/`.
