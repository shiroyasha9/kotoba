# Auto-learning dictionary entries

Status: research, 2026-10-15 23:31 IST. Owner ask: "look into ways to auto detect dictionary / word improvements". Spec story 32 ("notice when I edit pasted text and suggest a dictionary entry"), with story 30 (History) and story 34 (context awareness, off by default) as neighbours. Read-only: no kotoba source changed, no kotoba database opened, no paid API called. Private names, places and sentences from the owner's data are replaced with synthetic examples of the same shape (`Taviya`, `Marlow`, `#team-ops`); the original stays outside the repo.

## Readback (phase 2.6)

Status: built, 2026-10-16 01:10 IST (owner round 2026-10-16: strong candidates are added at once). Sources: the macOS SDK header `HIServices/AXUIElement.h` (Xcode, macOS 27 SDK), Apple's pages for `kAXSecureTextFieldSubrole`, `kAXStringForRangeParameterizedAttribute`, `kAXNumberOfCharactersAttribute` and `AXObserverAddNotification` (https://developer.apple.com/documentation/applicationservices), https://www.electronjs.org/docs/latest/tutorial/accessibility, Electron's `shell/browser/mac/electron_application.mm`, Rectangle's `AccessibilityElement.swift`. Not measured live yet: a live run needs the lead's go.

How it works (code: `KotobaCore/Sources/KotobaCore/EditReadback.swift`, `App/Readback.swift`):
- Start, event-driven: after Cmd-V, the pipeline gives the pasted text to `EditReadback`. The App adapter reads `kAXFocusedUIElementAttribute` of the frontmost app. It continues only when the field is not `AXSecureTextField`, `IsSecureEventInputEnabled()` is false, and the field has `kAXNumberOfCharactersAttribute` and `kAXSelectedTextRangeAttribute`. Then one `AXObserver` for the app's pid gets `kAXValueChangedNotification` and `kAXUIElementDestroyedNotification` on the field and `kAXFocusedUIElementChangedNotification` on the app element. Its run loop source goes on the run loop of a thread made for the session (the header says to add the source "to the run loop on which you want the callback executed", `AXNotificationConstants.h`). Every AX call of the session runs on that thread, so no AX object crosses threads and a hung app never blocks the main thread. The thread exits when the session ends. With "Learn from my edits" off (Dictionary pane, on by default), kotoba makes no thread and no observer. `NSWorkspace.didActivateApplicationNotification` reports an app change. There is no polling.
- Read: after a value change and then 500 ms without a change (`Settings.settle`), at the latest 2 s after the first change not read yet (`Settings.maxWait`, for a terminal that keeps redrawing), and once more when focus leaves with a change not read yet. One timer re-arms itself while changes come; there is no timer per change. An edit is "settled" only when the field did not change after its read, except for the one change that removed the text (a sent message); the time limit does not read. Only a settled edit adds words at once; an unsettled one can hold half a word, so its words go to Suggestions. Turning "Learn from my edits" off ends an open session with no edit. One read is 3 AX calls: the character count, the selected range, and `kAXStringForRangeParameterizedAttribute` for `pasted.utf16.count + 64` UTF-16 units on each side of the insertion point. A field without the ranged read is read whole (`kAXValueAttribute`) only up to 20,000 units. Each element has a messaging timeout of 0.25 s (`AXUIElementSetMessagingTimeout`; the header says it applies to that object only).
- Pasted span: `PastedSpan.find` aligns the pasted words with the read text. The start and the end are free; each added or removed word costs 1; a changed word costs 1, or 0.5 when the two words share at least half of their letters (`Mellow` -> `Marlow`); words compare on their letters only. So an edited first or last word stays in the span, and an unrelated word next to the paste stays out. No anchors are needed, because the first read can come after the first edit. When more than max(1, 50% of the pasted words) changed, the text is gone. Eval on the 216 Wispr edit pairs, each put between other field text: the same 14 candidates (9 strong) as the direct diff, and no span lost (`eval-readback/` and `eval-readback-output.txt` in the runbooks folder). Cost in a Debug build, off the main thread: on those pairs (211 of 200 words or fewer) p50 0.17 ms, p90 0.54 ms, max 5.0 ms; 200 random words in a 600-word read, about 16 ms.
- End: 60 s after the paste; focus leaves the field or the app; the pasted text is gone (Slack and terminal prompts empty on Return); or the next dictation or paste starts (no read then). The end removes the notifications and the run loop source and releases the field. Then `CorrectionDetector` runs once on the last span. Its thresholds did not change (eval on the Wispr pairs: strong precision 9 of 9, recall 9 of 14). A strong candidate is added at once with Undo on the pill; a weak one goes to Suggestions. When the next dictation ended the session, the pill is not free for Undo, so strong candidates go to Suggestions too (`ReadbackChoice`).

