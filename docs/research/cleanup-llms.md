# Fast LLM APIs for transcript cleanup (kotoba)

Research date: 2026-10-15. Data captured on 2026-10-15, about 19:10 IST.
No account was made. No API key was used. No money was spent.

## 1. Task and method

- Workload: system prompt of 300-800 tokens (cacheable) plus a transcript of 150-400 tokens. Output is 100-300 tokens. We want the lowest time to the full response, and no reasoning tokens (or minimal).
- Speed and latency source: the Artificial Analysis (AA) API providers leaderboard, with Status set to "All" and "Expand Columns" on. https://artificialanalysis.ai/leaderboards/providers
  - Raw dump: `raw/llm/aa_providers_all_expanded.txt`. Parsed CSV (1,200 endpoint rows): `raw/llm/aa_providers_all.csv`. Parser: `scripts/parse_expanded.py`. Table builder: `scripts/table.py`.
  - The CSV column "current" is "yes" when the row also shows with AA's default "Status: Current" filter (`raw/llm/aa_providers.csv`).
- Model IDs, prices and reasoning switches come from each provider's own docs (links in each row and in section 7).

### What AA numbers mean (read before you use the table)

From https://artificialanalysis.ai/methodology/performance-benchmarking :

- The default workload on the website is about 10,000 input tokens. Our prompts are about 500-1,200 tokens. So our real TTFT can be lower than the AA value.
- "Time to First Token" is the first token of any kind. For models that stream reasoning, it is the first reasoning token. "Time to First Answer Token" is measured after thinking.
- The values are medians (P50) over the past 72 hours.
- The test server is in Google Cloud us-central1-a (Iowa, USA). TTFT includes network time from there.
- AA reasoning time comes from AA's benchmark prompts. A short cleanup task will usually reason for less time. This is an estimate, not a measurement.

### Formula

`est 250 tok (s) = AA first answer token (s) + 250 / AA output speed (tok/s)`

For reasoning models this includes AA's reasoning time, so it is a high (conservative) value for our task.

## 2. Candidate table

Price is USD per 1M tokens (input / output). "AA idx" is the AA Intelligence Index v4.3.2 (higher is better; `*` = AA estimate). IFBench is shown only where AA has a value. All AA values come from https://artificialanalysis.ai/leaderboards/providers unless a row says otherwise.

