# Languages and Hinglish

Date: 2026-10-16 (research at 00:30-00:55 IST). Scope: which languages MAI-Transcribe-2, Grok STT and Wispr Flow support; how to stop a transcript in the wrong language; how to get Hinglish (code-switched Hindi and English in Latin script). Web docs only, plus a local read of the kotoba-bench-v1 files. No API calls, no sign-ups.

## Summary

- Neither MAI-Transcribe-2 nor Grok takes a list of allowed languages. Each takes one language or auto-detect. kotoba must make the "picked list" itself: force the language when one is picked; when more are picked, auto-detect, then check the detected language and the script.
- No source says that MAI or Grok writes Hinglish in Latin script. MAI names Hinglish code-switching but not the output script. Only Sarvam Saaras v4 (`mode: "translit"`) documents romanized output. Wispr Flow does it, but only when the user picks "Hinglish" by hand.
- kotoba-bench-v1 sent `language: "en"` on every request (`bench/stt.ts:192`). All its numbers (MAI WER 8.1%) are for forced English. Auto-detect on the owner's English is not measured.
- Recommended v1: English (default), Hinglish (Latin script) and Hindi (Devanagari) as the owner's languages; 19 more languages in the picker that pass a published per-language bar (table below). Hinglish route: benchmark MAI auto-detect against Sarvam `translit` on 30 of the owner's clips, then pick. Cost of the benchmark: about $0.35, under 10 minutes of run time.
- Synthetic Hinglish bench (2026-10-16, section below): MAI writes Hindi words in Devanagari and English words mostly in Latin, also with `language: "en"`. The words are right (romanized WER about 4%), only the script is wrong. Grok with auto-detect writes Urdu script. Proposed route: MAI with `en`, then a local Devanagari-to-Latin step. Sarvam `translit` is still untested.

## 1. Language support per provider

### MAI-Transcribe-2 (Azure direct)

| Item | Value | Source |
| --- | --- | --- |
| Languages | 60. Default is "multilingual mode". | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe |
| Language parameter | `locales`: "Allows forcing transcription in a specific language. This is a very strong hint to the model ... Only one language can be provided here." Default: automatic detection. | same |
| Allowed-language list | No. One locale or none. | same |
| Code-switching | Automatic: "For commonly blended language pairs such as Hinglish and Spanglish, handles conversations that move between languages mid-utterance." Output script for Hinglish: not stated. | same |
| Detected language in response | Each phrase has `locale` (model card sample: `"locale": "en"`). With `timestamps: "segment"`, segments split "by language". | https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf , https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe |
| Accuracy | FLEURS average WER 5.2% across 60 languages, the same with forced and inferred language (model card chart). No per-language number for v2. | https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf , https://microsoft.ai/news/mai-transcribe-2 |
| Per-language proxy | MAI-Transcribe-1 card has per-language FLEURS WER for 25 languages (table below). v2 is the same family with a lower average; use v1 only as a lower bound on quality. | https://microsoft.ai/pdf/MAI-Transcribe-1-Model-Card.pdf |

MAI-Transcribe-2 language codes: af, ar, as, az, bg, bn, bs, ca, cs, da, de, el, en, es, et, fa, fi, fil, fr, gl, gu, he, hi, hu, hy, id, is, it, ja, kk, kn, ko, lt, lv, mk, ml, mr, ms, nb, ne, nl, or, pa, pl, pt, ro, ru, sk, sl, sv, sw, ta, te, th, tr, uk, ur, vi, yue, zh. https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe

### MAI-Transcribe-2 through OpenRouter

- Top-level `language`: "ISO-639-1 language code (e.g., "en", "ja"). Auto-detected if omitted." One code only. https://openrouter.ai/docs/guides/overview/multimodal/stt
- How `language` maps to Azure `locales` is not documented. Azure forwards "most fields as-is", so `provider.options.azure.locales: ["hi"]` should also work. **Not confirmed.** Same source.
- Detected language comes back in `language` "only with `verbose_json`". OpenRouter says `microsoft/mai-transcribe-1.5` rejects `verbose_json`; for v2 it does not say. **Not confirmed.** Same source.

