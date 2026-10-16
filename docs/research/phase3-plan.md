# Phase 3: plan for the rest

Status: plan, 2026-10-16 10:35 IST. Agent `phase3-research`. Read-only on code: no source changed, no database opened, no paid API called. Inputs: `docs/spec.md` (stories 29-34, "Order after this round", the beyond-wispr bullets), `docs/research/beyond-wispr.md`, `auto-learning.md`, `ux-polish.md`, `per-app-modes.md`, and the code at `e1bb855` plus the working tree. Apple API facts come from the macOS 27 SDK headers and Apple's docs (sources in each section).

Done before this plan: History window, usage tracker, audio retention, per-app modes (local, not pushed), Insights (another agent finishes it now).

## Summary

- Ideas 2, 3 and 4 are already built (phase 2.6, commit `83d76c2`), with tests and manual rows. Section 1 lists what is left: the owner's manual test, and three small optional gaps.
- Story 32 is mostly built: readback after paste, "Fix Last Dictation…", Suggestions. Left: the live readback check on the owner's apps, history mining, the one-time Wispr history seed, and an "Add to kotoba Dictionary" system service. Section 2.
- Idea 5 (rank and cap terms) is a precondition of idea 1, because context terms share the route's 100-term cap. Build it first. Below the cap it changes nothing, so the risk "it drops a needed term" applies only past 100 terms. Section 3.
- Story 34 and idea 1 (context) need the owner's privacy decision. Section 4 gives five options. Recommendation: off by default; when on, send only identifier-shaped tokens from the active Claude Code or Codex session, the repo name and the branch, as keyterms. Never send screen text to the speech model.
- Follow-ups (section 5): Cmd-F in the Dictionary search (S), the `GeneralModel` parameter cleanup (quality #17, S), "Fix Dictation…" from a History row with "Add Selected Word" (S, no custom text view), and recovery of audio files that have no History row (S-M). The orphan recovery needs one fix first: Delete removes the row before the file, so a failed file removal leaves an orphan the owner wanted gone.
- Section 6 gives a build order in three waves, with the files of each item, so parallel agents do not edit the same file.

## 1. Ideas 2, 3, 4: built in phase 2.6

| Idea | What is built | Code | Tests |
|---|---|---|---|
| 3, submit after paste | Return while recording stops the dictation and sends Return after the paste (`HotkeyEvent.submit`). A transcript that ends with "press enter" or "press return" pastes without the phrase, then Return (`SubmitPhrase`, General toggle, on by default). Return goes only to the app in front at the stop; otherwise the pill says "Didn’t press Return: app changed" (`returnSkipped`). A retry never sends Return. | `KotobaCore/Sources/KotobaCore/SubmitPhrase.swift`, `TranscriptDelivery.swift:114-135`, `App/HotkeyTap.swift:51` | `PipelineSubmitTests.swift`; manual rows 230-249, 288-289 |
| 4, live "no sound" warning | After 2 s with every level under -72 dBFS, or with no level, the pill shows "No sound from the mic" with "Microphone…". The first level with sound clears it. One timer on the pipeline clock, only while recording. | `KotobaCore/Sources/KotobaCore/NoSoundPolicy.swift`, `PipelineRecording.swift:51` | `NoSoundPolicy` and `PipelineNoSound` tests; manual rows 266-272 |
| 2, Paste Last, Copy Last, Paste Raw | Menu items "Paste Last Dictation", "Paste Last Without Cleanup" (only after a cleanup dictation), "Copy Last Dictation". The paste goes through the clipboard guard. History has "Copy Without Cleanup". | `App/LastDictation.swift`, `App/StatusMenu.swift:122-135`, `DictationPipeline.swift:168-187` | `PipelinePasteAgainTests.swift`; manual rows 241-244, 290 |

What is left:
- The owner runs the manual rows above. The result column is empty for all of them.
- Gap A (optional, M): a global shortcut for Paste Last and Copy Last. Wispr uses ⌃⌘V and ⌃⌘C. Today the items are in the menu only. Design: a third chord role in `HotkeyChords` (modifier + key, set in the shortcut recorder, unset by default), classified in `HotkeyClassifier`, consumed by the active tap (`App/HotkeyTap.swift` already uses `kCGEventTapOptionDefault`, which "is an active filter", `CGEventTypes.h:415-419`). `NSEvent.addGlobalMonitorForEvents` cannot be used: "you cannot modify or otherwise prevent the event from being delivered" (`NSEvent.h`). Cost: no idle work; one more key compare per key event in the tap. Recommendation: build it only if the owner asks; the menu covers the need, and a default ⌃⌘V can take a shortcut from another app.
- Gap B (optional, S): a submit key per mode (Return or ⌘Return), as Aqua offers. Return works in Claude Code, Codex, Slack and browser fields. Recommendation: wait for a real miss.
- Gap C: "send it" as a phrase. Recommendation: no. Manual row 235 checks that "send it" pastes as spoken; the phrase is common in normal speech.

## 2. Story 32: learning from edits

### 2.1 What is built

- Readback after paste (`KotobaCore/Sources/KotobaCore/EditReadback.swift`, `App/Readback.swift`). It is event-driven: one `AXObserver` per paste on a thread made for the session, with `kAXValueChangedNotification`, `kAXUIElementDestroyedNotification` and `kAXFocusedUIElementChangedNotification`. It reads a bounded range (`kAXStringForRangeParameterizedAttribute`), never reads a secure field, and ends after 60 s, on focus loss, on submit or at the next dictation. There is no work at idle. Full design and costs: `auto-learning.md`, "Readback (phase 2.6)".
- `CorrectionDetector` (pure), the `dictionary_suggestions` table, the Suggestions section, the menu count, and "Fix Last Dictation…".
- So the Accessibility question is answered: the cheap, event-driven path is the observer above, and it is built. It cannot read terminal prompts that empty on Return (79% of the owner's cmux dictations gave Wispr no edited text, `auto-learning.md` 1.2).

### 2.2 What is left

**a. Live readback check (S, the owner's time).** `auto-learning.md` says "Not measured live yet". The owner runs manual rows 290-307 in Slack, Cursor, a browser and cmux. The lead then reads the readback signposts with Instruments. No code change unless an app fails.

**b. History mining (M).** `SuggestionCandidate.Origin.history` exists but nothing uses it.
- Behaviour: kotoba finds repeated near-misses of a dictionary term in past transcripts (for example "super base" heard 3 times while `Supabase` is a term), and suggests a rule. It also compares raw and cleaned text of cleanup dictations: where the cleaner wrote a dictionary term that the raw text did not have, the raw span is a candidate. Results go to Suggestions; nothing is added at once.
- Seam: a pure `NearMissMiner` in KotobaCore: input one delivered transcript, the raw text, the dictionary and the dismissed pairs; output candidates with a key for counting. It runs per dictation, after the paste, from the history change stream (`DictationPipeline.historyChanges`, already consumed by `App/SettingsController.swift:61`). The count lives in `dictionary_suggestions.evidence` (pending until 3). A one-time pass over old history runs when the owner opens the Dictionary pane the first time after the update, in batches of 500, off the main thread.
- Tests: table tests in `NearMissMinerTests.swift`: 3 sightings give a suggestion, 2 do not; a common heard word gives a term only, never a rule; a dismissed pair never returns; a cleaner diff that adds a term gives a candidate; a cleaner rewrite of a whole sentence gives none.
- Cost: under 1 ms per dictation (word n-grams of one transcript against at most 100 terms), after Cmd-V. No idle work. No framework.
- Privacy: local only. Only word pairs are stored.

**c. One-time Wispr history seed (S-M).** `Origin.wispr` exists but nothing uses it.
- Behaviour: one button next to the Wispr dictionary import: "Learn From Wispr Flow History…". It runs `CorrectionDetector` over Wispr's `History` rows (pasted text against `editedText`, about 44 rows with word edits on the owner's Mac) and adds the results as pending suggestions with a count first.
- Seam: `KotobaStorage/Sources/KotobaStorage/WisprFlowImport.swift` already clones Wispr's database safely. Add a read of `History(pastedText, editedText, app)`; the detector is unchanged.
- Privacy: Wispr's transcripts stay in memory and are dropped after the run. The spec has "History import is not in scope"; this reads history but imports only word pairs. Owner decision (`auto-learning.md` question 4).

**d. "Add to kotoba Dictionary" system service (S).**
- Behaviour: the owner selects a word in any app that supports Services (Terminal, TextEdit, Mail, Safari; Electron and Ghostty: UNCONFIRMED), and picks Services > "Add to kotoba Dictionary". The word becomes a term, and the pill shows "Added <word>" with Undo (the same pill as a learned word). This covers terminals, where readback fails, with no Accessibility read at all.
- Seam: `NSServices` in `project.yml` (`NSMessage`, `NSPortName` kotoba, `NSSendTypes` `NSStringPboardType`, `NSMenuItem`, and `NSRequiredContext` as an empty dict). Apple: "Always include this property … Otherwise the system registers your service, but does not automatically present it in the Services menu." (https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html). A provider object set with `NSApp.servicesProvider` (`NSApplication.h:549`) reads the string and hands it to the dictionary model. The term check (trim, at most 50 characters, one to four words, not already present) is a pure function in KotobaCore next to `PersonalDictionary`.
- Tests: pure tests of the term check; one manual row in Terminal and one in TextEdit.
- Cost: one provider object at launch; no work until the owner picks the item. A new service can need a logout before it shows (same Apple guide). Whether macOS launches kotoba for the service when it is not running: UNCONFIRMED.
- Privacy: only text the owner selected and sent.

## 3. Idea 5: rank and cap dictionary terms per request

Today `PersonalDictionary.keyterms` (`KotobaCore/Sources/KotobaCore/PersonalDictionary.swift:22-34`) sends the terms and then the rule replacements, in list order, and stops at 100. A term past position 100 is never sent, with no signal to the owner.

- Behaviour: at or under the cap, every term goes, in today's order: nothing changes. Over the cap, kotoba sends the terms that matter most: pinned terms, then terms added in the last 14 days, then terms by recent use, then the rest. The Dictionary pane marks the terms that were not sent with the last dictation ("Not sent: the list is over 100 words"). Optional pin (a star per row, like Wispr's starred terms): a pinned term is always sent.
- Seam: a pure `TermRanking` in KotobaCore. Input: the dictionary, a `TermUse` per lowercased term (`uses`, `lastUsedAt`, `addedAt`, `isPinned`), the context terms (section 4, empty for now), the limit, and the time. Output: the keyterms. Score: `uses × 0.5^(age in days / 30)`. Ties keep list order. `Settings.request(for:)` (`PipelineInterface.swift:138-142`) calls it, with a `TermUse` snapshot that the App hands to the pipeline as it does the dictionary (`updateDictionary`).
- Use counts: after a delivered dictation, a pure `TermHits.count(in:terms:)` finds which keyterms appear in the delivered text (whole words, case-insensitive; `zod` does not match `zodiac`; `order_id` and `auth.ts` match as written). The App adds them to a new `term_use` table in `dictionary.sqlite`. It cannot go in `dictionary_terms`, because `DictionaryStore.save` rewrites that table on each save (`auto-learning.md` 4.4). The trigger is the history change stream, after the paste.
- Tests: `TermRankingTests.swift`: under the cap the output equals today's `keyterms`; over the cap, pinned and recent terms stay; a term with old use falls below a term with recent use; context terms come first and the total never passes the limit; case-insensitive duplicates drop; a rule replacement counts as a term. `TermHitsTests.swift` for the word rule. One pipeline test: with a `TermUse` snapshot and 120 terms, `FakeProvider` gets the ranked 100.
- Cost: ranking at the stop sorts at most a few hundred strings (microseconds; measure with the `uploadStart` mark). The hit count runs after Cmd-V: one pass over the text per dictation, under 1 ms. One SQLite upsert in the dictionary file, off the hot path. No idle work.
- Privacy: local counts only. No change to what leaves the Mac.
- Risk: a needed term past the cap is dropped. Mitigation: no ranking under the cap; recent terms and pins stay; the pane shows what was not sent. Whether a list shorter than 100 helps MAI is unknown (phrase-list limits are not published, spec Unresolved 1). A bench pass with 25, 50 and 100 terms on kotoba-bench-v1 would answer it: about 1.7 h of audio per pass at $0.10/h, so about $0.50 for three passes and about 15 minutes. It needs the owner's go.
- Size: S-M.

## 4. Story 34 and idea 1: context awareness

The owner parked this. It is the one item with a real privacy trade-off, so this section lays out the options. Nothing here is built.

### 4.1 Why it matters

The main error class is identifiers. A short, relevant term list helps a lot and a long list hurts (`beyond-wispr.md` section 3: context biasing cut biased-word WER by up to 88% relative; bias lists degrade past about 100 phrases). The owner dictates mostly to Claude Code and Codex in cmux (210 of 275 bench clips).

### 4.2 Options

| Option | What leaves the Mac | Value for this owner | Cost |
|---|---|---|---|
| A. Off (today) | Dictionary terms only | none | none |
| B. Local evidence only | Nothing new. Context makes a corrected word a strong learning candidate when it is a repo identifier | Low-med: better learning, no accuracy gain on the first dictation | S |
| C. Session and repo terms as keyterms | Up to about 30 identifier-shaped tokens per dictation (for example `TermRanking`, `order_id`, `auth.ts`, `--strict`), the repo name and the branch, inside the speech request | High: targets the main error class | M |
| D. Selected text at chord-down | Identifier tokens from the selection as keyterms (C's filter); or the selected text itself to the cleanup LLM for cleanup dictations only | Med in editors and browsers; terminals rarely expose a selection | S-M |
| E. Window text or screen OCR | Free text from the screen | Low-med; VoiceInk's OCR on every recording is a known latency fault (spec, Approach) | Reject |

Recommendation: C, off by default, with one switch "Use words from your coding session". Add D's keyterm part later under the same switch. Keep free text out of the speech request in all options. Send selected text to the cleanup LLM only behind its own switch, and only if the owner asks.

### 4.3 Design for option C

- Behaviour: with the switch on and the front app in Code mode, kotoba adds the terms of the current coding session to the request. History shows the terms sent with each dictation ("Sent words: …"), as Superwhisper does, so the owner can see what left the Mac.
- Sources, read at chord-down, off the hot path (`beyond-wispr.md` 3.1):
  1. The newest session file by modification time: `~/.claude/projects/<folder>/<session>.jsonl` and `~/.codex/sessions/<year>/<month>/<day>/<file>.jsonl`. One `stat` per project folder.
  2. The repo: its name, and the branch from `.git/HEAD` (one small file read).
  3. Identifier tokens from the last 32 KB of that session file: camelCase, snake_case, dotted file names, `--flags`, ranked by count.
  4. Optional later: file names from `git ls-files`, cached by repo and HEAD. It needs a `Process` spawn (10-50 ms, estimate), so it waits for evidence that the session tokens are not enough.
- Secret filter, before any token can leave: drop tokens that match the key shapes in `scripts/privacy.sh` (`sk-`, `xai-`, `ghp_`, `AKIA`, `AIza`, `xox`), long hex or base64 runs (20 or more characters), email addresses, URLs, absolute paths, and tokens over 50 characters (the route limit). Drop tokens that are only digits.
- Seam: a new port `ContextSource` in `DictationPipeline.Ports`: `func terms(for app: FrontApp?) async -> [String]`. The pipeline starts it as a task at chord-down (only with the switch on and Code mode). At the stop it takes the result only if it is ready, and never waits. `TermRanking` (section 3) puts context terms first, within the same limit. The token extractor and the secret filter are pure (`ContextTerms.swift` in KotobaCore). The App adapter (`App/SessionContext.swift`) does the file reads. The record keeps the sent context terms (a new nullable `context_terms` column in `dictations`; see the migration note in section 6). A retry sends the kept terms again.
- Tests: `ContextTermsTests.swift`: the token shapes; every secret shape is dropped; the cap. Pipeline tests with `FakeContextSource`: a source that never answers gives a request with dictionary terms only, and the stop-to-paste time does not change (`ManualClock`); a ready source puts its terms first; with the switch off the source is never called; Writing mode never calls it; the record keeps the sent terms; a retry sends the kept terms.
- Cost: at chord-down, in a task: tens of `stat` calls, one 32 KB read, one tokenise, one small read of `.git/HEAD` (about 1-3 ms in all, estimate; measure with a signpost). Stop path: 0 ms, because the pipeline never waits. The request grows by about 1-2 KB. The effect of a longer phrase list on MAI latency is unknown; the bench in 4.4 measures it. Idle: no watcher, no timer, no task. No framework at launch.
- Permissions: kotoba is not sandboxed. `~/.claude/` and `~/.codex/` are not in Apple's protected list ("Documents, Downloads, Desktop, iCloud Drive, and network volumes", https://support.apple.com/guide/security/secddd1d86a6/web), so no prompt is expected. A repo inside Documents or Desktop would trigger a TCC prompt when kotoba reads `.git/HEAD`: kotoba then skips the branch.
- Limits: two agents in two repos at once can make kotoba pick the wrong session (the newest file wins). cmux's focused pane is not known without its socket (`beyond-wispr.md` question 4).
- Size: M (C), plus S for the History column and the switch.

### 4.4 Measure before turning it on

A bench run: the kotoba-bench-v1 cmux clips with session terms from the matching Claude Code session, against the dictionary only. Clips map to sessions by time. About 1.3 h of audio, so about $0.15 per pass and about 10 minutes. It needs the owner's go. Gate: term recall goes up and WER does not go up.

### 4.5 Privacy notes

- Session files hold whole conversations, which can hold secrets. kotoba reads them in memory, keeps only filtered tokens, and never logs them (`privacy: .private`).
- The terms go to the chosen speech route (OpenRouter by default, then Microsoft). They are words such as file and symbol names, not sentences. Some are still private (client names in a branch, internal product names).
- The switch is off by default (spec story 34). The History column shows the owner what was sent.

## 5. Small follow-ups

### 5.1 Cmd-F in the Dictionary search (S)

- Behaviour: in Settings > Dictionary, ⌘F (Edit > Find…) puts the cursor in "Search words". In other panes it does nothing, as today.
- Design: copy the History pattern. `HistoryWindowController.performTextFinderAction(_:)` (`App/History/HistoryWindow.swift:48-51`) takes the action as the window delegate and counts requests; the view focuses its field with `.searchFocused` (`App/History/HistoryView.swift:14-15`; `searchFocused` is macOS 15 or later in the SDK). `SettingsWindow` (the window delegate) adds the same method and a find counter in its `Selection`; `DictionaryPane` gets `@FocusState`, `.searchFocused` and `.onChange` of the counter.
- Tests: a manual row (⌘F with the focus in the list, in the toolbar and in the Add sheet). Snapshots do not change.
- Cost: none. Privacy: none.
- Note: `App/Settings/DictionaryPane.swift` has 368 lines. The edit may pass 350, so move one concern out first (for example `EntryEditor` to `App/Settings/EntryEditor.swift`), per `CODING_STANDARDS.md` Layout.

### 5.2 General pane: quality item #17 (S)

#17 is from the phase 2.6 quality review (`review26-quality`): "`GeneralModel` has too many parameters, and its doc comment is out of date". It is about the model's init, not the pane's sections.
- Today: the private init of `GeneralModel` (`App/Settings/GeneralPane.swift:96-118`) takes 13 parameters: each value and its setter closure come in apart (anchor, visibility, submit phrase, update checks). The doc comment is now current.
- Design: group each value with its write into one small struct, as `LoginItem` already does: for example `struct Choice<Value> { var read: @MainActor () -> Value; var write: @MainActor (Value) -> Void }`, with `.live` values for the indicator, the submit phrase and the updater, and fixed ones for `sample()`. The init then takes `settings`, `chords`, `audio` and one `Bindings` struct. The convenience init in the same file keeps its signature, so `App/AppDelegate.swift` does not change.
- Tests: `make snapshots` (`settings-general`, `settings-general-login-failed` and its check stay the same).
- Cost: none.
- The pane's sections (Shortcut, Paste, Startup, Feedback, History, Updates) follow System Settings and need no change. If the owner wants a visual change, it is a separate item.

### 5.3 "Fix Dictation…" from a History row, with "Add Selected Word" (S)

The progress note says History "Add to Dictionary…" needs a custom text view. It does not, with this design:
- Behaviour: the History row menu gets "Fix Dictation…". It opens the Fix window with that row's text. The owner edits and clicks Learn, as in "Fix Last Dictation…". The Fix window also gets "Add Selected Word": the owner selects a word in the editor and adds it as a term with no edit (for a transcript that was right but has a new word).
- Design: `FixLastDictationController` (`App/FixLastDictation.swift`) takes the text to fix as an argument instead of only the last dictation. The editor uses `TextEditor(text:selection:)` with `TextSelection` (macOS 15 or later in the SDK, so native on macOS 26). `HistoryView.menu(for:)` (`App/History/HistoryView.swift:97-115`) adds the item for one row with text.
- Tests: the Fix model's existing tests plus one for "Add Selected Word" (a selection inside one word adds that word; an empty selection disables the button). A snapshot of the Fix window opened from a row. Manual rows for Cmd-V and Cmd-A in the editor (`CODING_STANDARDS.md`, Windows and text entry).
- Cost: none at idle; the window is built on open, in a process that has History's SwiftUI loaded already.
- Privacy: kotoba's own text only.

### 5.4 Audio files with no History row (S-M)

Where orphans come from:
- A crash, a force quit or a power loss during a recording. The row is first saved at the stop (`TranscriptDelivery.swift:56-58`) or at a normal quit (`DictationPipeline.shutdown`, `.pending`), so a hard stop during recording leaves `<id>.flac` with no row.
- A failed save (`Store.saveOrLog` logs and goes on, `Store.swift:195-201`).
- A failed Delete. `HistoryStore.deleteRows` (`KotobaStorage/Sources/KotobaStorage/HistoryStore.swift:225-230`) deletes the rows first and then the files. When a file removal fails, the file stays with no row. That file is one the owner deleted. Recovering it would break the rule "a deleted dictation stays deleted" (commit `15617d4`). This is a pre-existing bug; fix it as part of this item: remove the files first, then delete only the rows whose file is gone, as retention does. The rows of a file that cannot be removed stay, and History says the delete did not finish.

Design:
- Behaviour: at launch, kotoba finds audio files with no row and gives each one a row with status `.pending`, as a quit does. The retry queue then transcribes them into "Recovered Dictations". Nothing is pasted. A file with no readable audio gets a `.cancelled` row with no text, so the owner sees it in History and can delete it. kotoba never deletes an orphan by itself.
- Seam: a pure rule in KotobaCore, `OrphanAudio.records(files:knownIDs:launchedAt:)`: a file is an orphan when its name is `<UUID>.flac`, no row has that id, and it was created before this launch (so a recording that started after launch is never taken). The App lists the audio folder once (names and creation dates only), reads each orphan's length with `AVAudioFile`, and saves the rows before the launch retry runs (`RetrySelection.exceptNeedsSetup`). KotobaStorage gets one query: which of these ids have rows (one `json_each` statement, as `markAudioDeleted` does).
- Tests: `OrphanAudioTests.swift` (pure): a known id is skipped; a file created after launch is skipped; a name that is not a UUID is skipped; an orphan gives a `.pending` record with the file's creation date. `HistoryStoreTests`: a Delete whose file cannot be removed keeps its row. Pipeline: an adopted `.pending` row is retried at launch, lands in Recovered, and nothing is pasted (the existing retry tests show the style).
- Spike first (S, in `spikes/`, no paid call): write a FLAC with `AVAudioFile`, kill the writer process mid-file, and check what `AVAudioFile.length` reads, and whether OpenRouter's decoder would get valid FLAC. Apple says nothing on this. RFC 9639 says a STREAMINFO total of 0 "means the number of total samples is unknown", and "if the streaminfo metadata block contains incorrect or incomplete information, decoder behavior is left unspecified" (https://www.rfc-editor.org/rfc/rfc9639.html). If the file does not decode, recovery may need to re-write the frames into a new FLAC.
- Cost: launch only, after the hotkey tap starts: one folder listing and one query. Estimate a few ms per 1,000 files; measure. No idle work.
- Privacy: none new; the audio already is on disk, and the request goes to the chosen route as for any retry. Cost to the owner: a few cents per hour of recovered audio.

## 6. Build order

Files each item touches (N = new file):

| Item | Size | Files |
|---|---|---|
| 5.1 Cmd-F Dictionary | S | `App/Settings/SettingsWindow.swift`, `App/Settings/DictionaryPane.swift`, N `App/Settings/EntryEditor.swift`, `docs/testing/phase2-manual.md` |
| 5.2 #17 GeneralModel | S | `App/Settings/GeneralPane.swift` |
| 5.3 Fix from History | S | `App/FixLastDictation.swift`, `App/History/HistoryView.swift`, `App/History/HistoryModel.swift`, `App/History/HistoryWindow.swift`, `App/AppDelegate.swift` (wiring), `App/Snapshots.swift`, manual doc |
| 5.4 Orphan audio | S-M | spike in N `spikes/flac-kill/`; N `KotobaCore/Sources/KotobaCore/OrphanAudio.swift` + tests; `KotobaStorage/Sources/KotobaStorage/HistoryStore.swift` (delete order, id query) + tests; N `App/OrphanAudio.swift`; `App/AppDelegate.swift` (one launch call) |
| 2.2d Service | S | `project.yml` (Info.plist), N `App/DictionaryService.swift`, `KotobaCore/Sources/KotobaCore/PersonalDictionary.swift` (term check), `App/AppDelegate.swift` |
| 3 Rank and cap | S-M | N `KotobaCore/Sources/KotobaCore/TermRanking.swift`, N `TermHits.swift` + tests, `PersonalDictionary.swift`, `PipelineInterface.swift` (`request(for:)`), `DictationPipeline.swift` (`updateTermUse`), `KotobaStorage/Sources/KotobaStorage/DictionaryStore.swift` (`term_use`), `App/Settings/DictionaryModel.swift`, `App/Settings/DictionaryPane.swift` (pin, "not sent"), `App/SettingsController.swift` |
| 2.2b History mining | M | N `KotobaCore/Sources/KotobaCore/NearMissMiner.swift` + tests, `DictionaryStore.swift`, `App/SettingsController.swift` |
| 2.2c Wispr seed | S-M | `KotobaStorage/Sources/KotobaStorage/WisprFlowImport.swift`, `App/Settings/DictionaryModel.swift`, `App/Settings/DictionaryPane.swift` |
| 4 Context (C) | M-L | N `KotobaCore/Sources/KotobaCore/ContextTerms.swift` + tests, `PipelineInterface.swift` (port), `PipelineRecording.swift` (start at chord-down), `TranscriptDelivery.swift`, `Store.swift` (record field), `HistoryStore.swift` (column), N `App/SessionContext.swift`, `App/Settings/ModesPane.swift` or `GeneralPane.swift` (switch), `App/History/HistoryView.swift`, `App/AppDelegate.swift` |
| 1 Gap A shortcut | M | `App/HotkeyChords.swift`, `KotobaCore/Sources/KotobaCore/HotkeyClassifier.swift`, `App/HotkeyTap.swift`, `App/ChordRecorder.swift`, `App/Settings/GeneralPane.swift` |

Waves:
- Wave 1, after Insights lands (it owns `SettingsWindow.swift`, `SettingsController.swift`, `DictionaryStore.swift` and `Snapshots.swift` now). Four agents in parallel: 5.1, 5.2, 5.3, and 5.4 (spike first). Shared files: `App/AppDelegate.swift` (5.3 and 5.4 each add one call; the second agent rebases on the first) and `docs/testing/phase2-manual.md` (append rows only; each agent takes a row-number block: 5.1 from 400, 5.3 from 410, 5.4 from 420; update the numbers to the free ones at start).
- Wave 2: 3 (rank and cap) alone in the dictionary files, with 2.2d (service) in parallel (no shared file but `AppDelegate.swift`, one line). 2.2a (live readback check) runs any time; it is the owner's time.
- Wave 3: 2.2b and 2.2c in sequence (both edit `DictionaryStore.swift` and the Dictionary pane). Then 4 after the owner's privacy decision and the bench go; it needs 3's ranking. Gap A only if the owner asks, and after 5.2 (both edit `GeneralPane.swift`).

Notes:
- Migrations (`AGENTS.md`): `term_use` (3) is a new table in `dictionary.sqlite`; `context_terms` (4) is a new column in `dictations`. Per-app modes is not pushed yet. If its schema change is still unpushed when 4 starts, 4 changes nothing in that migration and adds its own step from the last pushed shape, or the lead pushes modes first.
- Line limits: `DictionaryPane.swift` 368, `App/Readback.swift` 393, `App/IndicatorPanel.swift` 395, `DictionaryStore.swift` 341, `HotkeyClassifier.swift` 320. An item that grows one of them past 350 moves a whole concern out first.
- Every item reports its measured cost (`AGENTS.md`, No patchwork): `make memory` for idle footprint, and the latency marks for anything near the stop.

## Unresolved questions

Owner decisions, each with a recommendation.

1. Context awareness (section 4): which option, and on or off by default? Recommendation: option C, off by default, only in Code mode, with the sent words shown in History. Never send screen text or selected text to the speech model.
2. May the bench in 4.4 run (about $0.15, about 10 minutes, the owner's clips through MAI via OpenRouter)? And the list-size bench in section 3 (about $0.50, about 15 minutes)? Recommendation: yes to both, before turning context on.
3. Orphan audio (5.4): transcribe orphans at once into Recovered (as a quit does), or only list them in History for a manual Retry? Recommendation: transcribe at once; it matches the quit rule and costs cents.
4. Pins in the Dictionary (section 3): add a star per term? Recommendation: yes, it is the owner's guard against ranking.
5. Wispr history seed (2.2c): read Wispr's `History` table once for word pairs? Recommendation: yes, as pending suggestions only, from a clone, with the text dropped after.
6. Paste Last and Copy Last shortcuts (section 1, gap A): wanted? Recommendation: not now; the menu covers it.
7. "Add to kotoba Dictionary" service (2.2d): wanted? Recommendation: yes; it is the cheapest way to learn in terminals.
8. Does Ghostty (and so cmux) support the macOS Services menu on selected text? UNCONFIRMED; the service is worth less without it. Check by hand once the service is built.
9. Does an `AVAudioFile` FLAC whose writer was killed decode? The spike in 5.4 answers it before the recovery is built.
