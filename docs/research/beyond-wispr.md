# Beyond Wispr Flow: what makes kotoba better for its owner

Status: research, 2026-10-16 00:54 IST. Agent `research-edge`. Read-only: no kotoba source changed, no paid API called, no sign-up. Scope: (1) Wispr Flow's features and failures, and what users of competing apps praise or ask for; (2) methods that raise transcript accuracy on developer speech, with evidence and latency cost; (3) interaction details. Earlier research is not repeated: see `docs/research/dictation-apps.md` (Wispr and Aqua pipelines), `landscape-macos.md`, `auto-learning.md`, `ux-polish.md`, `cleanup-llms.md`.

Status marks used below:
- **built**: in the code today (file named).
- **spec**: in `docs/spec.md`, not built (or not complete).
- **new**: not in the spec.

## Summary

- kotoba already wins on the four things users complain about most: RAM (Wispr about 750 MB at rest, kotoba about 17 MB), privacy (Wispr app and URL tracking, screenshot controversy), cost (Wispr $12-15/month vs about $0.10/h of audio), and "AI changed my words" (Wispr's Auto Cleanup bug; kotoba pastes the raw transcript). Section 1.
- The largest open gap for this owner is accuracy on identifiers. kotoba sends one global dictionary. Wispr, Aqua and Claude Code's own `/voice` all add terms from the **current work** (visible variables, open files, project and branch name). The evidence says a short, relevant list helps a lot and a long list hurts. Section 3.
- Top 5 new ideas, by value divided by cost (section 5):
  1. Per-dictation context terms from the active coding session (Claude Code / Codex session files, repo file names, git branch), merged into the phrase list. No stop-path latency.
  2. "Paste Last Dictation" and "Copy Last Dictation" shortcuts (Wispr default ⌃⌘V / ⌃⌘C).
  3. Submit after paste: a spoken "press enter" at the end, or a stop gesture that sends Return (Wispr, Aqua "Send it").
  4. A live "no sound" warning while recording (Wispr, 2026-10-09).
  5. Rank and cap dictionary terms per request by use and recency, with the context terms first (Wispr "starred terms, usage-based ranking"; list-size evidence).

## 1. Wispr Flow today

### 1.1 Features added in 2026 (Wispr's own changelog)

Source for every row: https://wisprflow.ai/whats-new (fetched 2026-10-16), unless the row names another source.

| Date | Feature | kotoba status |
|---|---|---|
| 2026-03-31 | Sessions up to 20 min; rebindable cancel key; Enter can be reassigned; "Mouse Flow" (a mouse button starts dictation or sends Enter); dictionary "starred terms, usage-based ranking, and better auto-add filtering"; retry failed or cancelled dictations from History | 10-min warning, no stop: spec + built. Chord recorder: spec 2.6. Mouse trigger: new (low value). Term ranking: **new**. Retry: built (`RetryQueue.swift`). |
| 2026-04-24 | Auto Cleanup with four levels (None to High) and "Undo AI edit" to get the raw text; local transcript storage can auto-delete after 24 h | Raw-first main path: spec + built. Cleanup on its own chord: built (`CleanupChord.swift`, `OpenRouterCleaner.swift`). Raw-text recovery after cleanup: **new** (see 4). Audio retention: spec (phase 3). |
| 2026-05-01 | Scratchpad (floating notepad); Transforms (AI rewrite of selected text, presets "Polish" and "Prompt Engineer", optional run after each dictation); "Dictation into Claude Code and Codex terminals keeps longer text visible and editable"; interrupted dictations recoverable after quit | Edit selection by voice: **new**. Recovery: built ("Recovered Dictations", `App/StatusMenu.swift:94-97`). |
| 2026-06-24 | Course corrections, fewer changed words, punctuation and edit commands followed more often; highest-ranked available mic picked automatically | Mic preference order: spec + built (`MicrophonePreferences.swift`). Course correction ("no, dash dash debug"): only in the cleanup prompt (`OpenRouterCleaner.swift:125-126`). |
| 2026-07-09 | Flow Bar drags to left or right edge; latency "down 30% since the start of the year"; "an overly aggressive Auto Cleanup setting" identified as the main cause of accuracy problems | Indicator anchors: spec + built (`IndicatorPlacement.swift`). |
| 2026-08-05 | History replays the original audio of the last 14 days | spec (History window, audio retention). |
| 2026-08-21 | Double-tap of push-to-talk toggles hands-free; virtual audio devices as mic | Tap vs hold: built (`HotkeyClassifier.swift`). |
| 2026-09-04 | Dictionary shared org-wide; updates wait until the user is idle | Not relevant (one user). |
| 2026-09-17 | Canto, Wispr's own ASR model, default for all users | Provider choice by benchmark: spec + built. |
| 2026-10-09 | "Flow warns you right away when your mic picks up no sound while dictating" | After-the-fact "No speech heard" only (`App/StatusText.swift:97`). Live warning: **new**. |

Other Wispr features that matter here:
- Shortcuts: push-to-talk, hands-free, Command Mode, **Paste last transcript (⌃⌘V)**, **Copy last transcript (⌃⌘C)**, Cancel, and an unbound **Press Enter** action. https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts
- Spoken "press enter" at the end of a dictation presses Return after the paste; it must be the last words, and it is an Experimental setting. https://talk.macpowerusers.com/t/wisprflow-tip-press-enter-to-trigger-return/45142
- Variable recognition in Cursor and VS Code from visible names; file tagging with `@` in Cursor and Windsurf chat only; tagging is skipped in terminals. https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides
- Auto-learn skips file names, paths, code symbols and IDs, so code terms must be added by hand. https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary

### 1.2 Where Wispr fails (complaints and measured faults)

| Area | Evidence | kotoba position |
|---|---|---|
| Accuracy changed by the formatter | Wispr's own changelog: the Auto Cleanup setting was "the main driver of recent accuracy issues" (2026-07-09) and a rollback was tested (2026-06-04). https://wisprflow.ai/whats-new | Raw transcript + find/replace on the main path (spec "Cleanup"). Already better. |
| Developer terms | Owner's data: about 10,000 corrected words of 73,000 (counter includes formatter changes); Wispr learns no code symbols by design (see 1.1). `docs/spec.md` Problem Statement, `auto-learning.md` 1.3 | Phrase list from the dictionary: built. Context terms: **new** (section 3). |
| Latency | Owner's machine: 1,254 ms average end to end (`docs/spec.md`). Wispr claims a 30% drop in 2026. https://wisprflow.ai/whats-new | Gate p50 <= 1.0 s, p90 <= 1.5 s (spec). |
| RAM | 748 MB at rest and nearly 1 GB while recording on an 8 GB iMac; calls lagged until Flow was closed (tl;dv test, 2026-09-22 to 25, v1.6.937, a competitor). https://tldv.io/blog/wispr-flow-notetaker-review/ | About 17 MB idle (`memory-spike.md`). Already better. |
| Privacy | Independent log and database analysis (v1.4.752, 2026-04-03 to 04): foreground app and browser URL logged on each switch (1,688 events in about 30 h), hourly `POST /history/upload` "only uploading metadata" with sharing off, PostHog, Sentry, Segment and Datadog telemetry, 694 MB local database. https://wensenwu.com/thoughts/wispr-flow-investigation . A May 2026 report that Context Awareness sent window screenshots; the docs now say it reads text through Accessibility. https://laxis.com/blog/wispr-flow/ | No telemetry, no accounts, only the chosen provider (spec story 40). Already better. |
| Keyboard faults | The same analysis: a system-wide event tap suppressed 145 spacebar presses in about 10 min after a stuck Right Option key; stale-key recovery never cleared it. https://wensenwu.com/thoughts/wispr-flow-investigation | Risk for kotoba too: `App/HotkeyTap.swift:55` uses `.defaultTap` (can swallow events). See section 7. |
| Reliability | Outages "caused by scaling changes" in mid-2026. https://wisprflow.ai/whats-new (2026-06-04, 2026-06-10) | Audio kept, retry queue: built. |
| Cost | Pro $15/month or $12/month annual, free tier about 1,000 words per week. https://www.wrdw.com/2026/09/21/what-tech-app-day-wispr-flow/ | About $0.10/h of audio with own key (spec). |

## 2. Competitors: what users praise and ask for

| App | What users praise or the vendor ships | Source |
|---|---|---|
| Aqua Voice | Instant Mode about 450 ms after speech ends; Streaming Mode about 850 ms; Deep Context (screen-aware identifiers, off by default); File Tagging ("main ts" to `@main.ts`); Edit Mode (select, hold key, speak the change); "Send it" as the last words sends Enter, ⌘Enter or Ctrl+Enter (desktop v0.18.0, 2026-07-26); no "undo that" | https://aquavoice.com/llms.txt , https://aquavoice.com/guide/file-tagging |
| Superwhisper | Super Mode context: app text, selected text at record start, clipboard copied within 3 s of start; History shows everything sent to the AI, for diagnosis | https://superwhisper.com/docs/modes/super.md |
| Superwhisper users | Top requests: sync (50 votes), Linux, text to speech, **pause recording** (10), **auto language detection** (10), **hooks on record / transcribe / LLM complete** (10), **re-process with different settings** (4) | https://feedback.superwhisper.com/?sortBy=upvotes |
| FreeFlow (MIT) | Groq ASR, LLM cleanup with nearby app context; Edit Mode on highlighted text; literal prompt rule "correct only words the speaker already said that closely resemble a context or vocabulary term. Never insert names the speaker didn't say" | https://github.com/zachlatta/freeflow |
| Willow | "Spaces are now intelligently inserted when starting new dictations" (2025-09-27); fix for "capitalization errors in smart insertions"; auto-dictionary made "much less aggressive" | https://willowvoice.featurebase.app/changelog |
| Typeless | "Speak to edit": select text, speak the change, the edit replaces the selection | https://www.typeless.com/help/release-notes/ios/speak-to-edit |
| Spokenly | BYOK at no fee; custom dictionary and word replacements; MCP voice input so Claude Code, Codex and Cursor can ask for a spoken answer | https://spokenly.app/llms.txt |
| Monologue | App-based tone; dictionary of names, acronyms, slang; reviewers flag screen reading as a privacy risk | https://www.getvoibe.com/resources/monologue-review/ |
| Claude Code `/voice` | Adds the project name and git branch as recognition hints; a user request (May 2026) asks for custom vocabulary because skills, tool names and CLI subcommands are missed | https://aquavoice.com/blog/voice-dictation-claude-code , https://claudeissues.com/issue/60774-voice-dictation-user-configurable-vocabulary-hints-for-custom-terms |

Hacker News (FreeFlow launch, 277 points, 2026-02-16; "non-cloud alternative" thread, 2026-09-22): users praise speed, low cost, one-time price, local or own-key privacy, per-app prompts, and custom dictionaries for technical terms. They ask for streaming text while speaking, a toggle mode, a changeable hotkey, saved audio with the transcript, and no clipped first words (a Handy complaint). One user uses dictation "mainly to talk to coding agents". https://hn.algolia.com/api/v1/items/47040375 , https://hn.algolia.com/api/v1/items/49809670

Lesson: every praised item except streaming text is already in kotoba's spec. The differences left are accuracy on the owner's identifiers and a few small interaction tools.

## 3. Accuracy methods on developer speech

| Method | Evidence | Stop-path latency | Status |
|---|---|---|---|
| Global phrase list from the dictionary | kotoba-bench-v1: MAI term recall 58.7% -> 73.2% with phraseList (`docs/spec.md` Further Notes). Azure: a phrase list "shouldn't have more than 2,000 phrases. Note that a longer phrase list will impact quality and latency." https://learn.microsoft.com/en-us/azure/ai-services/speech-service/improve-accuracy-phrase-list | Not measured by list size. Request body grows a few KB. | built |
| **Per-dictation context terms** (active repo, files, branch, identifiers in the current agent session) | Context biasing cuts biased-word WER by up to 88% relative with other words "largely unaffected" (Huber and Waibel). https://arxiv.org/abs/2608.05759 . Claude Code `/voice` adds project and branch names (section 2). Wispr uses visible variable names; Aqua uses screen identifiers (section 1.1, 2). | 0 ms if collected between chord-down and chord-up (recording lasts 10-20 s). | **new** (spec story 34 names "context awareness", but only as selected or nearby text) |
| Keep the list short and ranked | Bias lists degrade past about 100 phrases (streaming transducer) and the gain shrinks at 1,000 (phrase prediction network). https://arxiv.org/pdf/2306.00804 , https://arxiv.org/pdf/2305.12493 . Wispr Canto took a similar wrong term "nearly five times as often" after RL. https://wisprflow.ai/canto . Deepgram caps keyterms at 100. https://developers.deepgram.com/docs/keyterm . OpenAI: unspoken keywords "can appear" in output. https://developers.openai.com/api/docs/guides/speech-to-text | 0 ms (smaller request). | **new** (ranking); route caps built (`TextCleaner.swift:9` "within the route limits") |
| Free-text context prompt into the ASR | OpenAI `gpt-transcribe` takes `prompt` (unstructured context) plus `keywords`. https://developers.openai.com/api/docs/guides/speech-to-text . No `prompt` field found for MAI-Transcribe-2 fast transcription; only `phraseList`. https://learn.microsoft.com/en-us/azure/ai-services/speech-service/improve-accuracy-phrase-list . Prompting stock Whisper raised long-form WER from 12.36 to 18.88 in one study. https://arxiv.org/pdf/2307.10274 | Unknown; needs a bench run. | new (bench candidate only) |
| LLM post-correction (cleanup chord) | kotoba-bench-v1: no cleanup LLM beat the raw transcript on WER (`docs/spec.md`). Unconstrained correction can break text: DeepSeek-V2 CER 5.06 -> 53.10 on AISHELL-1; a detect-correct-verify pipeline with GPT-4o gives 5-21% relative. https://arxiv.org/html/2505.24347v3 . Entity retrieval plus multiple hypotheses: 8-46% relative entity WER. https://arxiv.org/pdf/2603.16411 | 1-2 s or more (`cleanup-llms.md` section 6). Off the main path. | built (chord), spec |
| "Data, not instructions" prompt | Spotlighting: delimiting cut attack success "by about half"; datamarking cut it to 1-8%, encoding to 0-1.8%, from above 50% (GPT-3.5 / GPT-4). Datamarking had no task loss on QA and classification; rewrite tasks were not tested. https://arxiv.org/html/2403.14720v1 | 0 ms. | built: delimiting with tag escaping (`OpenRouterCleaner.swift:72`, `:93-99`). Datamarking: new, but risky for verbatim text. |
| Context candidates into the cleanup prompt | FreeFlow rule: change only words that "closely resemble a context or vocabulary term". https://github.com/zachlatta/freeflow . Retrieval papers above. | 0 ms extra on the cleanup call. | partly built (dictionary passed, `TextCleaner.swift:11`); context terms new |
| Readback learning | Wispr saw edits in 42 of 1,146 dictations; 79% of cmux dictations gave no text; 31% of replacements were dictionary material (`auto-learning.md` Summary). | 0 ms (after paste). | spec 2.6; detector built (`CorrectionDetector.swift`, `FixLastDictation.swift`) |
| Spoken casing and file-name forms ("camel case user id", "auth dot ts") | Aqua maps both; Wispr needs a dot in the file name. `dictation-apps.md` 1.5, 2.5 | 0 ms if the target names are in the phrase list. | new (comes with context terms) |

### 3.1 Where context terms come from, for this owner

The owner dictates mostly into cmux running Claude Code or Codex (210 of 275 bench clips from cmux, `docs/spec.md`). Terminal text is hard to read through Accessibility (Ghostty-based `AXValue` is the whole scrollback; one read took 3 s, `auto-learning.md` 3a), and the cmux socket accepts only processes with cmux ancestry by default. https://www.mintlify.com/manaflow-ai/cmux/automation/socket-api

A cheaper source exists on this Mac (checked by directory listing, 2026-10-16): Claude Code writes each session to `~/.claude/projects/<cwd with / as ->/<session>.jsonl`, and Codex writes to `~/.codex/sessions/`. The newest file tells which repo is active; its last messages hold the identifiers the owner talks about now. Proposed read, at chord-down, off the hot path:
1. Newest session file by modification time (one `stat` per project folder) -> repo path.
2. Repo terms: repo name, current branch (`.git/HEAD`), file names from `git ls-files` (cache by repo and HEAD).
3. Session terms: identifier-shaped tokens (camelCase, snake_case, dotted file names, `--flags`) from the last about 32 KB of the session file.
4. Rank: session terms, then dictionary terms by use and recency, then repo file names. Cap at the route limit (xAI 100 keyterms; MAI unpublished, keep about 100).
5. Ready before chord-up; if not ready, send the dictionary list only (never wait).

For Cursor and VS Code, the window title shows the active file and folder. https://dev.to/augiefra/how-i-used-macos-accessibility-api-to-fix-my-vscode-workflow-23a9

Privacy: the terms leave the Mac in the provider request. Keep it off by default (spec story 34) and show the sent terms in History (Superwhisper does this, section 2).

## 4. Interaction details

| Detail | Evidence | Status |
|---|---|---|
| Start sound only after capture starts; cues can be off | spec stories 7-8 | spec + built |
| Pill states, error pill with one action, timer bar, hover pause | spec 2.5, 2.6; `ux-polish.md` I1 | built / spec |
| Esc cancels, Undo resumes for 5 s | Wispr does the same (spec 5a) | built (`UndoWindow.swift`) |
| **Paste Last / Copy Last shortcut** | Wispr ⌃⌘V / ⌃⌘C, also in its menu bar menu (section 1.1) | **new** (only "Recovered Dictations" for failures, `App/StatusMenu.swift:94`) |
| **Submit after paste** | Wispr "press enter" (last words only) and an unbound Press Enter action; Aqua "Send it" with Enter, ⌘Enter or Ctrl+Enter (sections 1.1, 2) | **new** |
| **Live "no sound" warning** | Wispr 2026-10-09 (section 1.1) | **new** |
| Smart leading space and first-letter case at the insertion point | Willow (section 2); Wispr API sends `before_text` for casing and spacing (`dictation-apps.md` 2.4) | **new**; not possible in terminals (no readable text) |
| Edit selected text by voice (insert vs replace) | Wispr Command Mode and Transforms, Aqua Edit Mode (6,000-character cap), FreeFlow, Typeless, Superwhisper (sections 1.1, 2) | **new** (cleanup chord exists, `CleanupChord.swift`) |
| Raw text after cleanup ("Undo AI edit") | Wispr 2026-04-24 (section 1.1) | **new**; fits Paste Last ("Paste Raw") |
| Re-transcribe saved audio with another model | Superwhisper request; Wispr retry from History (sections 1.1, 2) | **new**; fits the History window (spec phase 3) |
| Streaming text while speaking | HN users ask for it (section 2); Aqua's own numbers: streaming about 850 ms vs instant about 450 ms (section 2) | Out of scope (spec). Evidence supports that: it costs stop-path latency. |
| Spoken edit commands ("new line", "scratch that") | Apple's list varies by macOS version; "undo that" is a Voice Control command. https://macmost.com/mastering-voice-control-dictation-on-your-mac.html . Aqua does not support "undo that" (section 2) | Not needed: the owner edits with the keyboard. |
| Pause recording | Superwhisper request, 10 votes (section 2) | Low value: Esc + Undo already resumes. |

## 5. Ranked ideas

Value is for this owner (prompts to coding agents, mostly in cmux). Cost is stop-path latency, idle RAM and build effort. Score = value / cost, highest first.

| Rank | Idea | Value | Stop-path latency | Idle RAM | Effort | Status |
|---|---|---|---|---|---|---|
| 1 | Context terms from the active coding session and repo (3.1), ranked and capped | High: targets identifiers, the main error class | 0 ms (built during recording); never waits | ~0 (no work at idle) | M | new |
| 2 | Paste Last Dictation / Copy Last Dictation (menu + shortcut), with "Paste Raw" after cleanup | Med-high: wrong-field paste, lost focus, reuse | 0 ms | 0 | S | new |
| 3 | Submit after paste: stop gesture with Return, or "press enter" / "send it" as the last words | Med-high: every agent prompt ends with Return | +1 key event (< 5 ms) | 0 | S | new |
| 4 | Live "no sound" warning after about 2 s of silence while recording (level meter exists) | Med: saves a lost long dictation | 0 ms | 0 | S | new |
| 5 | Rank dictionary terms by use and recency; cap per request; never exceed the route limit | Med: protects accuracy as the list grows (auto-learning adds terms) | 0 ms | 0 | S | new |
| 6 | Smart leading space and first-letter case from one AX read at chord-down (skip terminals and secure fields) | Med in Slack and browsers, 0 in cmux | 0 ms (read during recording, 10-20 ms, 0.25 s timeout) | 0 | S-M | new |
| 7 | Context terms into the cleanup prompt with a "resemble only, never insert" rule | Med | 0 ms extra on the cleanup call | 0 | S | new |
| 8 | Voice edit of a selection on the cleanup chord (selection present -> instruction mode) | Low-med: the owner mostly writes new prompts | 1-2 s (LLM), off the main path | 0 | M | new |
| 9 | Re-transcribe a saved dictation with another route, and show what was sent (History) | Low-med: helps tune accuracy | n/a | SwiftUI window cost, already accepted | M | new (with spec History) |
| 10 | Bench `gpt-transcribe` with `prompt` + `keywords` vs MAI + phraseList | Unknown | Unknown | 0 | S, paid run | new |
| - | Readback learning, History, per-app modes, usage tracker, Insights | See spec | - | - | - | spec |
| - | Streaming preview | Owner rejected; costs latency | - | - | - | out of scope |

## 6. Notes for the top new ideas

- Idea 1 must follow spec 2.6 ("no work at idle"): start on chord-down, finish before chord-up, cache per repo HEAD. Report the measured footprint and the time from chord-down to list ready. The bench can measure gain: rerun kotoba-bench-v1 clips with session terms built from the matching Claude Code session (needs the owner's go for a paid run).
- Idea 3 should be a gesture first (for example, a modifier held at the stop tap), because a spoken trigger can fire by mistake. Wispr limits the spoken form to the last words and puts it under Experimental (section 1.1).
- Idea 4: the pipeline already has the mic level; the warning is a pill state, with no new timer at idle (it runs only while recording, on the injected clock).

## 7. Risk found (follow-up, not fixed)

- `App/HotkeyTap.swift:55` creates the tap with `.defaultTap`, so it can drop events. Wispr's tap dropped 145 spacebar presses after a stuck modifier (section 1.2). Check that kotoba passes through every event that is not the chord or Esc during recording, and that a lost key-up (for example after sleep or a secure-input switch) cannot leave the chord "down".

## Unresolved questions

1. Does MAI-Transcribe-2 accept any free-text context besides `phraseList`, directly or through OpenRouter? Not found in Microsoft's docs.
2. What is MAI's phrase-list cap, and how does list length change its latency and false-term rate? Azure says only "no more than 2,000" for its general models.
3. May context terms (repo file names, identifiers from Claude Code sessions) leave the Mac in the provider request? The owner must decide (spec story 34 is "off by default").
4. In cmux, which pane is focused, and can kotoba get its cwd without the socket? The newest-session-file rule can pick the wrong repo when two agents run at once.
5. Does a long paste into cmux (Claude Code) arrive whole? Wispr needed a fix for "longer text" in Claude Code and Codex terminals (2026-05-01).
6. Which submit key does each target need (Return in Claude Code, ⌘Return in some chat apps)? Aqua offers a per-dictation choice.
7. Wispr's subprocessor and screenshot claims come from third parties (laxis.com, wensenwu.com); Wispr did not answer them on those pages.