Limits by app:
- Electron (Slack, Cursor, VS Code): Electron builds its tree only when an assistive app sets `AXManualAccessibility` on the app element. kotoba sets it once per process, only when the focused element is not readable text. The tree builds after the call, so the first paste into such an app after its launch may not be read. Cost: Electron keeps its full tree for the rest of that app's life (CPU and memory in that app, not in kotoba).
- Chromium browsers: kotoba does not set `AXEnhancedUserInterface`. Electron treats it like `AXManualAccessibility`, but window managers turn it off around each window move (Rectangle), and screen-reader mode costs the browser more. Chromium turns on basic mode when a client reads its attributes; whether the owner's browsers (Dia, Helium, Zen) then expose the field: UNCONFIRMED.
- Terminals (Terminal.app, Ghostty, cmux): the field is the scrollback, or there is none. The bounded read keeps the cost small (Ghostty: a full read took 3 s, ghostty#9932). A TUI prompt empties on Return, so the span is often gone; then nothing is learned and "Fix Last Dictation…" stays the way.
- Secure fields: never read. The subrole and Secure Input are checked when the field opens; Secure Input is checked again before each read; focus moving to another field ends the session.
- Privacy: the field text stays in memory (the session and one `Edit` value) and is never logged; the signposts ("readback open", "readback read") carry no text.
- Permission: the observer uses the Accessibility grant that the event tap and Cmd-V already need; there is no new prompt. No Apple page says this in words: UNCONFIRMED.
- Cost per paste: one thread start, then opening is 7 AX calls (9 when Electron is woken); each read is 3; the end is 3 removals. They run on the session thread, each bounded by the 0.25 s timeout; the main thread only reads the frontmost app (no IPC) and gets one stream yield per app change. The pipeline adds one actor hop after `pasteSent` and one after capture starts; nothing before Cmd-V. Idle cost: no thread, no observer, no timer and no task between sessions; `EditReadback` itself is one actor and one stream, made at launch. No new framework: ApplicationServices and Carbon are already loaded for the paste.

## Summary

- Edit readback alone gives little signal on the owner's machine. Wispr Flow watches the text box after each paste. Over 1,146 dictations (2026-05-14 to 2026-10-15) it saw word edits in 42 dictations and learned 5 entries; the owner deleted 1 of them. In cmux, the owner's main app (749 dictations), Wispr got no edited text for 588 dictations (79%): the prompt was submitted and cleared, or the pasted text was not found.
- The owner's edits that are real dictionary material are mostly names and identifiers. In a hand label of the 45 word replacements in Wispr's history, 14 (31%) are dictionary material (for example `embra`, `Zentyl`, `order_id`, `Marlow`). 18 are rewrites (word choice), 6 are mis-hearings of common words, 5 are formatting, 2 are numbers. Wispr's documented filter skips code symbols and IDs, so it missed most of the identifiers.
- Provider signals are weak. MAI returns no word confidence. xAI documents `words[].confidence`, but Grok is not the default route.
- Recommended first build: a pure `CorrectionDetector` in KotobaCore, a Suggestions list in DictionaryStore and the Dictionary pane, and a "Fix Last Dictation..." menu item. This needs no new permission and works in terminals. Then add Accessibility readback as a second detection source after a spike on the owner's apps. Then add history mining after the History window. Keep context sources (Contacts, repositories) for later, off by default.

## 1. How Wispr Flow learns (evidence from the owner's database)

Source: an APFS clone (`cp -c`) of `~/Library/Application Support/Wispr Flow/flow.sqlite`, taken 2026-10-15 23:19 IST into this session's scratch folder, opened with `immutable=1`. There was no `-wal` file at clone time, so the clone holds every write. The clone was deleted after the queries. Every query is in the appendix.

### 1.1 Schema

- `Dictionary` (`id`, `phrase`, `replacement`, `teamDictionaryId`, `lastUsed`, `frequencyUsed`, `remoteFrequencyUsed`, `manualEntry`, `createdAt`, `modifiedAt`, `isDeleted`, `source`, `isSnippet`, `observedSource`, `isStarred`, `replacementHtml`; unique on `phrase` + `teamDictionaryId`). A learned entry has `source = 'user_edits'`, `phrase` = what the owner typed, `observedSource` = what Wispr had pasted. Each entry counts its use (`frequencyUsed`, `lastUsed`).
- `History` holds the observation of each paste: `pastedText`, `formattedText`, `asrText`, `editedText`, `editedTextUnbounded`, `textboxContents`, `axText`, `axHTML`, `userEditMetaData` (JSON: `word_edits`, `punctuation_edits`, each an edit-op string such as `MMMSMMD`), `editDistanceToDictated`, `contentObservationEndReason`, `contentObservationEndLastKeystroke`, `numWordsCorrected`, `numDictionaryReplacements`, `averageLogProb`, and `additionalContext` (JSON: `ax_context`, `ocr_context`, `dictionary_context`, `textbox_contents`, `file_names`, `variable_names`, user name).
- `TranscriptCorrections` (`originalText`, `editedText`) belongs to meetings, not to dictation. `Polish`, `UserVoicePreferences` and `UserContext` hold style data, not vocabulary.

### 1.2 What the data shows

| Fact | Value |
|---|---|
| Dictations in History | 1,146 (101,246 words) |
| Dictations with an observed `editedText` | 271 (24%) |
| Dictations with at least one word edit (`word_edits` not all `M`) | 42 |
| Word edit ops in those | 40 substitute, 29 insert, 52 delete, 9,675 match |
| Dictionary entries, live | 38 (26 personal, 12 team); 2 with a replacement |
| Learned entries (`source = 'user_edits'`) | 5 in 5 months; 1 deleted by the owner (`isDeleted = 1`, deleted 5 days later) |
| Time from dictation to learned entry | 27 s to 136 s (after the observation ends) |
| Evidence needed | One edit. Each learned entry was created from a single dictation |
| Entries sent per dictation (`dictionary_context`) | about 21 of 38 on average: Wispr picks a subset per dictation |

Learned entries (word-level only):

| phrase (typed) | observedSource (pasted) | note |
|---|---|---|
| Taviya | Tavia | name |
| Codex | code ex | multi-word heard text |
| Marlow | Mellow | place; heard text is a common word |
| Orlena | Orlina | name |
| Dravik | (none) | term only; the owner deleted it |

How the observation ends (`contentObservationEndReason`, all apps): `textbox_emptied` 461, empty 286, `dictated_text_not_found` 157, `anchor_mismatch_transcript_intact` 107, `trailing_newline_added` 60, `next_paste_started` 38, `anchor_mismatch` 28, `observation_window_elapsed` 8, `next_dictation_started` 1. The last keystroke is recorded too: `return` 134, `backspace` 19, `esc` 12, `delete_line` 7, `cmd_enter` 4. So Wispr watches keystrokes and the text box, anchors the pasted text by its neighbours, and stops on submit, newline, the next paste or dictation, focus loss or a time limit.

By app:

| App | Dictations | With editedText | Main end reasons |
|---|---|---|---|
| cmux | 749 | 129 | `textbox_emptied` 441 (0 edited), `dictated_text_not_found` 147 (0 edited), `anchor_mismatch_transcript_intact` 106 |
| Ghostty | 80 | 16 | (none recorded) |
| A second AI editor app | 47 | 47 | `trailing_newline_added` 26, `next_paste_started` 10 |
| Cursor | 20 | 16 | `trailing_newline_added` 4 |

In a terminal TUI (Claude Code, Codex in cmux) the prompt box empties on Return, and Wispr then keeps no edited text. Browser and editor fields keep their text, and readback works there.

### 1.3 What the owner edits

A word-level alignment (Python `difflib` on whitespace tokens, pasted text vs `editedText`) of the 216 dictations whose edited text differs: 172 differ only in whitespace or newlines. 44 have word changes: 45 replacements, 11 deletions, 8 insertions. Hand label of the 45 replacements:

| Kind | Count | Examples (word-level) |
|---|---|---|
| Dictionary material: name, place, product, identifier | 14 | `order ID` -> `order_id`, `ember` -> `embra`, `ZenTail` -> `Zentyl`, `Tangle` -> `retangle`, `hashtag team ops` -> `#team-ops`, `Mellow` -> `Marlow` |
| Rewrite (word choice, not a mis-hearing) | 18 | `drafting` -> `editing`, `renamed` -> `removed`, `server` -> `host` |
| Mis-hearing of a common word | 6 | `Add it` -> `Audit`, `wait` -> `weight` |
| Formatting or punctuation | 5 | HTML list -> dashes, `ten.` -> `ten?` |
| Number | 2 | `2.5` -> `25` |

Deletions are false starts and filler; insertions are list numbers and added words. Neither is dictionary material.

Findings:
- Wispr learned 5 of the 14 dictionary edits (4 kept). It missed identifiers such as `embra`, `Zentyl`, `retangle`, `order_id`, `#team-ops`. Wispr's docs say it skips "paths, URLs, code symbols, IDs, numbers, dates" (https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary). For a developer, those are the useful entries.
- A naive "learn every replacement" has about 31% precision on this data. A filter must reject rewrites.
- One rewrite holds a real name (`Tavia.` -> `Orlena for the meeting.`). A size filter (1 token vs 4) must reject it, or it teaches a wrong rule.
- A rule from a common word is harmful: `ember` -> `embra` would break "ember glow", and `Mellow` -> `Marlow` would break "mellow". kotoba's Wispr import makes such rules today (`KotobaStorage/Sources/KotobaStorage/WisprFlowImport.swift:87-93`). The term alone (sent as a keyterm) is the safer form.
- Volume: 14 useful edits in 5 months, about 3 a month. Suggest-and-confirm costs the owner little. Edit readback alone grows the dictionary slowly.

### 1.4 Other Wispr findings

- `additionalContext.variable_names` and `file_names` are empty in all 471 rows that have them. Wispr's IDE identifier harvest gave nothing in the owner's setup.
- `averageLogProb` is stored (984 rows, mean 1.02, range 0.40 to 11.1; not a log-probability in the usual sense). Wispr does not use it for the dictionary as far as the data shows.
- Follow-up for the lead: `docs/spec.md:9` says "about 10,000 manual fixes over about 73,000 words". That number matches `History.numWordsCorrected`, which counts Wispr's formatter changes, not the owner's edits: rows where `asrText = formattedText` have 11 corrected words in total, and rows where they differ have 12,469. The owner's own word edits are in 42 dictations.

## 2. What other apps do

| App | Mechanism | Add or suggest | Filters | Problems |
|---|---|---|---|---|
| Wispr Flow | Watches the text box after paste; a changed spelling is learned | Auto-add; batched notification | Skips paths, URLs, code symbols, IDs, numbers, dates, common words, famous names; a deleted word never returns; 60 characters max | See 1.3 (misses identifiers; misses terminal edits) |
| VoiceInk (GPL, ideas only) | AX read 120 ms after Cmd-V; `AXManualAccessibility` for Electron and Chromium; finalizes on focus change (250 ms grace), 60 s, or next recording; 16-character anchors around the paste; segment diff; an LLM reviews each change ("phonetic evidence", "no semantic rewrite") | User choice: "Immediately" (with Undo) or "Manually" (review panel) | Diff: max 256 characters, 24 segments; reviewer rejects case-only changes | #985 open: review loses corrections, "Immediately" learns nothing; #988: maintainer says it "needs more polishing" |
| TypeWhisper (GPL, ideas only) | AX baseline, then a read each second for up to 30 s; stops on Return, Tab, focus or app change; common prefix and suffix, widened to tokens | Auto-add as a replacement rule | Exactly one changed token, same token count; rejects case-only, punctuation-only, number changes; optional repeat count (2, 3 or 5 in 30 days); skips secure fields | #1168: 0 entries in 4,168 dictations (Electron gave no baseline); #1459: a user undid about 95% of learned entries; #1020 asks for "Correct Last Dictation" |
| Willow Voice | Saved repeated unknown terms (2025-06); made "much less aggressive" with "a local cache that filters for intent" (2025-08); "post-insertion tracking" on by default | Auto-add with "learning notifications"; iOS shows an "Auto Learning" section | Not published | The 2025-08 change suggests too many bad entries |
| Dragon | Correction menu ("Correct That", "Add That to Vocabulary"); "Learn from documents" and sent email scan for new words and offer them | Explicit user action | User picks | - |
| Apple Dictation | Ambiguous words underlined in blue; click to pick an alternative; contact names may be sent as context | Not documented as learning | - | - |
| FreeFlow (MIT) | No edit learning; a menu action adds the copied words to the vocabulary | Explicit | Skips duplicates | - |
| Hex (MIT), Superwhisper, MacWhisper, Aqua Voice | No learning; manual vocabulary and replacements. Superwhisper warns "too many words can confuse the transcription model". One Aqua user has an LLM review logs weekly, then adds entries by hand | - | - | - |

Sources: https://github.com/Beingpax/VoiceInk/tree/main/VoiceInk/Features/Dictionary/AutoLearn, https://github.com/Beingpax/VoiceInk/issues/985, https://github.com/TypeWhisper/typewhisper-mac (`TargetAppCorrectionLearningService.swift`, `TextDiffService.swift`), https://github.com/TypeWhisper/typewhisper-mac/issues/1168, https://github.com/TypeWhisper/typewhisper-mac/pull/1459, https://github.com/TypeWhisper/typewhisper-mac/issues/1020, https://wisprflow.ai/data-controls, https://willowvoice.featurebase.app/changelog/qol-changes, https://www.nuance.com/products/help/dragon152/dragon-for-pc/enx/Home/Content/DialogBoxes/correction_dialog_items.htm, https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac, https://github.com/zachlatta/freeflow (`Sources/AppState+AddVocabularyButton.swift`), https://superwhisper.com/docs/get-started/interface-vocabulary.

Lessons:
- Every readback app had trouble: low recall in Electron and terminals, and low precision (TypeWhisper users undid most entries; Willow made learning less aggressive).
- Too many terms hurt accuracy. Wispr's Canto report: after RL, the model took a phonetically similar wrong dictionary term "nearly five times as often" (`docs/research/dictation-apps.md`, section 2.3). So kotoba must not grow the keyterm list without limits.
- Dragon and FreeFlow show the explicit path: the user says what to learn, and precision is near 100%.

## 3. Detection sources for kotoba

The hot path (key-down to Cmd-V sent) does not change for any source below. Learning starts after the `pasteSent` mark, off the pipeline actor.

### 3a. Accessibility readback after paste

How:
- After Cmd-V, read the focused element (`AXFocusedUIElement`) once the paste lands (about 120-200 ms, or on the first value change). Keep the pasted range and 16-character anchors before and after it.
- Read again 300 ms after the last key-down while the observation is open. The tap already receives key-down events (`App/HotkeyTap.swift:49-50`), so this costs a constant-time hand-off in the callback. Also read on focus or app change. Never read inside the tap callback (CODING_STANDARDS: real-time callbacks).
- End the observation on Return, Cmd-Return or Tab, on a focus or app change, on the next dictation or paste, or after 60 s. Use the last snapshot before the end. Wispr's data shows why: in a TUI, the text is gone after Return.
- Align: find the anchors in the last snapshot; when they are gone, search for the pasted text by local alignment. Then diff tokens (Myers or LCS) and keep replacement hunks.
- Filter: see section 4.3.

Behaviour by app (agent research, sources in section 5):

| Field type | Readable | Notes |
|---|---|---|
| Native AppKit | Yes | `AXValue`, `AXSelectedTextRange` |
| Chromium browsers (Chrome, Dia, Helium) | Yes, after AX is woken | Reading the app role turns on basic mode; `AXEnhancedUserInterface` turns on full mode after about 2 s and can break window managers. Arc and Dia: UNCONFIRMED |
| Electron (Slack, Cursor, VS Code) | Yes, with `AXManualAccessibility` set on the app | VS Code and Cursor expose the editor by pages (`accessibilityPageSize`); TypeWhisper users got no baseline in Electron (#1168) |
| Firefox-based (Zen) | Yes, after AX is woken | No `AXManualAccessibility` handler |
| Ghostty (and cmux, reported as Ghostty-based) | Partly | `AXValue` is the whole scrollback; one 700K-character read took 3 s (ghostty#9932). Read a bounded range (`AXStringForRange`) near the insertion point, or skip. Wispr kept no edited text in 79% of cmux dictations |
| Terminal.app, iTerm2 | Partly | Terminal.app returns the visible range only |
| Secure fields | No | Skip role `AXSecureTextField` and skip when `IsSecureEventInputEnabled()` is true |

- Feasibility: medium. It needs per-app handling and a spike on the owner's apps.
- Accuracy risk: high without filters (31% precision for "every replacement", section 1.3). Medium with filters.
- Privacy: the snapshots hold field text, which may include other people's messages. Keep snapshots in memory only, drop them when the observation ends, never log them, store only the word pair of a candidate. Wispr does the same ("captured text is cleared when the dictation ends").
- Cost: no money. AX reads take 10-20 ms in most apps; set `AXUIElementSetMessagingTimeout` to about 0.25 s and cap reads at about 100,000 UTF-16 units (VoiceInk uses 0.1-0.2 s and 100,000).
- Latency: none on the hot path. A slow AX target (Ghostty) blocks only the learning task, under the timeout.
- Permission: none new. kotoba already needs Accessibility for the active event tap and Cmd-V (`App/AppDelegate.swift:169-171`); AX reads need only `AXIsProcessTrusted`.

### 3b. History mining

What:
- Repeated near-misses: for each dictionary term, find n-grams in past transcripts that are close in sound or spelling (normalized edit distance on letters, or a phonetic key) and appear at least 3 times. Suggest a rule from that n-gram to the term. This finds new wrong spellings of known terms, not new terms.
- Cleaner diffs: for cleanup dictations, compare `transcript` with `cleaned_text` (`KotobaStorage/Sources/KotobaStorage/HistoryStore.swift:20-24`). Where the cleaner wrote a keyterm that the raw text did not have, record the raw span as a candidate. kotoba-bench-v1 showed the cleanup LLMs recover more terms than the raw transcript, though their WER is worse (`docs/progress.md`, Benchmark). Note: `transcript` is stored after the replacements (`KotobaCore/Sources/KotobaCore/TranscriptionSteps.swift:15-21`); the provider's raw text is not stored.
- Wispr seed (one time): run the same detector over Wispr's `History` (pasted text vs `editedText`, 44 dictations with word changes). By hand, about 14 candidates, of which Wispr learned only 5.
- Feasibility: high for the detector part; needs the History window (story 30) for a natural place to show results. Accuracy risk: low with the 3-repeat threshold. Privacy: local only. Cost and latency: none; runs at idle or on demand.

### 3c. Provider signals

| Route | Word confidence | n-best | Notes |
|---|---|---|---|
| MAI-Transcribe-2 (Azure direct) | No | No | `phrases[].confidence` exists, but for LLM Speech enhanced mode "`confidence` isn't available and is always 0"; `words[]` has text and timing only (https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe?view=rest-speechtotext-2025-10-15, https://learn.microsoft.com/en-us/azure/ai-services/speech-service/llm-speech) |
| OpenRouter | Maybe | No | `verbose_json` adds `words` with optional confidence when the routed provider supports it; for `microsoft/mai-transcribe-2` UNCONFIRMED (https://openrouter.ai/docs/guides/overview/multimodal/stt.md) |
| xAI direct | Yes | No | `words[].confidence`, "0.0-1.0, entropy-based. Omitted when 0" (https://docs.x.ai/developers/rest-api-reference/inference/voice.md) |

Today's parsers keep only the text and duration (`KotobaProviders/Sources/KotobaProviders/AzureProvider.swift:86-93`, `OpenRouterProvider.swift:121-129`, `XAIProvider.swift:69-73`). Use: on the Grok route, low-confidence words could be highlighted in "Fix Last Dictation". Not a detection source on its own, and not on the default route. A larger response body may add decode time on the hot path; measure before use.

### 3d. Explicit user action: "Fix Last Dictation..."

- A menu item (and later a History row action, story 30) opens a small window with the last pasted text in an editable field. The owner fixes the words and clicks Learn. The detector diffs the two texts and shows the candidates with checkboxes (strong candidates pre-checked). Add applies them.
- Variant (FreeFlow): "Add Selection to Dictionary" reads the selected text in any app (`kAXSelectedTextAttribute`) and adds it as a term.
- Feasibility: high. Accuracy risk: low (the owner states intent; rewrites still go through the filter, then the owner unchecks what is wrong). Privacy: kotoba's own text only. Cost and latency: none. Permission: none new.
- It works in terminals, where readback fails. Dragon, TypeWhisper #1020 and FreeFlow point the same way.
- A new window with a text field needs a manual test row for Cmd-V and Cmd-A (CODING_STANDARDS, Windows and text entry).

### 3e. Context sources

| Source | Value | Privacy and permission |
|---|---|---|
| Contacts names | About 5 of the 14 dictionary edits were names of people or places | New TCC permission (Contacts). Names would go to the provider as keyterms |
| Identifiers in the current repo (package names, file names, exported symbols) | High for prompts to coding agents; Claude Code's `/voice` adds project and branch names (`docs/research/dictation-apps.md`, 1.5) | No TCC for `~/Coding`; but identifiers leave the Mac as keyterms. Which repo is "current" is hard to know from a terminal |
| Frontmost window text (AX) | Wispr's `ax_context` holds 2-11 items per dictation | Story 34: off by default |

Use context as evidence for the detector (a corrected word that is a contact name or a repo identifier is a strong candidate), not as a direct keyterm source. Keep it off by default (story 34) and build it last.

## 4. Recommendation

### 4.1 Build order

1. `CorrectionDetector` (pure, KotobaCore), the Suggestions table and section, and "Fix Last Dictation...". No new permission; works in every app; precise. Seed it once from Wispr's history edits (owner decision, Unresolved question 4).
2. Readback spike (1-2 hours, no code kept): measure AX read time, readability and anchor survival in cmux, Ghostty, Cursor, a second AI editor app, Dia, Zen and Slack. Build the readback source only for the apps that pass.
3. `EditObservation` (pure state machine, KotobaCore) and an App adapter `AXFocusedTextReader` behind a port. It feeds the same detector.
4. History mining (near-misses, cleaner diffs) with the History window.
5. Context sources, off by default.

### 4.2 How a suggestion reaches the owner

- Suggest and confirm for readback and history candidates. Explicit fixes add what the owner checks.
- Show suggestions in a "Suggestions" section at the top of the Dictionary pane (heard -> corrected, the app, the count, Add and Dismiss per row, Add All).
- Add a menu item "N Word Suggestions..." when N > 0, which opens the pane. No indicator change: the indicator belongs to the dictation, and a learning note can collide with the next dictation.
- Optional later: auto-add a candidate seen 2 or more times, with an Undo item in the menu.

### 4.3 Keeping the dictionary clean

Filters in the detector (from section 1.3 and TypeWhisper's rules):
- Ignore whitespace-only changes, pure insertions and pure deletions.
- Keep only small hunks: at most 4 tokens on each side, and token counts within a factor of 2 (rejects `Tavia.` -> `Orlena for the meeting.`).
- Drop the observation when the pasted span changed by more than about 40% (a rewrite, not a fix).
- Reject punctuation-only and number-to-number changes. Strip Markdown backticks before comparing.
- Need sound or spelling similarity between the heard and the corrected text (normalized edit distance on letters, spaces and `_` removed, or a phonetic key).
- Need a "rare" corrected side: at least one token with code shape (internal capitals, `_`, `#`, `-`, digits mixed with letters, all-caps acronym) or a token that the spell checker does not know. Case-only changes pass when the result has code shape (`github` -> `GitHub`).
- Strong candidate (code shape or unknown word): suggest at count 1. Weak candidate (both sides are known words, for example `Add it` -> `Audit`): suggest at count 2 within 30 days.
- Propose a rule only when the heard text is not a common word or phrase. Otherwise propose the term only (`ember` -> `embra` becomes the term `embra`).
- Skip candidates already in the dictionary and candidates the owner dismissed (Wispr: a deleted word never returns).

Limits:
- At most 20 pending suggestions; a pending suggestion expires after 30 days.
- The keyterm list stays at 100 (`KotobaCore/Sources/KotobaCore/PersonalDictionary.swift:6-8`). When learned terms push it over, rank by recent use (Wispr tracks `frequencyUsed` and `lastUsed`, and sends about 21 terms per dictation).
- Deleting an entry that came from a suggestion marks the suggestion dismissed.

Evaluation: before turning readback on, run the detector over the Wispr pairs from section 1.3 in the runbooks folder (private text stays out of git) and report precision and recall against the hand labels. Target: precision 80% or more (Wispr's kept rate was 4 of 5).

### 4.4 Data model

`DictionaryStore` (`KotobaStorage/Sources/KotobaStorage/DictionaryStore.swift:7-21`) rewrites `dictionary_terms` and `replacement_rules` on each save, so provenance goes in a new table that the save does not touch:

```sql
CREATE TABLE IF NOT EXISTS dictionary_suggestions (
    id TEXT PRIMARY KEY,
    heard TEXT NOT NULL,          -- what kotoba pasted; empty for a term-only suggestion
    corrected TEXT NOT NULL,      -- what the owner wrote
    proposes TEXT NOT NULL,       -- 'term' or 'termAndRule'
    origin TEXT NOT NULL,         -- 'fix', 'edit', 'history', 'wispr'
    app_bundle_id TEXT,
    evidence INTEGER NOT NULL,    -- times seen
    first_seen_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    status TEXT NOT NULL          -- 'pending', 'added', 'dismissed'
);
CREATE UNIQUE INDEX IF NOT EXISTS dictionary_suggestions_pair
    ON dictionary_suggestions (lower(heard), lower(corrected));
```

Only the word pair is stored, never the field text. Usage counts for ranking (term hits per dictation) can come later in a separate table keyed by the lowercased term.

### 4.5 Test seam

- `CorrectionDetector` (KotobaCore, pure): `candidates(pasted: String, observed: String, dictionary: PersonalDictionary, dismissed: Set<...>, isKnownWord: (String) -> Bool) -> [DictionarySuggestion]`. The App passes `isKnownWord` from `NSSpellChecker` (AppKit is already loaded; KotobaCore may not import it). Table tests in `CorrectionDetectorTests.swift` with synthetic cases: `versel` -> `Vercel` (term and rule), `order ID` -> `order_id` (rule), `ember` -> `embra` (term only), `drafting` -> `editing` (none), a long rewrite (none), a pure deletion (none), `2.5` -> `25` (none), `ten.` -> `ten?` (none), `github` -> `GitHub` (term), an entry already in the dictionary (none), a dismissed pair (none), and a multi-hunk edit with one valid hunk.
- `EditObservation` (KotobaCore, pure state machine): events in (pasted, snapshot, key-down kind, focus change, next dictation, clock tick on `PipelineClock`), decision out (read now, finalize with the last snapshot, abandon). Tested with `ManualClock`.
- The pipeline hands each pasted dictation (id, pasted text, frontmost app) to the learner through an `AsyncStream` after `store.saveOrLog`, so nothing waits on it.
- Ports: `FocusedTextReader` (App: `AXFocusedTextReader`), with a fake for tests.

### 4.6 Permissions and gates

- No new TCC permission for steps 1-4. Accessibility is already required. Contacts (step 5) would add one; the owner clicks Allow.
- Hot path: no added work before Cmd-V. The pipeline change is one stream yield after the save; report its cost with `make latency`.
- Memory: no new framework at launch. Measure `NSSpellChecker` and the AX observer with `footprint` when built.

## 5. Sources not cited above

- AX and Electron: https://electronjs.org/docs/latest/tutorial/accessibility, https://code.visualstudio.com/docs/configure/accessibility/accessibility
- Chromium AX modes: https://chromium.googlesource.com/chromium/src/+/main/chrome/browser/chrome_browser_application_mac.mm
- Firefox AX: https://github.com/mozilla-firefox/firefox/blob/main/accessible/mac/Platform.mm
- Ghostty AX read cost: https://github.com/ghostty-org/ghostty/issues/9932
- `AXEnhancedUserInterface` side effects: https://developer.apple.com/forums/thread/659755
- Event tap permissions: https://developer.apple.com/forums/thread/122492, https://developer.apple.com/forums/thread/707680
- Jot insertion and secure-input guard (Apache-2.0): https://github.com/google-gemini/jot-gemini-transcribe-macOS (`AXInserter.swift`, `SecureInput.swift`, `AppQuirks.swift`)
- MAI options: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- xAI STT: https://docs.x.ai/developers/model-capabilities/audio/speech-to-text

## Appendix: queries run

All on the APFS clone, with `sqlite3 'file:flow.sqlite?immutable=1'`. Copy step: `cp -c flow.sqlite <scratch>/wispr-clone/flow.sqlite` (no `-wal` file existed). The clone and the diff output were deleted after the queries.

```sql
SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;
.schema Dictionary
.schema TranscriptCorrections
.schema Polish
.schema UserContext
.schema UserVoicePreferences
.schema History
SELECT source, manualEntry, isDeleted, isSnippet, (teamDictionaryId='00000000-0000-0000-0000-000000000000') AS personal, (replacement IS NOT NULL AND replacement<>'') AS has_repl, (observedSource IS NOT NULL) AS has_obs, count(*) n FROM Dictionary GROUP BY 1,2,3,4,5,6,7 ORDER BY n DESC;
SELECT phrase, observedSource, replacement, frequencyUsed, remoteFrequencyUsed, manualEntry, isDeleted, createdAt, modifiedAt, lastUsed FROM Dictionary WHERE source='user_edits' OR observedSource IS NOT NULL ORDER BY createdAt;
SELECT min(createdAt), max(createdAt), sum(frequencyUsed), max(frequencyUsed) FROM Dictionary;
SELECT count(*) n, min(timestamp), max(timestamp), sum(numWords) words, sum(numWordsCorrected) corrected, sum(numDictionaryReplacements) dict_repl FROM History;
SELECT editedTextStatus, count(*) n, sum(editedText IS NOT NULL) has_edited, sum(axText IS NOT NULL) has_ax, sum(userEditMetaData IS NOT NULL) has_meta, avg(editedTextAttempts) avg_attempts, max(editedTextAttempts) max_attempts FROM History GROUP BY 1 ORDER BY n DESC;
SELECT contentObservationEndReason, count(*) n FROM History GROUP BY 1 ORDER BY n DESC;
SELECT contentObservationEndLastKeystroke, count(*) n FROM History GROUP BY 1 ORDER BY n DESC LIMIT 15;
SELECT j.key, j.type, count(*) n FROM History h, json_each(h.userEditMetaData) j WHERE h.userEditMetaData IS NOT NULL GROUP BY 1,2 ORDER BY n DESC;
SELECT j.key, j.type, count(*) n FROM History h, json_each(h.additionalContext) j WHERE json_valid(h.additionalContext) GROUP BY 1,2 ORDER BY n DESC LIMIT 30;
SELECT contentObservationEndReason, count(*) n, sum(editedText IS NOT NULL) has_edited, sum(editedText IS NOT NULL AND editedText <> coalesce(pastedText, formattedText)) differs, round(avg(editDistanceToDictated),3) avg_dist, sum(numWordsCorrected) corrected FROM History GROUP BY 1 ORDER BY n DESC;
SELECT (asrText = formattedText) same_asr_fmt, (editedText IS NOT NULL) has_edited, count(*) n, sum(numWordsCorrected) corrected, sum(numWords) words FROM History GROUP BY 1,2;
SELECT json_extract(userEditMetaData,'$.word_edits') we, json_extract(userEditMetaData,'$.punctuation_edits') pe FROM History WHERE userEditMetaData IS NOT NULL AND json_extract(userEditMetaData,'$.word_edits') NOT IN ('[]','0','') LIMIT 8;
WITH w AS (SELECT json_extract(userEditMetaData,'$.word_edits') s FROM History WHERE userEditMetaData IS NOT NULL) SELECT count(*) rows, sum(length(s)) ops, sum(length(s)-length(replace(s,'M',''))) m, sum(length(s)-length(replace(s,'S',''))) s_ops, sum(length(s)-length(replace(s,'I',''))) i_ops, sum(length(s)-length(replace(s,'D',''))) d_ops, sum(length(s)-length(replace(replace(replace(replace(s,'M',''),'S',''),'I',''),'D',''))) other, sum(s GLOB '*[^M]*') rows_with_edit FROM w;
SELECT h.app, count(*) n, sum(h.editedText IS NOT NULL) edited, sum(json_extract(h.userEditMetaData,'$.word_edits') GLOB '*[^M]*') word_edited FROM History h GROUP BY 1 ORDER BY n DESC LIMIT 10;
SELECT d.phrase, d.createdAt learned_at, h.timestamp dictated_at, h.app, h.contentObservationEndReason, h.contentObservationEndLastKeystroke, instr(h.formattedText, d.observedSource)>0 heard_in_pasted, instr(h.editedText, d.phrase)>0 phrase_in_edited, round((julianday(substr(d.createdAt,1,23)) - julianday(substr(h.timestamp,1,23)))*86400,1) secs_after FROM Dictionary d JOIN History h ON h.editedText IS NOT NULL AND instr(h.editedText, d.phrase)>0 AND instr(coalesce(h.pastedText,h.formattedText), d.phrase)=0 WHERE d.source='user_edits' ORDER BY d.createdAt, h.timestamp;
SELECT app, count(*) n, round(avg(json_array_length(additionalContext,'$.variable_names')),1) avg_vars, round(avg(json_array_length(additionalContext,'$.file_names')),1) avg_files, round(avg(json_array_length(additionalContext,'$.dictionary_context')),1) avg_dict, round(avg(json_array_length(additionalContext,'$.ax_context')),1) avg_ax, round(avg(json_array_length(additionalContext,'$.ocr_context')),1) avg_ocr FROM History WHERE json_valid(additionalContext) AND json_type(additionalContext,'$.variable_names')='array' GROUP BY app ORDER BY n DESC LIMIT 8;
SELECT round(avg(averageLogProb),3) avg_lp, min(averageLogProb), max(averageLogProb), sum(averageLogProb IS NOT NULL) n FROM History;
SELECT app, contentObservationEndReason, count(*) n, sum(editedText IS NOT NULL) has_edited FROM History WHERE app IN ('com.cmuxterm.app','com.todesktop.230313mzl4w4u92','com.mitchellh.ghostty') GROUP BY 1,2 ORDER BY 1, n DESC;
```

The word alignment in section 1.3 used this read-only query in a Python script (`difflib.SequenceMatcher` on whitespace tokens), output kept in the scratch folder and deleted:

```sql
SELECT coalesce(pastedText, formattedText), editedText, app, contentObservationEndReason
FROM History WHERE editedText IS NOT NULL AND editedText <> coalesce(pastedText, formattedText);
```

## Unresolved questions

Owner decisions, each with a recommendation.

1. Suggest-and-confirm or auto-add for edits that kotoba sees after paste? Recommendation: suggest and confirm. The owner makes about 3 useful edits a month, so the cost is small, and both TypeWhisper and Willow had trouble with auto-add.
2. Learn identifiers, names and acronyms (which Wispr skips), but not paths, URLs or numbers? Recommendation: yes. Wispr did not learn 9 of the 14 useful edits in its history; 8 of those 9 are identifiers or product names.
3. Rule or term for a heard text that is a common word (`ember` -> `embra`)? Recommendation: term only. A rule would rewrite the common word in every later dictation. The same question applies to the existing Wispr import, which makes `Mellow` -> `Marlow` a rule today.
4. Seed suggestions once from Wispr's history edits (reads Wispr's `History` table, not only `Dictionary`; the spec has history import out of scope)? Recommendation: yes, as pending suggestions only, from a clone, with the field text kept in memory and dropped after.
5. Learning from edits (readback) on or off by default? Recommendation: on, after the spike passes, with a toggle in the Dictionary pane. It is local only and stores only word pairs. Context sources (Contacts, repositories, window text) stay off by default (story 34).
6. Where do suggestions show? Recommendation: a Suggestions section in the Dictionary pane, plus a menu item with the count. No indicator change.
7. Should "Fix Last Dictation..." also put the corrected text on the clipboard? Recommendation: yes, copy only; no re-paste, because the focus has moved.
8. An LLM review of candidates (VoiceInk style, via the cleanup model with ZDR)? Recommendation: not now. Measure the local filters first on the Wispr pairs; add a review only if precision is under 80%.
