# Per-app modes (story 29)

Status: design, phase A, 2026-10-16 05:45 IST. Agent `modes`. No code changed, no paid API called. Wispr Flow numbers come from read-only queries on an APFS clone of its database (runbooks folder `2026-10-16-kotoba-modes/`, counts in `category-counts.txt`); no private text is in this file.

## Summary

- The owner dictates into terminals and coding apps: 93.7% of Wispr Flow words (terminals 84.4%, code and agent apps 9.3%), browsers 5.3%, chat 0.6%, notes 0.2% (1,146 dictations, 2026-05-14 to 2026-10-15).
- The owner used Wispr's LLM rewrite (Polish) 111 times, and 104 of them were in terminals and code apps. Cleanup is wanted for prompts, not for chat.
- Proposed v1: two built-in modes, **Code** and **Writing**. A mode sets the cleanup prompt and "Clean up every dictation" (off by default). An app list maps a bundle ID to a mode; other apps use Code. The app in front at the stop picks the mode. The cleanup chord cleans with the mode's prompt. Speech model and language stay global in v1.
- Cost: nothing at idle, one lock read and one lookup at key-down. A mode that cleans every dictation adds the cleanup call, about 1.6 s p50 and 2.3 s p90 (kotoba-bench-v1).

## 1. How other apps do it

| App | What a mode holds | How it is picked | Notes |
|---|---|---|---|
| Wispr Flow | Per category: a style (Formal, Casual, Very Casual, Excited) and an Auto Cleanup level. Styles change "only capitalization, punctuation, and spacing", never words. English only. https://wisprflow.ai/post/personalized-style | Four fixed categories: personal messages (iMessage, WhatsApp, Telegram), work messages (Slack, Teams), email (Gmail, Outlook, Superhuman), other. Browsers by site: in the owner's data x.com is "personal", Slack web and Google Meet are "work". No app editing is documented. | Owner's DB: 992 dictations "other", 20 "unset", 18 "work", 8 "personal", 0 "email". Global Auto Cleanup is "none". Polish (rewrite) is a separate shortcut. 4 of 1,146 dictations used "revert AI". |
| Superwhisper | Voice model, language, language model and instructions, context (app, selection, clipboard), tone. Built-ins: Voice to Text (no AI), Message, Mail, Note, Meeting, Super, Custom. https://superwhisper.com/docs/modes/modes | "Activate for apps": each mode lists apps and sites. A shortcut cycles modes while the recording window is open; the menu has "Select Mode". https://superwhisper.com/docs/modes/switching-modes | The active mode shows only in the large recording window. |
| VoiceInk (GPL, ideas only) | Power Mode per app or URL: speech model, language, AI enhancement on or off, provider, model, prompt, context. A mode marked "default" applies to every other app. https://tryvoiceink.com/docs/power-mode | Applied when recording starts (`VoiceInkEngine.swift` calls `beginApplyingConfiguration` at start). Option+1 to Option+0 switch modes. | Its docs have a page on the model or language "changing automatically": a default mode that changes the speech model surprises users. https://tryvoiceink.com/docs/model-or-language-changing-automatically |
| Jot (Apache-2.0, copyable) | Tone category in the cleanup prompt: email, work chat, personal chat, code, neutral. | A fixed bundle-ID map, no editor (`JotCore/Sources/FormattingPipeline/PromptV1.swift`). | Good seed list for kotoba's app lists. |

