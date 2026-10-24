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

- Log with `os.Logger`, subsystem `Log.subsystem` (the bundle id: `tech.teensy.kotoba`, or `tech.teensy.kotoba.dev` for a Debug build), one category per module (`Log.pipeline`). Transcripts and keys are logged `privacy: .private`; never log an API key.
- Each hot-path `LatencyMark` (keyDown, firstAudioBuffer, stop, uploadStart, response, pasteSent) is recorded in the dictation's `LatencyLog` as an offset from key-down, emitted as a signpost on `Log.signposter` (points of interest), logged as one notice line on `Log.latency` (with the model and the audio length; `make latency-log` reads it from `log show`), and stored in the `latency_marks` table that `make latency` reads. A new hot-path step gets a mark.
- The network marks (connected, uploadSent, firstByte) come from the system's URLSession metrics through the provider's `Transcript.network`, after the answer. They get no signpost (it would sit at the wrong moment), and the pipeline never waits for them: when the metrics come late, the marks are left out. A new mark name is a new row value, not a schema change.

## Layout

- Colocate by concern: a type, constant or small helper lives in the file of the function that owns it. A separate file only when several modules share it, to break an import cycle, or for an integration of 60+ lines.
- Plain file names after the main type (`DictationPipeline.swift`), no dotted suffixes.
- Files stay under 400 lines (lint). When your edit takes a shared file past 350 lines, move a whole concern into its own extension file first (`PipelineRecording.swift`, `AppMenu.swift`), so the next agent has room. Never trim comments or join lines to pass the limit.
- Platform code lives in `App/`; decisions live in `KotobaCore/`, which imports only Foundation, os and Synchronization. If an adapter starts to decide something, move the decision into the core behind a port.
- The shell (the menu bar icon, the menus' status line and counts, the Dock badge, the start and stop cues) is decided in `ShellStatus` in KotobaCore and tested there. `AppDelegate` and `AppMenu` pass it facts and draw its output; lint refuses a `switch` or `if case` in them.
- Live dictations: what is live (each dictation from key-down until it ends, its step, its Return request and latency marks, the recording and its Undo window, Polish, Transcribe Again and a retry send), what may begin, and what quit waits for live in `KotobaCore/Sources/KotobaCore/LiveDictations.swift`, tested as a pure type in `LiveDictationsTests`. The pipeline changes it only through its transitions and asks it what is live; lint `live_state_in_ledger` refuses a per-dictation collection on the actor, and `live_questions_to_ledger` a hand-made "recording or Undo window" check. An event that reads or changes the recording or its Undo window (a key event, Undo, the Undo window's end, an absence, quit) runs in `DictationPipeline.inTurn`, so it never lands while a capture starts or an Undo resumes; the capture transitions in `PipelineRecording.swift` assert it, and `AudioCapture` refuses a second open capture (`CaptureError.alreadyCapturing`).
- Dictation state: the pipeline reports a `DictationState`, a phase (`DictationPhase`: what is live now) and the notice shown over it (`DictationNotice`: a one-shot outcome). A reader that asks whether a dictation is live reads `phase.isLive`, never a list of cases and never the notice; a switch over a phase or a notice names every case (lint `state_switch_has_no_default`). A new outcome is a notice, never a phase (lint `dictation_phase_cases`): its case and facts in `KotobaCore/Sources/KotobaCore/DictationState.swift`, its words and button in `App/StatusText.swift`, its snapshot row in `App/IndicatorSnapshots.swift`.
- Mic capture: the input lifecycle (which mic records, when its input is built again, what waits for the end of a capture) lives in `KotobaCore/Sources/KotobaCore/AudioCapture.swift`. `App/HALCaptureHardware.swift` only runs the `CaptureHardware` port on CoreAudio; a new device or route rule is a test in `AudioCaptureTests` first (lint `capture_lifecycle_in_core`).
- Billed work: a request whose cost goes to the usage ledger outside a live dictation's send or a job (a primer, the segments a recording did not use, a late cleanup or Polish answer) runs as `work.bill` (`PendingWork`), so quit waits for it beside the sends, all within `DictationPipeline.quitWait`. Lint `billed_work_is_billed` refuses a ledger write in `work.track` or a bare `Task`.
- Segment upload: where a recording is cut at pauses (`UploadSegments`, on the capture writer's thread), what is sent while it records, the join at the stop and the fallback to the whole recording live in `KotobaCore/Sources/KotobaCore/UploadSegments.swift` and `SegmentUpload.swift`, tested in `UploadSegmentsTests` and `PipelineSegmentTests`. `CaptureWriter` only feeds chunks and reports the closed segment. A dictation's segments leave `LiveDictations` only with its stop or `dropSegments`; `LiveDictations.end` asserts it, so a new way to end a dictation fails its tests until it drops them.

## Native components (owner, 2026-10-16)

- Build UI from Apple's own components, in this order: a SwiftUI or AppKit control with its system style (`Form` with `.formStyle(.grouped)`, `Section`, `List` with `.onMove`, `Toggle`, `Picker`, `LabeledContent`, `Button` with system styles, toolbar items, `ProgressView`, `.glassEffect`, SF Symbols); then a composition of them. Build a custom view only when no native control exists. Put a one-line comment on it that names the gap, for example the shortcut recorder.
- Never draw your own copy of a native control: no hand-made drag handles, list rows, separators, toggles, tab bars, or button shapes. Take spacing, fonts and colors from the system (semantic colors, `.font(.body)`), never hard-coded values.
- Settings follows macOS System Settings: a sidebar with grouped forms. Lists that the user orders use the native list reorder.
- Native is the floor, not the goal: each view must also look polished, like a first-party Apple app (clear hierarchy, an empty state for each list, balanced layout). Judge every snapshot as a designer before you report.

## Pages (0.5.0 page system)

The main window's visual system lives in `App/Page/` (plan: docs/research/ui-redesign.md, "Window" and "Page map"). Every page and sheet is built from it; lint refuses the patterns that broke the 0.4 window.

- **Which view for what.** A page is a `PageForm` (a grouped form whose sections stay in a centred column `PageMetrics.columnWidth` wide), or a `PageList` when it lists many selectable rows (History: selection, list keys, rows built as they scroll in), with its rows where the form's cards are; a sheet over a page ("Advanced…") is a `PageSheet`. A settings page opens with a `PageHeader(page:summary:)` in its first `Section`: its tile and name come from the page's `PaneID`, so they match the sidebar. A row with a title and at most one grey subtitle is a `PageRow` (with or without an icon, with trailing content); it is the only way to write one (lint `row_is_page_row` refuses a `LabeledContent`, `Label` or `Toggle` with two Texts). A switch with a title and a subtitle is a `PageToggle`. One choice of a few, each with a plain description (a speech or cleanup model), is a `ChoiceRow`: a check on the chosen row, as a picker cannot show a line under its choices. A page's search is a `PageSearchField`, alone in the header of the section it searches (⌘F focuses it). A sidebar count (Dictionary's suggestions) is `Pane(id:badge:content:)`. A row whose text is not a title and a subtitle (a dictation's one line) puts its icon and text in `RowLeading`; text under a row's title starts in the text column (`.inRowTextColumn()`). An icon in a row is a `SymbolTile` (a symbol on a tint, `PageMetrics.rowTileSide`) or an `AppIconView`; every icon of a page sits in one 28 pt column. A chart card opens with `ChartHeadline`; day bars are `DayBars` over `ChartDays`. A read that failed is a `LoadFailedRow`. A key value with no other row is `LabeledContent("Title", value:)`.
- **PageRow alignment.** Trailing content (a value, keycaps, a button) is centred on the row while the subtitle fits on one line (System Settings > Notifications' app rows), and sits on the title line once the subtitle wraps (Keyboard's "Keyboard navigation"). `PageRow` does this with `ViewThatFits`; never offset a row's parts by hand.
- **A chord never shows alone.** Keycaps (`Keycaps`) or a chord's title always come with the action they start: a row title ("Hands-free"), a menu item's name, the pill's "Dictate". Keycap legends are the primary label colour.
- **Brand colour.** `Color.brand` (the icon's coral, `App/Assets.xcassets/Brand`) is only for charts and the pill's bars, which keep it whatever the accent, as Screen Time's charts do. Selection, buttons and switches follow the user's accent; text uses the system label colours.
- **Design values.** A size the system gives no value for (the column, a tile, a keycap, the window's sizes, a chart's height) is a named value in `PageMetrics` (`App/Page/PageMetrics.swift`) with its source in one line. Page code never writes a number in padding, a frame, spacing, a corner radius, an AppKit inset or size, and does not hide one in a `CGFloat` constant (lint `ui_layout_literal`, `appkit_layout_literal`, `ui_layout_constant`; 0 is allowed). Snapshot code sets render sizes and lives in `*Snapshots.swift`. The pill's values are the pill's (`App/PillGeometry.swift`, `IndicatorPlacement`).
- **Symbols.** Size an SF Symbol with `.font(_:)` at the weight of the text beside it; never `.resizable()` (lint `symbol_not_resizable`). An app icon (`Image(nsImage:)`) may scale, through `AppIconView`.
- **Colours and dividers.** System colours only (lint `ui_fixed_color`); a tile's white glyph is `SymbolTile`'s. Grouped sections separate content: no `Divider()` or drawn separator (lint `ui_divider`). A grouped form is a `PageForm` or `PageSheet` (lint `page_form`).
- **No toolbar.** A page has no toolbar items, so the title bar keeps one height on every page (`make view-checks` switches through the pages and fails on a move). Controls go in the page: a period switch above its chart card, as Battery's.
- **Durations** are `Duration.pageText`: the system formatter's narrow units ("14h 20m", "42s"), as Screen Time.
- **Ratchet.** A page not on the system yet starts with `// 0.5.0 ratchet: the <page>'s rollout …` and `// swiftlint:disable <page rules it breaks>`. Its rollout removes both lines; `superfluous_disable_command` fails a line that hides nothing, and `scripts/ratchet-done.sh` (first step of `make release`) fails while a ratchet line or a page with a toolbar (`pagesWithToolbar`) remains.
- **New page.** Add its case to `PaneID` (title, symbol, tint, group), a `Pane` factory and a model in a feature folder (`App/Activity/`), and its snapshots; register the whole window in `SettingsSnapshots.windowSnapshots`, and check every PNG in light and dark, at the default size and at `PageMetrics.maximumWindowWidth`.

## Windows and text entry

- kotoba is a Dock app by default (story 35); with "Show in Dock" off it is an agent with no visible menu bar while no window is open. `App/MainMenu.swift` builds one main menu for both: the kotoba app menu first (About, Settings…, Hide, Quit ⌘Q), then File > Close, the Edit menu (Undo, Redo, Cut, Copy, Paste, Select All, Find > Find…), Window and Help. Without it, Cmd-W and Cmd-X/C/V/A/Z do nothing in any text field and macOS beeps. Never remove it; a new window with text entry needs no extra wiring.
- Only `DockAndMenuBar` sets the activation policy (lint `activation_policy`). A window that the owner opens goes through `WindowFront`, so it counts as open for "Show in Dock" off.
- Every new window or pane with a text field gets a manual test row in `docs/testing/phase2-manual.md` for Cmd-V and Cmd-A, because snapshots and unit tests cannot catch a missing responder action.

## User-facing text

Reference: the copy deck in `docs/research/ux-polish.md` (sections 4.1-4.6). A new string follows these rules; review checks them, and `.swiftlint.yml` enforces 3, 4 (a modifier name joined to a key, such as "Cmd+V"), 5, 8, 13 and 14 on UI-building lines (and on the line after the builder's `(`). A view that takes visible text as a parameter (a header card, a row) adds its name to the UI-builder list of every `ui_text_*` rule; `scripts/ui-text-builders.sh` (`make lint`) fails when the lists differ.

1. Brand: always "kotoba", lowercase, also at the start of a sentence.
2. Capitalisation (Apple HIG): Title Case for menu items, buttons, window and pane titles, section headers. Sentence case for toggle and field labels, footers, help text, pill messages and status lines.
3. Ellipsis "…" (one character) only on an item that opens a window or needs more input ("Settings…"). Never "...".
4. Keys: modifier symbols ⌃ ⌥ ⌘ ⇧ fn and ⌘V in UI, never the key names in words, onboarding included (owner, 2026-10-16).
5. No internal terms in UI: route, keyterm, ZDR, zero-data-retention, needsSetup, provider slugs, API parameter names, "untested", owner-specific numbers, file paths (unless the user must act on one).
6. An error says what happened and what to do next, names the service ("Couldn't reach OpenRouter"), says when the audio is saved, and puts the fix on a button. Never blame the user.
7. A pill message fits the 360 pt pill (about 34 characters); the snapshot run fails on truncation. A live pill (recording, transcribing, cleanup, rewrite) shows no words: the pill reads `pillText`, which is nil there (lint `pill_reads_pill_text`; the snapshot run fails on words in a live pill), and the menu status line reads `statusText`. The pill has one glass, its capsule; its buttons use a fill (lint `glass_on_navigation_layer_only`; the snapshot run fails on a second glass view). Symbols and text take text styles, never a point size (lint `ui_font_size_literal`).
8. No " - " between phrases: two sentences, a colon, or "·" for a value after a state.
9. One word per concept: Recording (live state; owner, 2026-10-24, was Listening), dictation, speech model, key, word, replacement, suggestion.
10. Counts inflect (`AttributedString(localized: "^[…](inflect: true)")`); hide a zero count instead of "(0)".
11. Pill and menu status strings live in `App/StatusText.swift` only.
12. Every new window, pane, `DictationPhase` and `DictationNotice` gets a snapshot in `App/Snapshots.swift` (light and dark).
13. Typographic punctuation: curly apostrophe and quotes (’ “ ”) in UI text, never ' or " inside the visible words.
14. Voice (Apple HIG Writing, Apple Style Guide): no “we”, “our” or “us” (name kotoba or the thing), no “please”, no “enable”, “disable” or “toggle” (a switch’s label names what is on: “Keep filler words”), no interjections (“oops”, “sorry”).
15. Keys: “press” and “hold”, never “tap” (“Press ⌃⌥⌘ to start, press it again to stop.” “Hold ⌥ while you speak.”). In code, “tap” stays the name of a short chord press (Naming). Lint `status_text_press_not_tap` checks `App/StatusText.swift`; the copy pass adds the rule for the other UI text.

## Tests

- Tests sit in `KotobaCore/Tests/KotobaCoreTests/`, one file per concern (`PipelineHotkeyTests.swift`, `PipelineClipboardTests.swift`) sharing `Fakes.swift`, using Swift Testing (`@Test`, `#expect`).
- Drive the public seam with events and assert outcomes on fakes: text pasted, clipboard restored, audio kept, latency recorded. Control time with `ManualClock.advance(by:)`.
- Provider request building and response parsing are tested against recorded fixtures. Live API calls belong to `bench/`.
- A cost test counts work, never time: a read on a large history asserts what it costs SQLite (`costs(on:of:)`, `SQLiteDatabase.StatementCost`: statements, steps, full-scan steps, sorts) on 5,000 rows and on 10,000, both on a store with no planner statistics (a new install) and on one opened again after the fill (`PRAGMA optimize` at launch). A read through an index costs the same on both; a scan grows no faster than the rows. Its time limit goes in the package's `TimingTests` suite (`make timing`), off in `make test`.