### Grok STT (xAI)

| Item | Value | Source |
| --- | --- | --- |
| Languages | "38+". Listed: ar, bs, bg, yue, ca, zh, hr, cs, da, nl, en, fil, fi, fr, de, el, hi, hu, id, it, ja, ko, mk, ms, nb, fa, pl, pt, ro, ru, sk, es, sv, th, tr, uk, ur, vi. | https://docs.x.ai/developers/model-capabilities/audio/speech-to-text |
| Language parameter | `language`, one code, optional. "Biases transcription toward that language and selects the formatting rules for `format=true`." Regional codes for es, pt, ar (`es` = es-MX, `pt` = pt-BR). | same |
| Allowed-language list | No. | same |
| Code-switching | Auto-detects and "follows switches partway through a recording". With `language` set, "the model leans toward that language when the audio is ambiguous". Hinglish: not named. | same |
| `format=true` (ITN) | Needs `language`; works for 11 languages (ar, zh, en, fr, de, ja, pt, ru, es, sv, vi). Hindi: no effect. | same |
| Detected language in response | `language`, BCP-47. | same |
| Per-language accuracy | Not published. AA reports English only (2.7% streaming WER). | https://www.datacamp.com/blog/grok-voice-transcribe-2-0 |
| On OpenRouter | Only `x-ai/grok-stt-1.0`; whether it serves 2.0 is unknown. | `docs/research/benchmark-sources.md` |

### Wispr Flow (reference)

- "100+ languages"; 7 "trained and tuned to match English-level performance": French, German, Hindi, Italian, Portuguese, Spanish, Thai. https://wisprflow.ai/post/supporting-languages
- Picker: Auto-detect, or a set of picked languages. "Flow detects one language per dictation, not per word." "Selecting languages narrows what Flow can choose from; selecting just one tells Flow to use that language." https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages
- Hinglish: "Writes Hindi in Latin letters and formats English normally." It "must be selected manually. Flow does not detect it automatically, and selecting Hindi plus English does not produce Latin-script Hindi." Hindi and Hinglish are one variant group: picking one replaces the other. Same source.
- Wrong-language guard: "accent confidence scoring"; a "Speaking a different language?" notice at most once a day; Hindi/Urdu and Russian/Ukrainian get a "double-check". Same two sources.
- Wispr calls romanized Hinglish an "ongoing code-mixing experiment". https://wisprflow.ai/post/supporting-languages
- Local evidence: 1 of the owner's 275 exported Wispr clips has a Devanagari word inside English text. MAI with `language: "en"` wrote that clip in English words only. Source: `<runbooks>/2026-10-15-kotoba-bench/manifest.json` and `results/stt-raw.jsonl`.

### kotoba-bench-v1 script check (local, no cost)

Count of outputs that contain any non-Latin letter, from `results/stt-raw.jsonl`: 0 of 252 clips for each of the 7 variants (mai, mai+phraseList, mai+clean, grok, grok+keyterms, grok+keyterms+format, grok+keyterms+fillers). Every request had `language: "en"`. So forced English gave no wrong script on the owner's Indian-English speech. Auto-detect is not measured.

## 2. Recommended v1 language list

Bar for the picker: published per-language FLEURS WER of 5.0% or lower for MAI-Transcribe-1 (the only per-language MAI data), and in Grok's list (so the fallback route has the language).

