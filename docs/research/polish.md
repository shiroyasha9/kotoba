# Polish: model and prompt

Status: bench, 2026-10-17 (03:24-04:30 IST). Agent `polish-bench`. Paid: USD 1.50 on OpenRouter (cap raised from USD 1.50 to 3.00 during the run); 4 Codex pilot jobs (2.38 credits) before the judge moved to OpenRouter. Inputs: the owner's Wispr Flow Polish history (read-only copy of Wispr's database), the cleanup research (`cleanup-llms.md`, `cleanup-prompts.md`, `per-app-modes.md`) and the bench harness in `bench/`. Personal text, outputs and per-row scores stay in the runbooks folder `<runbooks>/2026-10-17-kotoba-polish/`; this file has the method, the prompt and aggregate numbers only.

## Summary

- **Recommendation: DeepSeek V4.1 Flash, pinned to the Together host, reasoning off, with prompt v2 (section 4).** On a 40-input test sample of the owner's real Polish inputs, it kept 97.1% of the checklist items (Wispr Flow's own output: 86.5%), lost or changed an item in 22.5% of outputs (Wispr: 55.0%), and added content in 2.5% (Wispr: 45.0%). Output is a median 0.78 of the input's words (Wispr: 0.69). Latency for 200-400 word inputs, one request at a time from India: p50 1.06 s, p90 1.33 s to the last token. Cost: USD 0.34 per 1,000 Polish.
- **Fallback: Gemini 3.5 Flash-Lite with the same prompt** (Google, already kotoba's cleanup default): 87.6% kept, Wispr-level preservation, shorter output (0.68), p50 1.39 s, p90 1.91 s, USD 0.88 per 1,000.
- The trade is length against loss. The fast models that cut most (gpt-oss-120b, Wispr's own model, at 0.49; Qwen 3.8 27B at 0.55) lose the most (75.6% and 81.7% kept). gpt-oss also writes non-ASCII hyphens (U+2011) in 62-84% of outputs, the same defect as 80% of Wispr's outputs, which breaks identifiers in a terminal.
- DeepSeek without a host pin went to 11 hosts with total p50 from 1.0 s to 8.6 s per host (p90 8.6 s overall). Pin the host.
- A length target in the prompt (v3) made 3 of 4 models lose more; two examples (v2) helped Gemini most (82.4% to 90.5% kept on the 25 dev inputs).
- Limits: one sample per (model, input); 40 of the 80 test inputs; one judge model (GPT-6 Luna). See unresolved questions.

## 1. What Polish is

- Wispr Flow's Polish rewrites a dictated text with an LLM. The owner ran it 111 times (2026-04-30 to 2026-10-13): 105 succeeded, 0 were undone, 99 were in cmux, mostly prompts for coding agents. All 105 used one instruction: "Make more concise, Maintain your tone, Reword for clarity, Reorder for readability, Add structure for readability".
- Wispr's model, from `Polish.usedProvider`: `gpt-oss-120b` on Cerebras for 95 rows (Wispr's `processingTime`: p50 1.33 s, p90 1.90 s), `gpt-5-nano` on OpenAI for 10 rows (p50 5.4 s).
- On the 105 pairs, Wispr's output is a median 0.70 of the input's words.

## 2. Eval set

- All 105 Polish rows with `status = 'succeeded'` (3 `error`, 2 `short_text` and 1 `timeout` rows have no output). All 105 inputs are distinct. Input: median 234 words, mean 281, range 35-924. 50 inputs hold Wispr's list HTML (`<ul>`, `<ol>`, `<li>`); the bench turns it into "- " and "1. " lines, because kotoba's input is plain text.
- Split by a hash of the row id: 25 dev inputs pick the prompt, 80 test inputs rank the models. The test numbers are the honest ones.
- Cut to fit the cap (the paid judge costs about USD 0.001 per verdict): the prompt choice is judged on all 25 dev inputs; the models run and are judged on a test sample of 40 of the 80 test inputs, 10 from each input-length quartile (35-924 words).
- The input is the text the owner sent to Polish, so it is Wispr's transcript after Wispr's own cleanup, with the speech-to-text errors left in it (for example a framework name heard as other words). That is the real case for kotoba too: Polish runs on a dictation that is already pasted.
- No vocabulary block: these inputs have no kotoba dictionary match data, and Polish runs on text, not audio.

## 3. Scoring

Four signals per output. Wispr's own output gets the same scores, as a reference, not as ground truth.

1. **Preservation (LLM judge, two steps).** The judge model writes one fixed checklist per input: every instruction, question, constraint, fact and identifier, each with the exact words and a "critical" flag (would dropping it change what the agent does). A second model then grades each output against that same checklist: every item is kept, weakened, changed or lost, with the output's words as evidence. One fixed checklist per input makes every model and prompt meet the same bar. Scores: share of items kept, rows that lose (or change) at least one item, rows that lose a critical item.
2. **Exact tokens (code, no LLM).** Every code-like token of the input (paths, file names, dotted and snake_case identifiers, slash commands, flags, URLs, camelCase, all-caps words, numbers, backticked spans) must occur in the output, case-sensitive, after mapping non-ASCII hyphens, spaces and quotes to ASCII. Also counted: code-like tokens in the output that the input never had (invented names), and outputs with a non-ASCII hyphen or space (an identifier written with a U+2011 hyphen is a different string in a terminal prompt).
3. **Concision.** Output words over input words, median per variant.
4. **Added content and answering (judge).** Statements, requests, names or steps that the input does not support; and whether the output answers or does the task instead of rewriting it. The judge also gives a 1-5 clarity score (how easy the output is for a coding agent to act on).

Judge: OpenAI GPT-6 Luna at medium reasoning through OpenRouter, zero-data-retention endpoints (Azure), JSON schema output. It is not a candidate, so no model grades its own rewrites. A first pilot with Claude Haiku 5.5 as judge "corrected" speech-to-text names in its checklists (for example a misheard package name written as the real one), so a rewrite that guessed the same name looked faithful; the checklist brief now says to copy every name as the text spells it. Check against the Codex pilot (checklist by GPT-6.1 Sol, verdicts by GPT-6 Luna in Codex) on the one input both scored: both judges flag the same gpt-oss losses (a deferred decision, a stated doubt, the final summary; Codex 4 lost, 1 weakened, 1 changed; OpenRouter 3 lost, 4 weakened). The Codex verdict passed every Haiku item; the OpenRouter judge flagged one changed name in the Haiku output (a misheard package name replaced by a guessed one), which the rubric counts as changed. The judge is one model, one sample per output: read differences of a few points as noise.

Judge rubric (the full briefs and JSON schemas are in the runbooks folder, `judge/`):

| Status | Meaning |
| --- | --- |
| kept | Same meaning, maybe merged with other items. New wording, order, lists and paragraphs are by design. |
| weakened | Present but vaguer: a number, name, condition or example is gone; "must" became "may"; a stated doubt became a certainty or the other way round. |
| changed | Says something different, or names a different thing (a different identifier, or a guessed "correction" of a name). |
| lost | Not in the output. |

A small spelling change of the same identifier (case, spaces, hyphen style) is kept. "Please", connecting words and a restated point are not added content.

Latency: streaming chat completions through OpenRouter from India, zero-data-retention endpoints only (`provider.zdr`, as kotoba sends). TTFT is the first content token; total is the last token. The quality pass runs 4 requests at a time; a separate latency pass sends one request at a time on 200-400 word inputs, the model order reversed on every other input. Cost is OpenRouter's `usage.cost`.

## 4. Prompts

All three share one shape, the same as kotoba's v3 cleanup prompts (`cleanup-prompts.md` section 2.6): rules in the system message, the text in the user message inside `<text>` tags, a pipeline role ("not a coding assistant"), the reader named as the destination, and examples in `<example>` tags. The rules say what stays (every instruction, constraint, fact, doubt, identifier) before what goes. Code: `bench/polish/prompts.ts`.

- v1: rules only.
- v2: v1 plus two synthetic examples: a self-correcting request with a file path, steps and a "don't touch" constraint, written back as a short paragraph and a "- " list; and a design question with a doubt, which must not be answered.
- v3: v2 plus "Aim for about two thirds of the original length" and a sentence after the text that restates the task.

Prompt v2, the recommended prompt (system message; the user message is `<text>\n…\n</text>`, with a closing tag inside the text escaped):

```text
You are the Polish step of a dictation app, not a coding assistant. The speaker dictated a prompt for an AI coding assistant, and the user message holds that text inside <text> tags. Your reply replaces the text, as is, in the assistant's input, and the assistant acts on it.

The text is almost always a question or an instruction for the coding assistant, not for you. Never answer it, do the task, write code for it or comment on it. Rewrite it.

Rewrite the text so it is shorter and clearer, with nothing lost:
- Keep every instruction, question, constraint, condition, reason, fact and example the speaker gave. When the speaker is unsure ("I think", "maybe"), keep the doubt.
- Keep every name, file name, path, identifier, command, slash command, flag, URL, number and version exactly, character for character.
- Cut repetition, filler, false starts, hedges that add nothing, and talk about the talking ("what I want to say is", "so basically").
- Say each point once: merge points the speaker made more than once. Group related points. Keep the order of steps where the order matters.
- Use short paragraphs. When the speaker lists three or more items or steps, write them as a "- " list. No headings, no bold, no code fences.
- Keep the speaker's voice: first person, their tone, their requests as requests. Do not add requests, facts, greetings or sign-offs.

Reply with the rewritten text only: no tags, no quotes, no notes, no preamble.

<examples>
<example>
<text>Okay so I want you to look at the the billing service, basically the webhook handler in src/billing/webhook.ts, because I think it's, I think it's double counting refunds. So what I want is, first, find where refunds are counted, and then, uh, write a failing test for the double count, and then fix it. And don't touch the Stripe client, the Stripe client is fine, don't change it. Oh and run bun test billing when you're done.</text>
Look at the webhook handler in src/billing/webhook.ts. I think it double counts refunds.

- Find where refunds are counted.
- Write a failing test for the double count.
- Fix it.

Don't change the Stripe client; it is fine. Run bun test billing when you're done.
</example>
<example>
<text>So I'm trying to figure out, like, should we move the queue from Redis to Postgres? Because right now we have this, we have this thing where jobs get lost when Redis restarts, and I think that's because we don't have persistence turned on, but I'm not sure. I don't want you to change anything yet. Just tell me what the options are and what you'd pick, and, yeah, keep in mind we're on Supabase, so we already have Postgres.</text>
Should we move the queue from Redis to Postgres? Jobs get lost when Redis restarts. I think that's because persistence is off, but I'm not sure.

Don't change anything yet. Tell me the options and which one you'd pick. Keep in mind we're on Supabase, so we already have Postgres.
</example>
</examples>
```

Request settings (OpenRouter `POST /chat/completions`, streaming, `provider.zdr: true`):

| Model | Settings |
| --- | --- |
| `deepseek/deepseek-v4.1-flash` (recommended) | `reasoning: {effort: "none"}`, `temperature: 0`, `provider.only: ["together"]`, `allow_fallbacks: false` |
| `google/gemini-3.5-flash-lite` (fallback) | `reasoning: {effort: "minimal"}` (lowest; mandatory), no temperature |
| `qwen/qwen3.8-27b` | `reasoning: {enabled: false}`, `temperature: 0`, pinned to Cerebras (9 HTTP 429s from Cerebras in this run, all retried) |
| `openai/gpt-oss-120b` | `reasoning: {effort: "low"}` (lowest; mandatory), pinned to Cerebras |
| `anthropic/claude-haiku-5.5` | `reasoning: {enabled: false}` |
| `anthropic/claude-sonnet-5.5` | `reasoning: {effort: "low"}`: reasoning is mandatory on every endpoint (`enabled: false` returns 400) |

## 5. Results

### 5.1 Prompt choice (dev)

All 25 dev inputs, judged. Latency from the concurrent pass (4 in flight).

| Model | Prompt | Items kept | Rows that lose an item | Lost items per row | Rows with added content | Word ratio p50 | Code tokens kept |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Gemini 3.5 Flash-Lite | v1 | 82.4% | 64.0% | 2.24 | 44.0% | 0.54 | 95.3% |
| | **v2** | **90.5%** | **48.0%** | **1.00** | **24.0%** | 0.69 | **98.1%** |
| | v3 | 86.9% | 60.0% | 1.40 | 24.0% | 0.60 | 96.2% |
| Qwen 3.8 27B (Cerebras) | v1 | 84.2% | 68.0% | 2.24 | 48.0% | 0.56 | 93.4% |
| | v2 | 83.1% | 72.0% | 2.20 | 32.0% | 0.54 | 92.5% |
| | v3 | 81.0% | 68.0% | 2.60 | 32.0% | 0.49 | 91.5% |
| gpt-oss-120b (Cerebras) | v1 | 83.1% | 68.0% | 2.32 | 32.0% | 0.57 | 90.6% |
| | v2 | 77.9% | 72.0% | 3.32 | 44.0% | 0.46 | 90.6% |
| | v3 | 78.6% | 80.0% | 3.12 | 60.0% | 0.49 | 91.5% |
| Claude Haiku 5.5 | v1 | 94.5% | 44.0% | 0.76 | 48.0% | 0.85 | 92.5% |
| | v2 | 93.2% | 52.0% | 1.04 | 44.0% | 0.83 | 92.5% |
| | v3 | 92.8% | 48.0% | 1.28 | 64.0% | 0.74 | 92.5% |
| Wispr Flow (reference) | | 84.3% | 60.0% | 1.56 | 56.0% | 0.69 | 89.6% |

v2 was picked: the largest gain (Gemini: 82.4% to 90.5% kept, lost items per row 2.24 to 1.00), fewer or equal rows with added content on 3 of 4 models, and v1 within noise of v2 on Qwen and Haiku. On gpt-oss, v1 keeps more than v2, but gpt-oss is out on quality either way. v3's length target cost preservation on 3 of 4 models. One Haiku v2 output answered the text (judge flag); no other dev output did.

### 5.2 Models (test sample, prompt v2)

40 test inputs, 10 per length quartile. Latency columns: the sequential pass (one request at a time) on the 23 sample inputs of 200-400 words, where it ran; Sonnet and unpinned DeepSeek from the concurrent pass.

| Model | Items kept | Rows that lose an item | Lost items per row | Items weakened | Rows with added content | Clarity (1-5) | Code tokens kept | Rows with a non-ASCII hyphen or space | Word ratio p50 | TTFT p50 (ms) | Total p50 / p90 (ms) | USD per 1,000 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **DeepSeek V4.1 Flash, Together** | **97.1%** | **22.5%** | **0.35** | 1.8% | **2.5%** | 4.88 | 96.9% | 0% | 0.78 | 457 | **1,057 / 1,334** | 0.34 |
| DeepSeek V4.1 Flash, any host | 95.3% | 25.0% | 0.65 | 2.6% | 10.0% | 4.83 | 96.9% | 0% | 0.77 | 876 | 1,851 / 8,605 | 0.37 |
| Claude Sonnet 5.5 (reasoning low) | 94.8% | 35.0% | 0.82 | 2.6% | 42.5% | 4.95 | 95.8% | 0% | 0.80 | 1,076 | 2,833 / 4,160 | 6.70 |
| Claude Haiku 5.5 | 90.4% | 40.0% | 1.75 | 4.1% | 37.5% | 4.85 | 92.1% | 0% | 0.81 | 955 | 2,180 / 2,858 | 0.33 |
| **Gemini 3.5 Flash-Lite** | 87.6% | 67.5% | 1.68 | 7.1% | 35.0% | 4.83 | 95.3% | 0% | 0.68 | 702 | 1,385 / 1,907 | 0.88 |
| Wispr Flow (reference) | 86.5% | 55.0% | 1.77 | 7.9% | 45.0% | 4.85 | 90.6% | 80.0% | 0.69 | - | Wispr's own: 1,334 / 1,977 | - |
| Qwen 3.8 27B, Cerebras | 81.7% | 67.5% | 2.88 | 9.1% | 37.5% | 4.90 | 93.7% | 0% | 0.55 | 521 | 704 / 1,320 | 1.35 |
| gpt-oss-120b, Cerebras | 75.6% | 82.5% | 3.55 | 13.1% | 47.5% | 4.83 | 92.1% | 62.5% | 0.49 | 498 | 616 / 955 | 0.51 |

- "Rows that lose a critical item" is not in the table: the checklist marked almost every item critical, so it tracks "rows that lose an item" within 5 points.
- The Wispr latency row is Wispr's `processingTime` for its gpt-oss rows of 200-400 words (n = 52), not a kotoba measurement.
- Clarity does not separate the models (4.83-4.95).
- DeepSeek per host, unpinned (total p50): Together 1.04 s (n = 7), PrimeIntellect 1.01 s, Relace 1.04 s (one call 12.5 s), CoreWeave 8.6 s (n = 5, max 22.8 s). The pinned Together run had no call over 1.45 s.
- Exact-token misses the judge also sees: Wispr and gpt-oss drop slash commands (Wispr dropped a `/grill-me` 9 times in 105 rows) and numbers (percentages, token counts). Qwen once replaced a misheard framework name with a different real framework (an added identifier).

## 6. Recommendation

- **Default:** `deepseek/deepseek-v4.1-flash`, prompt v2, `reasoning: {effort: "none"}`, `temperature: 0`, `provider: {zdr: true, only: ["together"], allow_fallbacks: false}`, streaming. It keeps the most of any model in the run, Sonnet included, adds the least, and is fast and steady when pinned (p90 1.33 s against the 2 s target). It cuts less than Wispr (0.78 against 0.69 of the input): for prompts to a coding agent, a lost constraint costs more than 9% more words.
- **Fallback (other vendor, same key):** `google/gemini-3.5-flash-lite`, prompt v2, `reasoning: {effort: "minimal"}`. Wispr-level preservation, Wispr-level length, p90 1.91 s. Use it when Together fails or is slow, or as the owner's choice for shorter output.
- **Do not use** gpt-oss-120b (Wispr's model): fastest, but it loses the most and writes U+2011 hyphens. Sonnet 5.5 keeps well but costs 20x and takes 2.8 s.
- One long-lived URLSession per provider applies: Polish goes to the same OpenRouter host as cleanup, so it can share that connection.

## Queries

Read-only, on `file:<runbooks>/2026-10-15-kotoba-bench/flow-copy.sqlite?immutable=1` (standing go of 2026-10-15), 2026-10-17 about 03:30 IST:

```sql
SELECT status, COUNT(*), ROUND(AVG(polishInitialWordCount)), ROUND(AVG(polishedWordCount)) FROM Polish GROUP BY 1;
SELECT instruction, COUNT(*) FROM Polish WHERE status = 'succeeded' GROUP BY 1;
SELECT modelVersion, usedProvider, promptName, COUNT(*), ROUND(AVG(processingTime), 2) FROM Polish WHERE status = 'succeeded' GROUP BY 1, 2, 3;
SELECT MIN(polishInitialWordCount), MAX(polishInitialWordCount), MIN(polishedWordCount), MAX(polishedWordCount) FROM Polish WHERE status = 'succeeded';
SELECT COUNT(DISTINCT polishInitialText) FROM Polish WHERE status = 'succeeded';
SELECT polishInitialWordCount, polishedWordCount, app, substr(createdAt, 1, 10) FROM Polish WHERE status = 'succeeded' ORDER BY createdAt;
SELECT polishInitialText, polishedText FROM Polish WHERE status = 'succeeded' AND polishInitialWordCount BETWEEN 250 AND 300 LIMIT 2;
-- the eval set (sqlite3 -json, to <runbooks>/2026-10-17-kotoba-polish/data/polish-pairs.json):
SELECT id, createdAt, app, polishInitialText AS input, polishedText AS wispr, polishInitialWordCount AS inWords,
       polishedWordCount AS outWords, processingTime AS wisprMs, json_extract(usedProvider, '$.model') AS wisprModel, instruction
FROM Polish WHERE status = 'succeeded' ORDER BY createdAt;
```

## How to rerun

From `bench/`, with the data folder in `KOTOBA_POLISH_DATA` and the key file in `KOTOBA_ENV_FILE`:

```sh
bun --env-file="$KOTOBA_ENV_FILE" polish/run.ts --set dev --versions 1,2,3 --models gemini-3.5-flash-lite,qwen3.8-27b@cerebras,gpt-oss-120b@cerebras,claude-haiku-5.5
bun --env-file="$KOTOBA_ENV_FILE" polish/judge.ts --set dev --sample 12 --variants <variants>,wispr
bun --env-file="$KOTOBA_ENV_FILE" polish/run.ts --set test --sample 40 --versions 2 --models <keys>
bun --env-file="$KOTOBA_ENV_FILE" polish/judge.ts --set test --sample 40 --variants <variants>,wispr
bun --env-file="$KOTOBA_ENV_FILE" polish/run.ts --set test --sample 40 --pass latency --versions 2 --models <keys>
bun polish/run.ts --only report     # results/report.md, from the raw files only
```

`--dry-run` prints the plan and estimate. The USD 1.50 cap spans `polish-raw.jsonl` and `judge-raw.jsonl`; `--cap USD` limits one run.

## Unresolved questions

1. Full Codex judge run for the owner's go: checklists on GPT-6.1 Sol and verdicts on GPT-6 Luna for all 105 inputs and every variant, about 170 Codex credits, about 30 min. It would cover all 80 test inputs and give a second judge. The 4 pilot jobs (2.38 credits) agreed in direction with the OpenRouter judge on the input they both scored.
2. Variance: each (model, input) ran once. Is DeepSeek's lead over Gemini stable over 3-5 samples? DeepSeek at `temperature: 0` and Gemini (which ignores temperature) can both vary.
3. Does the owner want DeepSeek's length (0.78 of the input) or Gemini's (0.68, closer to Wispr's 0.69)? The bench says "keeps more" against "cuts more"; only the owner can weigh it.
4. Together is one host. Should kotoba send `provider.order` with two or three fast DeepSeek hosts (Together, PrimeIntellect, Relace) and fallbacks on, instead of `only`? Not measured.
5. The examples turn numbered steps into "- " lists. Should the prompt keep "1." lists when the order matters? Not measured.
6. The input here is Wispr's text. kotoba's own transcripts (MAI or Grok, before or after cleanup) may differ in punctuation and errors; a rerun on kotoba history once it has long prompts would confirm.