| # | Provider | Model id (docs) | Reasoning setting | AA tok/s | AA TTFT first chunk / first answer (s) | Price in / out | AA idx | IFBench | Est. 250 tok (s) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Cerebras | `gpt-oss-120b` ([docs](https://inference-docs.cerebras.ai/models/openai-oss)) | `reasoning_effort: "low"` (cannot turn off; default is medium) | 1,642 | 0.41 / 1.63 (reasoning 1.22) | $0.35 / $0.75 ([docs](https://inference-docs.cerebras.ai/models/openai-oss)) | 10* | 58% | **1.78** |
| 2 | Cerebras | `qwen-3.8-27b` ([docs](https://inference-docs.cerebras.ai/models/qwen-3.8-27b)) | `reasoning_effort: "none"` (default is high) | not on AA; vendor says ~1,850 | unconfirmed | $0.99 / $1.49 ([docs](https://inference-docs.cerebras.ai/models/qwen-3.8-27b)) | 20 (non-reasoning variant, other hosts) | not on AA | ~0.5-0.7, unconfirmed (0.135 s decode at vendor speed + unknown TTFT) |
| 3 | Groq | `openai/gpt-oss-20b` ([docs](https://console.groq.com/docs/models)) | `reasoning_effort: "low"` (low/medium/high only) | 951 | 0.76 / 2.86 (reasoning 2.10) | $0.075 / $0.30 ([docs](https://console.groq.com/docs/models)) | 10* | 58% | 3.12 |
| 4 | Groq | `openai/gpt-oss-120b` ([docs](https://console.groq.com/docs/models)) | `reasoning_effort: "low"` | 472 | 0.73 / 4.97 (reasoning 4.24) | $0.15 / $0.60 | 10* | 58% | 5.50 |
| 5 | Groq (Preview) | `qwen/qwen3.8-27b` ([docs](https://console.groq.com/docs/model/qwen/qwen3.8-27b)) | `reasoning_effort: "none"` ([docs](https://console.groq.com/docs/reasoning)) | not on AA; vendor says ~450+ | unconfirmed | $0.80 / $4.00 | 20 (non-reasoning variant, other hosts) | not on AA | ~1.2-1.5, unconfirmed |
| 6 | Google AI Studio | `gemini-3.5-flash-lite` ([docs](https://ai.google.dev/gemini-api/docs/models)) | `thinking_level: "minimal"` (this is the default) ([docs](https://ai.google.dev/gemini-api/docs/thinking)) | 438 | 7.06 / 7.06, but AA measured the reasoning version at an unstated level ([AA page](https://artificialanalysis.ai/models/gemini-3-5-flash-lite)) | $0.30 / $2.50 ([docs](https://ai.google.dev/gemini-api/docs/pricing)) | 22 | not on AA | 7.63 as measured; at minimal, ~1.0-1.5, unconfirmed |
| 7 | Google AI Studio | `gemini-3.1-flash-lite` (shutdown 2027-05-07, [docs](https://ai.google.dev/gemini-api/docs/deprecations)) | not in the thinking table; setting unconfirmed | 376 | 4.25 / 4.25 | $0.25 / $1.50 ([docs](https://ai.google.dev/gemini-api/docs/pricing)) | 16 | 77% | 4.91 |
| 8 | Google Vertex (Mumbai) | `gemini-3.5-flash` (in AI Studio this id now routes to `gemini-3.6-flash`, [docs](https://ai.google.dev/gemini-api/docs/deprecations)) | `thinking_level: "minimal"` | 186 (AI Studio row, AA "not current") | 0.80 / 0.80 | $1.50 / $9.00 (AA) | 24* | 47% | 2.14 |
| 9 | Anthropic | `claude-haiku-5-5` ([docs](https://platform.claude.com/docs/en/models/haiku-5-5/overview)) | AA: effort low, thinking on. Docs allow `thinking: {"type": "disabled"}` at effort high or below ([docs](https://platform.claude.com/docs/en/build-with-claude/thinking)) | 161 | 7.69 / 7.69 (thinking on) | $0.10 / $0.50 for prompts up to 100k ([docs](https://platform.claude.com/docs/en/models/haiku-5-5/overview)) | 29 (effort low) | not on AA | 9.24 with thinking; with thinking disabled ~2.0-2.3, unconfirmed |
| 10 | OpenAI | `gpt-6-luna` ([docs](https://developers.openai.com/api/docs/models/gpt-6-luna)) | `reasoning.effort: "none"` | 111 | 0.88 / 0.88 | $0.10 / $0.50 ([docs](https://developers.openai.com/api/docs/models/gpt-6-luna)) | 18 | not on AA | 3.13 |
| 11 | xAI | `grok-4.7` ([docs](https://docs.x.ai/developers/models/grok-4.7)) | lowest is `low` (low/medium/high/xhigh; no "none") | 64 | 3.87 / 3.87 | $2.00 / $6.00 ([docs](https://docs.x.ai/developers/models)) | 42 | not on AA | 7.78 |
| 12 | Mistral | `mistral-small-2603` (Mistral Small 4, [docs](https://docs.mistral.ai/models)) | non-reasoning mode | 146 | 1.07 / 1.07 | $0.15 / $0.60 (AA) | 9* | 33% | 2.78 |
| 13 | SambaNova | `gpt-oss-120b` | `reasoning_effort: "low"` | 740 | 1.20 / 3.90 (reasoning 2.70) | $0.22 / $0.59 (AA) | 10* | 58% | 4.24 |

Reference rows (outside the brief, or not open to a personal account):

| Provider | Model id | Setting | AA tok/s | AA TTFT (s) | Price in / out | AA idx | IFBench | Est. 250 tok (s) | Note |
|---|---|---|---|---|---|---|---|---|---|
| LithosAI | `deepseek-ai/DeepSeek-V4.1-Flash-ultra-chat` | non-reasoning | 1,218 | 0.58 | $0.35 / $1.40 | 25 | -- | 0.79 | Fastest measured row at a useful AA idx. A small provider; not checked. |
| Nebius | `Qwen/Qwen3.8-27B` (FP4) | non-reasoning | 370 | 1.39 | $0.45 / $3.00 | 20 | -- | 2.07 | AA proof point for Qwen 3.8 27B non-reasoning quality. |
| Groq | `llama-3.1-8b-instant` | none | 623 | 0.83 | $0.05 / $0.08 (AA) | 7* | 29% | 1.23 | Groq now lists it as "Enterprise, Contact Sales" ([docs](https://console.groq.com/docs/models)). |
| Google AI Studio | `gemini-2.5-flash-lite` | thinking off (default) | 304 | 0.31 | $0.10 / $0.40 (AA) | 7* | 31% | 1.13 | Access limited to past users ([docs](https://ai.google.dev/gemini-api/docs/models)). |
| Anthropic | `claude-haiku-4-5-20251001` | thinking off | 88 | 0.50 | $1.00 / $5.00 (AA) | 15* | 42% | 3.34 | Old model; shown as a TTFT reference for Haiku with thinking off. |

Cost per request (1,000 input + 250 output tokens, no cache, no reasoning tokens), from the prices above:
Groq gpt-oss-20b $0.00015; Haiku 5.5 and GPT-6 Luna $0.000225; Cerebras gpt-oss-120b $0.00054; Gemini 3.5 Flash-Lite $0.000925; Cerebras Qwen 3.8 27B $0.00136. At 200 dictations per day, all of these cost less than $0.30 per day. Price does not decide the choice.

## 3. Findings

1. Cerebras is the fastest measured host. `gpt-oss-120b` at low effort has the lowest measured end-to-end value in the brief list (1.78 s for 250 tokens, with AA's long reasoning included).
2. gpt-oss cannot turn reasoning off. On Groq and Cerebras the lowest value is `low` ([Groq](https://console.groq.com/docs/reasoning), [Cerebras](https://inference-docs.cerebras.ai/models/openai-oss)). Its quality score is low: AA idx 10*, IFBench 58%.
3. Qwen 3.8 27B can turn reasoning fully off (`reasoning_effort: "none"`) on Cerebras and Groq. Its non-reasoning AA idx is 20, which is 2x gpt-oss low. AA does not benchmark it on Cerebras or Groq ([AA](https://artificialanalysis.ai/models/qwen3-8-27b-non-reasoning/providers)), so its speed there is a vendor claim only.
4. Gemini 3.5 Flash-Lite has the right default (`minimal` thinking) and high speed (438 tok/s). But the AA TTFT (7.06 s) is for the reasoning version at an unknown level. We must measure it at `minimal`.
5. Haiku 5.5 and GPT-6 Luna are cheap and good, but slow per token (161 and 111 tok/s). Each needs about 1.5-2.3 s for 250 tokens even with thinking off.
6. Grok 4.7 has no "none" setting and is slow (64 tok/s). Drop it.
7. Mistral Small 4 and SambaNova add nothing over Cerebras or Groq here.

## 4. Network from India

AA measures from Iowa. From India, a warm (kept-alive) HTTPS connection adds about one extra round trip (RTT). A cold connection adds about two more RTTs for TCP and TLS. So keep one connection open, and open it when recording starts.

RTT from Mumbai, median of 336 hourly runs, 2026-10-01 to 2026-10-15 (computed by `scripts/pings.py` from `raw/llm/ping_mumbai_*.html`):

| To | Median RTT (ms) | Source |
|---|---|---|
| New York | 185 | https://wondernetwork.com/pings/Mumbai/New%20York |
| Chicago | 199 | https://wondernetwork.com/pings/Mumbai/Chicago |
| Dallas | 258 | https://wondernetwork.com/pings/Mumbai/Dallas |
| San Jose | 245 | https://wondernetwork.com/pings/Mumbai/San%20Jose |
| Frankfurt | 142 | https://wondernetwork.com/pings/Mumbai/Frankfurt |
| Helsinki | 170 | https://wondernetwork.com/pings/Mumbai/Helsinki |
| Riyadh | 159 | https://wondernetwork.com/pings/Mumbai/Riyadh |
| Singapore | 154 (but 58-69 ms in the last 6 runs; the route changed) | https://wondernetwork.com/pings/Mumbai/Singapore |
| Sydney | 295 | https://wondernetwork.com/pings/Mumbai/Sydney |

These are one host pair per city. Your ISP path can differ.

Per provider:

- **Groq**: no India data center. A Groq community post says so (undated) ([link](https://community.groq.com/t/can-i-get-the-models-to-be-hosted-inside-of-india-regeion/190/2)). Groq has a site in Sydney (search summary of [DCD](https://www.datacenterdynamics.com/en/news/groq-deploys-ai-infrastructure-in-data-center-in-sydney-australia/); page returned 403, so unconfirmed) and reports 13 data centers in North America, Europe, the Middle East and APAC (search summary of [The Tech Capital](https://thetechcapital.com/groq-raises-650-million-to-scale-ai-inference-cloud/), unconfirmed). Groq picks the data center. The response header `x-groq-region` tells you which one served the request ([docs](https://console.groq.com/docs/production-readiness/optimizing-latency)). Log it.
- **Cerebras**: no Asia data center. The first European capacity comes online by end of 2026 ([press release](https://cerebras.gcs-web.com/news-releases/news-release-details/cerebras-systems-accelerates-european-expansion-200mw-ai-compute), search summary). India and Singapore are only "pursued" opportunities (search summary of [Zacks](https://www.zacks.com/stock/news/2951704/cbrs-european-expansion-strengthens-ai-growth-story-whats-ahead), unconfirmed). Expect a US round trip (~185-260 ms).
- **Google**: on Vertex AI, Mumbai (`asia-south1`) serves `gemini-3.5-flash` and `gemini-2.5-flash`, but not `gemini-3.5-flash-lite`, `gemini-3.8-flash` or any Flash-Lite model. Claude Haiku 5.5 and gpt-oss on Vertex are not in any APAC region in the table ([Vertex locations](https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/locations); parsed by `scripts/vertex_apac.py`). The AI Studio (Gemini Developer API) serving region is not stated (unconfirmed).
- **Anthropic**: Amazon Bedrock has an India cross-region profile (Mumbai and Hyderabad) for Claude Opus 5, Sonnet 5 and Haiku 4.5, not Haiku 5.5 ([CRN Asia](https://www.crnasia.com/india/news/2026/anthropic-takes-claude-inference-live-in-india-opens-path-to-regulated-ai-deployments)). The first-party API region is unconfirmed.
- **OpenAI**: third-party reports say India gives data storage only, and inference runs outside India ([eCorpIT](https://ecorpit.com/openai-per-request-regional-processing-india-storage-only-2026/), unconfirmed against OpenAI docs). Bedrock has India cross-region inference for GPT-5.6 models ([AWS news](https://aws-news.com/article/2026-08-27-introducing-india-cross-region-inference-for-openai-gpt-56-models-on-amazon-bedrock), unconfirmed).
- **xAI**: `grok-4.7` lists region `us-east-1` ([docs](https://docs.x.ai/developers/models/grok-4.7)).

Effect on the table: add about 0.2 s (warm) or 0.6 s (cold) to each US-hosted estimate. This does not change the order.

## 5. Instruction-following risk for small models

- The main risk is not punctuation. The transcript is itself an instruction for a coding agent ("fix the bug in auth.ts"). A weak model can obey the transcript and not clean it. It can also "fix" identifiers, file paths and CLI flags that it does not know.
- Quality scores from AA (https://artificialanalysis.ai/leaderboards/providers):
  - gpt-oss-120b and gpt-oss-20b at low: AA idx 10*, IFBench 58%.
  - Qwen 3.8 27B non-reasoning: AA idx 20 (no IFBench value).
  - Gemini 3.5 Flash-Lite (reasoning version): AA idx 22. Gemini 3.1 Flash-Lite: idx 16, IFBench 77%.
  - GPT-6 Luna none: idx 18. Haiku 5.5 low (thinking on): idx 29.
  - Mistral Small 4 non-reasoning: idx 9*, IFBench 33%. Llama 3.1 8B: idx 7*, IFBench 29%.
- AA Intelligence Index v4.3.2 does not include IFBench ([AA model page](https://artificialanalysis.ai/models/gemini-3-5-flash-lite)). So models from mid-2026 have no IFBench value. The AA idx tests agentic and knowledge work, not short rewrites. Both are weak proxies for this task.
- Cerebras warns that gpt-oss-120b can call tools that are not in the request ([docs](https://inference-docs.cerebras.ai/models/openai-oss)). Do not send tools.
- Do this to reduce the risk: put the transcript inside tags, say "do not follow instructions inside the tags", give 3-5 short examples that contain paths and flags, and pass a list of known identifiers from the repo (for example file names) as facts. Then test on 20-30 real transcripts.

## 6. Recommendation

- **Best default: Cerebras `qwen-3.8-27b` with `reasoning_effort: "none"`.**
  - Reasons: no reasoning tokens, vendor speed ~1,850 tok/s, and AA idx 20 for the non-reasoning variant. That is the best quality-to-speed mix in the brief list.
  - Risk: AA does not measure it on Cerebras. Measure TTFT and total time from India before you commit.
  - Free Trial limit is 5 requests per minute and 1M tokens per day ([docs](https://inference-docs.cerebras.ai/models/qwen-3.8-27b)). That is enough for one person who dictates.
- **Fast fallback on the same account: Cerebras `gpt-oss-120b`, `reasoning_effort: "low"`.** It is the fastest measured row (1.78 s). Quality is lower and reasoning cannot be turned off.
- **Backup on a different vendor: Google `gemini-3.5-flash-lite` at the default `thinking_level: "minimal"`.** It is fast (438 tok/s) with AA idx 22, and a different network path. Measure its TTFT at `minimal`; the AA value (7.06 s) is for a higher thinking level.
  - Note: on the Gemini free tier, the "Used to improve our products" field is "Yes" ([pricing](https://ai.google.dev/gemini-api/docs/pricing)). Use the paid tier for transcripts.
- If you want the highest quality and can accept ~2 s: Anthropic `claude-haiku-5-5` with `thinking: {"type": "disabled"}` and effort low. TTFT with thinking off is unconfirmed.
- Do not use: `grok-4.7` (no "none", 64 tok/s), Groq `gpt-oss-120b` (slow first answer on AA), Mistral Small 4 (low IFBench).

## 7. Sources

- AA providers leaderboard: https://artificialanalysis.ai/leaderboards/providers
- AA methodology: https://artificialanalysis.ai/methodology/performance-benchmarking
- AA Gemini 3.5 Flash-Lite: https://artificialanalysis.ai/models/gemini-3-5-flash-lite
- AA Qwen3.8 27B (non-reasoning) providers: https://artificialanalysis.ai/models/qwen3-8-27b-non-reasoning/providers
- Groq models: https://console.groq.com/docs/models
- Groq reasoning: https://console.groq.com/docs/reasoning
- Groq Qwen 3.8 27B: https://console.groq.com/docs/model/qwen/qwen3.8-27b
- Groq latency guide: https://console.groq.com/docs/production-readiness/optimizing-latency
- Cerebras models: https://inference-docs.cerebras.ai/models/overview
- Cerebras gpt-oss-120b: https://inference-docs.cerebras.ai/models/openai-oss
- Cerebras qwen-3.8-27b: https://inference-docs.cerebras.ai/models/qwen-3.8-27b
- Gemini models: https://ai.google.dev/gemini-api/docs/models
- Gemini pricing: https://ai.google.dev/gemini-api/docs/pricing
- Gemini thinking: https://ai.google.dev/gemini-api/docs/thinking
- Gemini deprecations: https://ai.google.dev/gemini-api/docs/deprecations
- Vertex AI locations: https://docs.cloud.google.com/gemini-enterprise-agent-platform/resources/locations
- Anthropic models: https://platform.claude.com/docs/en/models/overview
- Claude Haiku 5.5: https://platform.claude.com/docs/en/models/haiku-5-5/overview
- Anthropic effort: https://platform.claude.com/docs/en/build-with-claude/effort
- Anthropic thinking: https://platform.claude.com/docs/en/build-with-claude/thinking
- OpenAI models: https://developers.openai.com/api/docs/models
- GPT-6 Luna: https://developers.openai.com/api/docs/models/gpt-6-luna
- OpenAI Fast mode: https://developers.openai.com/api/docs/guides/fast-mode
- xAI models: https://docs.x.ai/developers/models
- xAI Grok 4.7: https://docs.x.ai/developers/models/grok-4.7
- Mistral models: https://docs.mistral.ai/models
- WonderNetwork pings: https://wondernetwork.com/pings/Mumbai/ (city pages listed in section 4)

## 8. Unresolved questions

1. What are the TTFT and output speed of Cerebras `qwen-3.8-27b` and Groq `qwen/qwen3.8-27b` with reasoning "none"? AA does not measure them. A short test from India is the only way to know.
2. What is the TTFT of `gemini-3.5-flash-lite` at `minimal`? Which thinking level did AA use for its row?
3. What is the TTFT of `claude-haiku-5-5` with thinking disabled? AA measures only thinking-on levels.
4. How many reasoning tokens does gpt-oss at `low` use on a 300-token cleanup? AA's 1.2-4.2 s of reasoning comes from benchmark prompts.
5. Which Groq data center serves a request from India (`x-groq-region`)? Is the Sydney or Middle East site used?
6. Does GPT-6 Luna support Fast mode (2x price), and how much faster is it? The Luna page lists Fast as a tier, but no speed number.
7. SambaNova's model docs returned HTTP 403. Its current model list is unconfirmed.
8. The Groq Sydney, Groq 13-site, Cerebras Asia, and OpenAI India-processing claims come from search summaries. I did not open the full pages.