| Code | Language | MAI-1 FLEURS WER | Scribe v2 (same table) | In Grok list |
| --- | --- | --- | --- | --- |
| it | Italian | 1.2% | 1.3% | yes |
| ja | Japanese | 1.9% | 2.3% | yes |
| pl | Polish | 2.1% | 3.8% | yes |
| es | Spanish | 2.2% | 2.7% | yes |
| pt | Portuguese (BR) | 2.5% | 3.2% | yes |
| en | English | 2.7% | 2.7% | yes |
| de | German | 2.7% | 3.5% | yes |
| fr | French | 3.0% | 3.6% | yes |
| id | Indonesian | 3.0% | 2.9% | yes |
| ro | Romanian | 3.4% | 2.9% | yes |
| ru | Russian | 3.4% | 4.4% | yes |
| nl | Dutch | 3.5% | 3.9% | yes |
| ko | Korean | 3.6% | 3.3% | yes |
| vi | Vietnamese | 3.9% | 3.7% | yes |
| cs | Czech | 4.0% | 4.3% | yes |
| hi | Hindi | 4.0% | 10.2% | yes |
| tr | Turkish | 4.3% | 4.0% | yes |
| zh | Chinese | 4.5% | 5.6% | yes |
| sv | Swedish | 4.6% | 4.9% | yes |
| th | Thai | 4.6% | 6.3% | yes |
| fi | Finnish | 4.7% | 3.2% | yes |

Source for all numbers: "Raw WER Data" table, https://microsoft.ai/pdf/MAI-Transcribe-1-Model-Card.pdf (page 2). Vendor-measured. The card does not say whether ja, zh and th use WER or CER.

Out of v1: nb 5.2%, hu 5.3%, da 6.2%, ar 10.1% (same table), and the 35 languages that are new in MAI-2 (all other Indian languages included), because no per-language number is published for them.

Proposal for the owner:
- Default set: English only. That keeps today's behavior (forced `en`) and today's benchmark numbers.
- Owner's own entries: English, Hinglish (Latin script), Hindi (Devanagari). Hinglish and Hindi are one variant group, as in Wispr.
- The 20 other languages in the table are pickable but not tested by us.

How kotoba keeps "nothing in the wrong language":
1. One language picked: force it (`locales: [code]` on Azure, `language` on Grok and OpenRouter).
2. More than one picked: send no language. After the response, check (a) the detected language (MAI `phrases[].locale`, Grok `language`, OpenRouter `language` with `verbose_json`) and (b) the script of every letter against the scripts of the picked languages. On a miss, send the request again with the first picked language forced. This adds one request (MAI p50 881 ms in kotoba-bench-v1) only on a miss.
3. Hinglish is never auto-detected (Wispr does the same). Picking it selects the Hinglish route below.

## 3. Hinglish

### What each option gives

| Option | Romanized output | Evidence | Price | Latency fit (1 s gate) |
| --- | --- | --- | --- | --- |
| MAI-Transcribe-2, auto-detect | Unknown. Code-switching for Hinglish is documented; script is not. | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe | $0.10/h promo to 2026-12-31 | Same as today |
| Grok STT, auto-detect | Unknown. Hinglish not named. | https://docs.x.ai/developers/model-capabilities/audio/speech-to-text | $0.10/h batch (xAI post) https://x.ai/news/grok-stt-and-tts-apis | Slower than MAI in kotoba-bench-v1 |
| Sarvam Saaras v4, `mode: "translit"` | Yes, documented: "mera phone number hai 9840950950"; Sarvam calls it "WhatsApp language". `codemix` gives "मेरा phone number है" (mixed script). | https://docs.sarvam.ai/api/api-guides-tutorials/speech-to-text/how-to/select-output-mode.md , https://www.sarvam.ai/blogs/introducing-saaras-v4 | ₹0.49/min pay-as-you-go = ₹29.40/h (about 3x MAI's promo price; USD not listed) | Unknown. REST takes at most 30 s audio per request; longer needs chunks or the streaming API. Streaming first token "below 150 ms" (vendor). |
| MAI or Grok, then local transliteration | Partial. macOS ICU transforms (Foundation `StringTransform`) give ISO 15919 with diacritics ("mērā"), not casual Hinglish; schwa deletion is not mentioned. AI4Bharat IndicXlit has a Devanagari-to-Roman model (~11M parameters, word level, Python/fairseq; a CTranslate2 port exists). | https://unicode-org.github.io/icu/userguide/transforms/general/ , https://ai4bharat.iitm.ac.in/?p=1121 , https://pypi.org/project/ai4bharat-transliteration/ , https://huggingface.co/Singla0009/all-indic-transliteration | Free | ICU: under 1 ms (expected, not measured). IndicXlit needs a Core ML port and adds idle memory; not measured. |
| MAI or Grok, then a small LLM | Yes, if the prompt is followed | `docs/research/cleanup-llms.md`: Cerebras and Groq have no India data center; estimate ~0.5-0.7 s per call | Cents per thousand calls | Fails the gate: 881 ms + ~500 ms or more. Fit for the cleanup hotkey only. |
| gpt-transcribe with `languages: ["hi","en"]` and `prompt` | Unknown; prompt is "unstructured context" | https://developers.openai.com/api/docs/guides/speech-to-text | $0.27/h on OpenRouter (`docs/research/benchmark-sources.md`) | Inference in US/EU (`docs/research/stt-vendors.md`) |
| ElevenLabs Scribe v2 | No script option in the API; `language_code` is one code | https://elevenlabs.io/docs/api-reference/speech-to-text/convert | $0.11/h on OpenRouter | n/a |
| Deepgram Nova-3, `language=multi` | Deepgram itself says to "add a transliteration step" for consistent romanized output | https://deepgram.com/learn/hinglish-voice-ai-speech-recognition | $0.258/h on OpenRouter | n/a |
| Gladia Solaria, `code_switching` + `languages` list | Script not documented. Gladia is the only vendor found with a true allowed-language list. | https://docs.gladia.io/chapters/language/code-switching | not checked | n/a |

