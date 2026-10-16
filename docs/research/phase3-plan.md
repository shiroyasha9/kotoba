# Phase 3: plan for the rest

Status: plan, 2026-10-16 10:35 IST. Agent `phase3-research`. Read-only on code: no source changed, no database opened, no paid API called. Inputs: `docs/spec.md` (stories 29-34, "Order after this round", the beyond-wispr bullets), `docs/research/beyond-wispr.md`, `auto-learning.md`, `ux-polish.md`, `per-app-modes.md`, and the code at `e1bb855` plus the working tree. Apple API facts come from the macOS 27 SDK headers and Apple's docs (sources in each section).

Done before this plan: History window, usage tracker, audio retention, per-app modes (local, not pushed), Insights (another agent finishes it now).

## Summary

- Ideas 2, 3 and 4 are already built (phase 2.6, commit `83d76c2`), with tests and manual rows. Section 1 lists what is left: the owner's manual test, and three small optional gaps.
- Story 32 is mostly built: readback after paste, "Fix Last Dictation…", Suggestions. Left: the live readback check on the owner's apps, history mining, the one-time Wispr history seed, and an "Add to kotoba Dictionary" system service. Section 2.
- Idea 5 (rank and cap terms) is a precondition of idea 1, because context terms share the route's 100-term cap. Build it first. Below the cap it changes nothing, so the risk "it drops a needed term" applies only past 100 terms. Section 3.
- Story 34 and idea 1 (context) have their own research in `docs/research/context-awareness.md`; section 4 here gives only its build-order touch points.
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

Its own research: `docs/research/context-awareness.md` (agent `context-research`). That file holds the options, the privacy decision, the design and the bench. This plan keeps only what the build order needs.

- Depends on section 3: context terms share the route's 100-term cap, so they go through `TermRanking` (context terms first, within the limit). Build section 3 first.
- Likely touch points: a new port in `KotobaCore/Sources/KotobaCore/PipelineInterface.swift` (`DictationPipeline.Ports`), `PipelineRecording.swift` (start the read at chord-down), `TranscriptDelivery.swift` and `Settings.request(for:)` (take the terms only if ready, never wait), `Store.swift` and `KotobaStorage/Sources/KotobaStorage/HistoryStore.swift` (if the record keeps the sent terms: a new column), a new pure extractor in KotobaCore and a new App adapter, a switch in `App/Settings/ModesPane.swift` or `GeneralPane.swift`, and `App/History/HistoryView.swift` (if History shows the sent terms). `context-awareness.md` is the authority on these.

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
| 4 Context | see `context-awareness.md` | Likely: `PipelineInterface.swift`, `PipelineRecording.swift`, `TranscriptDelivery.swift`, `Store.swift`, `HistoryStore.swift`, `ModesPane.swift` or `GeneralPane.swift`, `HistoryView.swift`, `AppDelegate.swift`, plus new files |
| 1 Gap A shortcut | M | `App/HotkeyChords.swift`, `KotobaCore/Sources/KotobaCore/HotkeyClassifier.swift`, `App/HotkeyTap.swift`, `App/ChordRecorder.swift`, `App/Settings/GeneralPane.swift` |

Waves:
- Wave 1, after Insights lands (it owns `SettingsWindow.swift`, `SettingsController.swift`, `DictionaryStore.swift` and `Snapshots.swift` now). Four agents in parallel: 5.1, 5.2, 5.3, and 5.4 (spike first). Shared files: `App/AppDelegate.swift` (5.3 and 5.4 each add one call; the second agent rebases on the first) and `docs/testing/phase2-manual.md` (append rows only; each agent takes a row-number block: 5.1 from 400, 5.3 from 410, 5.4 from 420; update the numbers to the free ones at start).
- Wave 2: 3 (rank and cap) alone in the dictionary files, with 2.2d (service) in parallel (no shared file but `AppDelegate.swift`, one line). 2.2a (live readback check) runs any time; it is the owner's time.
- Wave 3: 2.2b and 2.2c in sequence (both edit `DictionaryStore.swift` and the Dictionary pane). Then 4, as `context-awareness.md` decides; it needs 3's ranking. Gap A only if the owner asks, and after 5.2 (both edit `GeneralPane.swift`).

Notes:
- Migrations (`AGENTS.md`): `term_use` (3) is a new table in `dictionary.sqlite`; if 4 keeps the sent terms, that is a new column in `dictations`. Per-app modes is not pushed yet. If its schema change is still unpushed when 4 starts, 4 changes nothing in that migration and adds its own step from the last pushed shape, or the lead pushes modes first.
- Line limits: `DictionaryPane.swift` 368, `App/Readback.swift` 393, `App/IndicatorPanel.swift` 395, `DictionaryStore.swift` 341, `HotkeyClassifier.swift` 320. An item that grows one of them past 350 moves a whole concern out first.
- Every item reports its measured cost (`AGENTS.md`, No patchwork): `make memory` for idle footprint, and the latency marks for anything near the stop.

## Unresolved questions

Owner decisions, each with a recommendation.

1. Context awareness: see the questions in `docs/research/context-awareness.md`.
2. May the list-size bench in section 3 run (25, 50 and 100 terms on kotoba-bench-v1 through MAI via OpenRouter, about $0.50, about 15 minutes)? Recommendation: yes, before the cap changes from 100.
3. Orphan audio (5.4): transcribe orphans at once into Recovered (as a quit does), or only list them in History for a manual Retry? Recommendation: transcribe at once; it matches the quit rule and costs cents.
4. Pins in the Dictionary (section 3): add a star per term? Recommendation: yes, it is the owner's guard against ranking.
5. Wispr history seed (2.2c): read Wispr's `History` table once for word pairs? Recommendation: yes, as pending suggestions only, from a clone, with the text dropped after.
6. Paste Last and Copy Last shortcuts (section 1, gap A): wanted? Recommendation: not now; the menu covers it.
7. "Add to kotoba Dictionary" service (2.2d): wanted? Recommendation: yes; it is the cheapest way to learn in terminals.
8. Does Ghostty (and so cmux) support the macOS Services menu on selected text? UNCONFIRMED; the service is worth less without it. Check by hand once the service is built.
9. Does an `AVAudioFile` FLAC whose writer was killed decode? The spike in 5.4 answers it before the recovery is built.