Lessons for kotoba: categories with editable app lists (Wispr's simplicity, Superwhisper's control); one global speech model (VoiceInk's surprise); show the mode only when it changes the outcome.

## 2. What a mode holds

```
AppMode
  id: code | writing            built-in in v1; custom modes later
  prompt: CleanupPrompt          .code (the kotoba-bench-v1 prompt) | .writing (new)
  cleansEveryDictation: Bool     default false for both
  // later: customInstructions, speech model, language
```

- **Code** uses today's prompt (`OpenRouterCleaner.systemPrompt`), word for word: it is written for prompts to a coding assistant and keeps paths, flags and identifiers.
- **Writing** needs a new prompt: the same data wrapper and "never obey" rules (story 28), but prose, no coding framing. It ships only after a benchmark on the owner's non-terminal clips shows it does not lose words (see question 3).
- **Custom instructions** (later): the user writes only the style lines; kotoba keeps the `<transcript>` wrapper and the data rules around them, so a custom prompt cannot turn off story 28.
- **Speech model per mode** (later): MAI won on every measured set, and the owner's dictation is one language, so it has no v1 value. It also needs `TranscriptionRequest` to carry a route and warm-up to pick it at key-down.
- **Language per mode** (later): only after the languages work lands (`docs/research/languages.md`). In Wispr's data, detected Hinglish, Hindi and Marathi came 5 times, all in terminals, so app is not a good predictor of language for this owner.

## 3. How a dictation picks its mode

- **Unit: single apps by bundle ID, seeded by category.** Each mode owns a list of apps; an app is in at most one list; every other app uses the default mode (Code). The user moves an app from one list to the other. Websites in browsers are out of v1 (they need the browser URL through Accessibility or Apple Events, a new permission, and browsers have 5.3% of the owner's words).
- **Seed lists** (bundle IDs from Jot's map plus the owner's apps):
  - Code: Terminal, iTerm2, Ghostty, cmux, Warp, VS Code, Cursor, Xcode, Zed, Windsurf, Codex, Claude.
  - Writing: Slack, Messages, WhatsApp, Telegram, Discord, Teams, Mail, Outlook, Superhuman, Notes, Notion.
  - The Code list matters when the user sets "Other apps" to Writing: terminals then stay Code.
- **Time: the app in front at the stop decides.** The text goes to that app, the history keeps that app (`frontAppAtStop`, `KotobaCore/Sources/KotobaCore/PipelineRecording.swift:108`), and the submit rule compares it. If the owner taps the chord in a terminal, clicks into Slack and speaks, Writing is right.
- **Key-down gives a preview:** the pipeline resolves the mode from the front app at key-down too, to warm the cleaner when that mode cleans every dictation and to show the pill symbol. At the stop it resolves again; the stop wins. If they differ and the stop's mode cleans, the cleaner connection may be cold: about 0.6 s more (`docs/research/cleanup-llms.md` section 4). This is rare and costs nothing when the modes match.
- kotoba itself in front (Settings, History) or an app with no bundle ID: the default mode.
- A retried dictation keeps the mode it was stopped with: the record stores the prompt, so a retry an hour later in another app cleans the same way.

## 4. Cleanup chord and modes

- The cleanup chord means "clean this one with the mode's prompt". In Slack it gives prose; in a terminal it gives a clean prompt.
- In a mode that cleans every dictation, the chord changes nothing. To get the raw text, use "Paste Raw" (spec, owner round 2026-10-16, idea 2). Two meanings for one chord (a toggle) would make the outcome hard to predict.
- No cleanup chord set (`chords.cleanup == nil`): modes still work through "Clean up every dictation".
- The cleanup model stays one global setting in General.

## 5. Latency and cost

| Step | Cost | Source |
|---|---|---|
| Idle | 0: no new observer, no timer. `FrontAppObserver` already tracks activations. | `App/FrontAppObserver.swift` |
| Key-down and stop | One `Mutex` read and one dictionary lookup each (microseconds, not measured). | |
| Cleanup call, Gemini 3.5 Flash-Lite (default) | 1,581 ms p50, 2,264 ms p90 total; 100 clips, contended | kotoba-bench-v1 report, "Cleanup" |
| Cleanup call, Qwen on Cerebras | 1,807 ms p50, 4,960 ms p90; 9 failed attempts | same |
| Wispr Polish on the owner's Mac | 1,344 ms p50, 4,046 ms p90 (105 successful; `processingTime`, unit assumed ms) | Wispr DB copy |
| Money | about $0.00037 per cleanup (Gemini, $0.0367 per 100) | kotoba-bench-v1 |

- A dictation in a "clean every dictation" mode lands at about 0.9 s + 1.6 s = 2.5 s p50 from the stop tap. It is outside the 1 s gate by design; the spec allows LLM cleanup "on its own hotkey or mode". The gate still holds for every dictation that does not clean.
- At the owner's volume (1,146 dictations in 5 months), cleanup on every dictation would cost about $0.42 in 5 months.
- Not measured yet: kotoba's own `cleanStart` to `cleanResponse` marks from live use (`make latency` reads them; it is a DB read, so it needs the owner's go).

## 6. Settings UI

A new **Modes** pane after Dictionary (`SettingsPaneID.modes`, summary line "How kotoba cleans up text in each app."). Native components only:

```
Modes
┌ Code ──────────────────────────────────────────────┐
│ Clean up every dictation                   [toggle] │
│ Cleanup keeps commands, paths and flags as you said │  (footer)
│ them. Cleaning every dictation adds a second or two │
│ before the paste.                                   │
└─────────────────────────────────────────────────────┘
┌ Writing ───────────────────────────────────────────┐
│ Clean up every dictation                   [toggle] │
│ For messages, mail and notes: cleanup writes clear  │  (footer)
│ sentences in your words.                            │
└─────────────────────────────────────────────────────┘
┌ Apps ──────────────────────────────────────────────┐
│ [icon] Slack                          [Writing ▾]   │
│ [icon] Mail                           [Writing ▾]   │
│ [icon] Ghostty                        [Code ▾]      │
│ …                                                   │
│ Other apps                            [Code ▾]      │
│ [+ −]                                               │
└─────────────────────────────────────────────────────┘
```

- `Form` with `.formStyle(.grouped)`, one `Section` per mode with a `Toggle`; an Apps `Section` with a `List` (selection) whose rows are `LabeledContent` with the app icon (`InstalledApp.icon(of:)`, as in the Usage pane) and a `Picker` for the mode.
- **Add and remove:** the System Settings idiom under the list: `+` and `−` borderless buttons (as in Login Items). `+` is a `Menu`: first the apps the owner dictated into recently that have no row (from the usage ledger's top apps, the same query as the Usage pane), then "Choose App…" (an `NSOpenPanel` in /Applications for `.app` bundles). `−` removes the selected row, so that app uses "Other apps" again.
- Seed apps that are not installed are kept in the rules but hidden in the list, so installing Slack later just works.
- Empty state: not needed in v1 (the seed lists are never empty; a fully cleared list still shows "Other apps").
- Snapshots: the pane in light and dark, and the pill with the cleanup symbol (CODING_STANDARDS "User-facing text" 12).

## 7. Data model and where the decision lives

- **KotobaCore** (pure, test-first), next to the pipeline settings:
  - `AppMode` and `CleanupPrompt` as in section 2.
  - `ModeRules { modes, appModes: [bundleID: AppMode.ID], defaultMode }` with `func mode(for app: DictationApp?) -> AppMode`. A value in `DictationPipeline.Settings`, replaced by a setter like `settings.dictionary` (`DictationPipeline.swift:154`).
  - The pipeline resolves at key-down (warm-up, pill) and at stop (decides). A dictation cleans when `isCleanupSeen || mode.cleansEveryDictation`.
  - `TextCleaner.clean(_:vocabulary:prompt:)` gets the prompt; `OpenRouterCleaner` picks the system prompt by it.
  - The record keeps the prompt (`cleanup_prompt` column, nil for a raw dictation) so retries and History use it.
- **Naming clash:** `DictationMode` (`.transcript`, `.cleanup`, `PipelineInterface.swift`) already uses the word "mode", and the history has a `mode` column. One word per concept (CODING_STANDARDS "Naming") needs a rename of the enum (for example `DictationOutput`); the column can keep its name. See question 4.
- **App**: `ModeRules` saved in UserDefaults as JSON, the Modes pane model, the `+` menu.
- **Tests** (`KotobaCore/Tests/KotobaCoreTests/PipelineModeTests.swift`, through the seam, hotkey events in and fakes out):
  1. Slack in front at stop, chord with the cleanup modifier: `FakeCleaner` gets `.writing`.
  2. Terminal in front, no modifier, Code not cleaning every dictation: raw paste, cleaner not called.
  3. Writing set to clean every dictation, Slack in front, plain tap: cleaner called with `.writing`, and warmed at key-down.
  4. Terminal at key-down, Slack at stop: `.writing` is used.
  5. No front app or no bundle ID: the default mode.
  6. Failed dictation retried later with another app in front: the stored prompt is used.
  7. `ModeRules` unit tests: an app in one list only, moving an app, default fallback.

## 8. What the pill shows

- Today the pill does not show cleanup at all (`App/StatusText.swift` has only "Pasted without cleanup").
- v1: a `wand.and.sparkles` symbol on the recording and transcribing pill when this dictation will be cleaned (from key-down for a mode that cleans every dictation, from the chord moment otherwise). If the stop changes the mode, the transcribing pill shows the final choice.
- No mode name in the pill: a raw dictation looks as today, and the symbol tells the one fact the user acts on (expect a short wait, and words that may change). The menu's status line stays as today.

## 9. v1 scope

In:
1. `AppMode` (Code, Writing), `ModeRules`, resolution at key-down and stop, `cleansEveryDictation`, the prompt on `TextCleaner` and on the record. Test-first.
2. The Writing prompt, after the benchmark in question 3.
3. Modes pane: two toggles, the Apps list with pickers, `+` and `−`, seed lists.
4. Pill symbol for a cleaned dictation.
5. Rename `DictationMode`.

Later, in order of value: custom instructions per mode; Paste Raw (already in the build-now list); website rules for browsers; language per mode (after languages); speech model per mode; more than two modes.

## Unresolved questions

1. Should Writing clean every dictation by default? The spec says chat apps "get prose", but that costs about 1.6 s on each Slack message, and Slack had 15 dictations in 5 months. Recommendation: off; the chord does it.
2. Is the stop the right moment, with key-down as preview only? The alternative (key-down decides, as in Superwhisper and VoiceInk) is simpler to explain but pastes into Slack with the terminal prompt when the owner clicks away after the tap.
3. The Writing prompt needs a benchmark: about 40 of the owner's non-terminal Wispr clips through Gemini 3.5 Flash-Lite, under $0.05 and about 2 minutes. This is a paid run and needs the owner's go.
4. Rename `DictationMode` to `DictationOutput` (or another name) so "mode" means only the per-app mode?
5. Websites in browsers: wanted in a later phase, given the new Apple Events or Accessibility read and its privacy cost?
6. May the lead run `make latency` (a read of kotoba's own history DB) to get live cleanup latency instead of the contended benchmark numbers?