### Third-party benchmarks (none cover MAI-2 or Grok on Hinglish)

- Trelis (2026), code-switched Hindi-English WER: Sarvam Saaras v3 11.25 on CoSHE-500 (conversational) vs Scribe v2 12.40; Scribe v2 7.57 on Code-Switch FLEURS hi-en (read) vs Sarvam 16.47. Reference script not stated; Sarvam run in code-mixed mode. https://huggingface.co/Trelis/tara
- Josh Talks "Voice of India" (August 2026), Hindi OI-WER on telephone speech: Saaras v3 3.8, Gemini 3 Pro 4.7, Scribe v2 5.9, Microsoft Speech-to-Text 7.6, Deepgram Nova-3 9.5. MAI is not in it. Scribe v2 wrote code-mixed English words in other scripts (Russian, Chinese, Korean, Japanese, Thai) in 0.14% of segments. https://elevenlabsreport.ai.joshtalks.com/ , https://arxiv.org/pdf/2604.19151
- Deepgram: "Hinglish WER ranges from 26.97% to 69.53%" across six unnamed models on the same audio. https://deepgram.com/learn/hinglish-voice-ai-speech-recognition
- Sarvam (vendor): language-ID error 5.22% across 22 Indian languages, 2.9% across the top ten. https://www.sarvam.ai/blogs/introducing-saaras-v4

### Recommended Hinglish route

