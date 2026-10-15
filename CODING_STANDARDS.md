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
- Each `LatencyMark` (keyDown, firstAudioBuffer, keyUp, uploadStart, response, pasteSent) is recorded in the dictation's `LatencyLog` and emitted as a signpost on `Log.latency` (points of interest). The latency report reads these; a new hot-path step gets a mark.

## Layout

- Colocate by concern: a type, constant or small helper lives in the file of the function that owns it. A separate file only when several modules share it, to break an import cycle, or for an integration of 60+ lines.
- Plain file names after the main type (`DictationPipeline.swift`), no dotted suffixes.
- Platform code lives in `App/`; decisions live in `KotobaCore/`, which imports only Foundation, os and Synchronization. If an adapter starts to decide something, move the decision into the core behind a port.

## Tests

- Tests sit in `KotobaCore/Tests/KotobaCoreTests/`, one file per source file (`DictationPipelineTests.swift`), using Swift Testing (`@Test`, `#expect`).
- Drive the public seam with events and assert outcomes on fakes: text pasted, clipboard restored, audio kept, latency recorded. Control time with `ManualClock.advance(by:)`.
- Provider request building and response parsing are tested against recorded fixtures. Live API calls belong to `bench/`.