1. First test MAI auto-detect on the owner's Hinglish clips (no new vendor, no new key). If the Hindi words come back in Latin script with acceptable WER, Hinglish is only "MAI with no `locales`".
2. If MAI writes Devanagari (the likely case; no source shows otherwise), use Sarvam `saaras:v4` with `mode: "translit"` as the Hinglish-only provider. It is the only documented romanized output, and it takes 50 keyterms (the owner's dictionary has 36). It needs its own key (direct API; not on OpenRouter) and a fix for the 30 s REST limit.
3. Do not put an LLM transliteration step on the hot path. Keep it as an option on the cleanup hotkey.

## 4. Phrase list with a non-English language set

- MAI `phraseList`: the docs tie it to no language. Azure's phrase-list page says allowed characters "include locale-specific letters", and the phrase list works with "Fast transcription API" and "LLM Speech transcription API"; "a phrase list shouldn't have more than 2,000 phrases". Its example pairs it with `locales: ["en-US"]`; the MAI example has no `locales`. So it should work with auto-detect and other languages. **Not confirmed for MAI by any test.** https://learn.microsoft.com/en-us/azure/ai-services/speech-service/improve-accuracy-phrase-list , https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- Grok `keyterm`: docs say nothing about language. **Unknown.** https://docs.x.ai/developers/model-capabilities/audio/speech-to-text
- Sarvam `keyterms`: `saaras:v4` only, "Up to 50 terms, 64 characters each". Behavior in `translit` mode not stated. https://docs.sarvam.ai/api/api-guides-tutorials/speech-to-text/rest-api
- Others for reference: Deepgram keyterms work with `language=multi` (up to 100) https://deepgram.com/learn/hinglish-voice-ai-speech-recognition ; ElevenLabs up to 1000 keyterms, +20% surcharge https://elevenlabs.io/docs/api-reference/speech-to-text/convert
- Risk to test: an English term list may pull a Hinglish clip toward English words. The benchmark below has a with/without variant for this.

## 5. Benchmark plan (not run; needs the owner's go)

### Data

| Set | Clips | Source | Reference |
| --- | --- | --- | --- |
| H: Hinglish | 30, 10-30 s each (30 s cap for Sarvam REST) | New recordings by the owner, real dictation style (Slack, WhatsApp, prompts). The 275-clip Wispr export has no Hinglish clips (local check: 0 clips with romanized Hindi words). A read-only Wispr history query for more is possible. | Owner types the romanized text they want, in the review page (`bench/review/`) |
| D: Hindi | 10 (optional) | New recordings | Devanagari |
| E: English guard | 40 | The existing seeded 10-20 s latency clips from kotoba-bench-v1 | Existing references |

### Variants

- Set H: `mai` (no language), `mai+phraseList` (no language), `mai` with `provider.options.azure.locales: ["hi"]`, `grok` (no language), `grok` with `language: "hi"`, Sarvam `saaras:v4` `translit`, Sarvam `codemix`. Optional: `openai/gpt-transcribe` with `languages: ["hi","en"]` and a prompt. On each Devanagari output, also score ICU transliteration (local, free).
- Set E: `mai` with no language vs `mai` with `language: "en"`; `grok` the same. This measures what auto-detect costs on English (WER, wrong-language rate).
- Latency pass: sequential, 20 clips from set H, `mai`, `grok`, Sarvam `translit`.

### Metrics

- WER on romanized text after a Hinglish normalizer (lowercase, no punctuation, fold common spelling variants such as hai/he, nahi/nahin, kya/kia, double vowels), plus CER.
- Script purity: share of non-Latin letters in set H output (target 0).
- Wrong-language rate on set E: clips with a detected language or a script outside {en, Latin} (target 0 of 40).
- Term recall with and without the phrase list.
- Latency p50/p90 from stop to text, sequential.

### Harness changes (agent work, about half a day)

- A `language` option per variant (today `bench/stt.ts:192` sends `language: "en"` on every request).
- A Sarvam adapter (direct `POST https://api.sarvam.ai/speech-to-text`, `api-subscription-key` header). Sarvam key from the owner; load with `bun --env-file`.
- Hinglish normalizer and script-purity metric in `score.ts`; `verbose_json` to get the detected language.

### Cost and duration

| Item | Audio | Price | Cost |
| --- | --- | --- | --- |
| Set H, 5 OpenRouter variants (MAI, Grok) | 30 x ~20 s = 10 min each | $0.10/h | ~$0.09 |
| Set H, 2 Sarvam variants | 10 min each | ₹0.49/min | ~₹10 (about $0.11 at ₹88/$, assumed rate) |
| Set H, gpt-transcribe (optional) | 10 min | $0.27/h | ~$0.05 |
| Set E, 4 variants | 40 x ~15 s = 10 min each | $0.10/h | ~$0.07 |
| Latency pass, 3 variants x 20 clips | ~7 min each | as above | ~$0.03 + ~₹3 |
| Total | | | about $0.35; cap $1 |

- Owner time: about 45 minutes to record 30-40 clips and type references.
- Run time: accuracy pass under 3 minutes; sequential latency pass about 2 minutes (60 requests at ~1-2 s).
- Sarvam needs a sign-up by the owner (free credits on sign-up; amount not stated). https://www.sarvam.ai/api-pricing

## Synthetic Hinglish bench

Run: 2026-10-16, 01:11-01:15 IST. Owner's go at 01:11 IST. Harness: `bench/hinglish/` (`bun run hinglish`). Data and raw rows are in the runbooks folder `2026-10-16-kotoba-hinglish/`, not in git.

### Set-up

- TTS: OpenRouter `/audio/speech`, `google/gemini-3.8-flash-lite-tts`, voices Kore, Aoede and Puck, 24 kHz PCM (Gemini TTS rejects `mp3`). Listed price: $6 per 1M audio tokens at 25 tokens/s, so $0.54 per audio hour.
- Texts: 30 Hinglish developer texts (prompts to agents, Slack messages) and 10 Hindi texts, in `bench/hinglish/texts.ts`. The TTS read Hindi words in Devanagari and English words in Latin script. Each text was spoken in 3 voices: 120 clips, 18.7 min of audio, clip length 7.4-10.8 s (p50 9.4 s).
- References: romanized Hinglish for set H, Devanagari for set D.
- STT variants on OpenRouter: `mai+auto` (no `language`), `mai+hi` (`language: "hi"`), `grok+auto` (no `language`), `mai` (`language: "en"`, today's setting).
- Metrics: share of letters by script; WER after Hinglish spelling folds (a Devanagari word against a romanized reference is an error); "romanized WER", which romanizes both sides first with ICU Devanagari-Latin and simple schwa and spelling rules (approximate); latency in the accuracy pass (16 requests in flight) and in a sequential pass (20 Hinglish clips x 4 variants).

### Results

Set H, Hinglish (90 clips):

| Variant | Latin letters | Devanagari letters | Urdu (Arabic) letters | Clips with Devanagari | WER | Romanized WER (approx.) | Sequential latency p50 / p90 ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| mai+auto | 55.3% | 44.7% | 0.0% | 90 | 70.9% | 4.6% | 1023 / 1047 |
| mai+hi | 54.6% | 45.4% | 0.0% | 90 | 71.2% | 4.8% | 1017 / 1053 |
| grok+auto | 17.4% | 60.4% | 22.2% | 70 | 92.7% | 39.6% | 814 / 982 |
| mai (en) | 57.9% | 42.1% | 0.0% | 90 | 69.5% | 3.8% | 1018 / 1118 |

Set D, Hindi (30 clips):

| Variant | Devanagari letters | Urdu (Arabic) letters | WER | Romanized WER (approx.) |
| --- | --- | --- | --- | --- |
| mai+auto | 100.0% | 0.0% | 2.1% | 2.1% |
| mai+hi | 100.0% | 0.0% | 2.1% | 2.1% |
| grok+auto | 50.0% | 50.0% | 53.8% | 53.8% |
| mai (en) | 95.4% | 0.0% | 5.5% | 3.0% |

Findings:

1. No variant gives romanized Hinglish. MAI writes every Hindi word in Devanagari and most English words in Latin script, even with `language: "en"`. Sample: "भाई, ये PR अभी merge मत करना। Staging पे tests fail हो रहे हैं।"
2. MAI recognizes the words well: romanized WER is 3.8-4.8% on Hinglish and 2.1% on Hindi. Most remaining errors are English words written in Devanagari ("डॉक्यूमेंटेशन", "सर्विस"): about 60 of 783 English words with `en`, 88 with auto-detect. Other errors are numbers written as digits ("pandrah" -> 15) and split or joined words (setup, codebase).
3. `language: "hi"` gave the same text as auto-detect on 88.9% of the Hinglish clips and 96.7% of the Hindi clips. `language: "en"` gave the same text on only 65.6% and 60.0%, so OpenRouter does forward `language` to MAI. Forced `en` keeps more English words in Latin script.
4. Grok writes Urdu script on 20 of 90 Hinglish clips and on half of the Hindi letters. With auto-detect, Grok cannot be used for Hindi or Hinglish.
5. Latency: MAI sequential p50 is about 1.02 s on clips of about 9 s. This is the provider round-trip only; the 1.0 s gate is measured from the stop tap to Cmd-V. Grok is about 0.2 s faster.
6. The romanized WER uses romanization rules that were tuned on these references (the spoken forms romanize to the references with 0 errors). It shows how well the words are recognized. It does not show how good the romanized spelling is.

### Recommendation

- Hinglish route: MAI with `language: "en"` (today's request), followed by a local Devanagari-to-Latin step that changes only the Devanagari words. MAI already recognizes the words; only the script is wrong. This adds no second request.
- ICU (`StringTransform`) with the rules in `bench/hinglish/score.ts` gives readable but not casual spelling ("tumhen", "men", "achchha", apostrophes in "isli'e"). Before it ships, test a better transliterator (IndicXlit, or more rules) on these outputs. Measure its cost on the hot path.
- English words that MAI writes in Devanagari (about 8%) do not come back to English through transliteration. Sarvam `saaras:v4` `translit` is still the only documented romanized output. Benchmark it on the same 120 clips before the decision; this needs a Sarvam key from the owner.
- Hindi (Devanagari): MAI with auto-detect or `hi` (WER 2.1%). Do not use Grok for Hindi or Hinglish without a forced language. Grok with `language: "hi"` was not tested.
- These are synthetic voices with clean audio. Confirm on 10-20 of the owner's own clips before the decision.

### Cost and duration

- Recorded in the raw files: TTS $0.1706 (listed-price estimate from audio length; OpenRouter `/generation` returned 404 for TTS generation ids), STT $0.1506 (`usage.cost`: accuracy $0.1290, latency $0.0216). Total $0.3212, cap $1.
- One failed attempt before the run: Gemini rejected `mp3` (400, no cost).
- Run time: about 4 min.
- The OpenRouter `/credits` total moved by only $0.0009 during the run, so it does not confirm the TTS estimate.

### Unresolved questions

1. What is the real TTS cost? `/generation` has no TTS rows, and `/credits` did not move.
2. Does Sarvam `translit` beat MAI plus local transliteration on these clips and on the owner's clips?
3. Which casual spelling does the owner want ("mein" or "men", "nahi" or "nahin")? This sets the transliteration rules.
4. Does Grok with a forced `language: "hi"` stop the Urdu output?

## Unresolved questions

1. Which script does MAI-Transcribe-2 use for Hinglish: Latin, Devanagari, mixed, or Urdu? No source says. Only the benchmark answers this. Synthetic bench: mixed (Hindi words in Devanagari, English words mostly in Latin).
2. Does OpenRouter map top-level `language` to Azure `locales`? (Synthetic bench: `language` changes MAI output, so it is forwarded; the field it maps to is still unknown.) Does `provider.options.azure.locales` pass through? Does MAI-2 accept `verbose_json` on OpenRouter (needed for the detected language)?
3. How much does auto-detect cost on the owner's English (WER, wrong-language rate) compared with forced `en`? kotoba-bench-v1 only measured forced `en`.
4. Which languages does the owner want besides English, Hindi and Hinglish? The 20 others in the table are untested by us.
5. Where does Sarvam serve its API from, and what is its latency from India for 10-30 s clips? Its docs give no region and no REST latency.
6. Is Sarvam's 30 s REST limit acceptable (chunking at pauses), or must the Hinglish route use its streaming API?
7. Does Grok's `x-ai/grok-stt-1.0` slug on OpenRouter serve Grok Voice Transcribe 2.0?
8. MAI-1 per-language numbers are a proxy for MAI-2. Does Microsoft publish a per-language table for MAI-2 anywhere (Foundry catalog page)?
9. Does the owner want Hinglish spelling normalized to one form (for example always "nahi"), or kept as the model writes it? This sets the scorer and any find/replace rules.
