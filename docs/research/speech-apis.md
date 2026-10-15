# Cloud STT and fast-LLM APIs for a macOS dictation app

Research date: 2026-10-15. All numbers have a source URL. "Unconfirmed" marks a fact that a primary source did not confirm.

Raw page dumps and extraction scripts:

- Artificial Analysis (AA) batch leaderboard, parsed from the page's embedded data: `scratchpad/raw/aa-batch-table.tsv` (from `raw/aa-batch.html`)
- AA streaming leaderboard, parsed: `scratchpad/raw/aa-streaming-table.tsv` (from `raw/aa-streaming.html`)
- MAI-Transcribe-2 model card PDF: `scratchpad/raw/mai/mai-t2-card.pdf`
- Scripts: `scratchpad/scripts/aa_extract.py`, `scratchpad/scripts/aa_batch.py`

Companion files (written by research sub-agents, merged in summary form below):

- `scratchpad/stt-vendors.md` - vocabulary boosting, short-clip latency, regions for the other STT vendors
- `scratchpad/cleanup-llms.md` - fast LLM options for the cleanup step
- `scratchpad/dictation-apps.md` - Wispr Flow, Aqua Voice and others

(All paths are under the session's scratch folder (outside git).)

---

## 1. Claim check (brief vs sources)

| Claim in brief | Verdict | Source |
| --- | --- | --- |
| xAI "Grok Voice Transcribe 2.0", 2.3% WER on AA | Confirmed. AA-WER 2.29%, speed factor 164.8, $1.67 per 1000 min. AA lists the creator as "SpaceXAI". | https://artificialanalysis.ai/speech-to-text |
| xAI ~$0.10/h batch, ~$0.20/h streaming | Confirmed. "REST (batch): $0.10 / hr", "Streaming (WebSocket): $0.20 / hr". | https://docs.x.ai/developers/models |
| xAI supports keyterms | Confirmed. `keyterm`, max 100 terms, max 50 characters each, batch and streaming. | https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text |
| MAI-Transcribe-2, 2.0% WER | Confirmed on AA (2.04%, rank 3 of 60 behind two 1.73% models; Microsoft says "#2"). | https://artificialanalysis.ai/speech-to-text, https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf |
| MAI-Transcribe-2 ~$0.10/h batch | Partly confirmed. $0.10/h is a "limited-time offer" (Azure footnote: "promotional offer till 12/31/2026"). The permanent price is not published. The Azure pricing page shows "N/A" for the row in the default view. AA lists $1.67/1000 min (= $0.10/h). | https://microsoft.ai/news/mai-transcribe-2, https://azure.microsoft.com/en-us/pricing/details/speech/ |
| MAI-Transcribe-2 has a phrase list | Confirmed: `phraseList.phrases`, "Terms are hints, not forced output". Count limit for v2 is unconfirmed. MAI-Transcribe-1.5 docs say "up to 200 keywords". | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe, https://microsoft-foundry.github.io/forgebook/notebook/mai-transcribe-1-5/ |
| Runs on Azure Speech API, not OpenAI-compatible | Correct for batch (multipart `audio` + `definition` JSON, `Ocp-Apim-Subscription-Key`). But: (a) the streaming model uses an "OpenAI Realtime API-like protocol"; (b) OpenRouter lists `microsoft/mai-transcribe-2` on `POST /api/v1/audio/transcriptions` (JSON with base64 audio, not multipart). | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime, https://openrouter.ai/microsoft/mai-transcribe-2 |
| Separate streaming version, ~120 ms latency | Confirmed in spirit. AA measures MAI-Transcribe-2-Streaming at 0.128 s time-to-final after speech end, 0.122 s to first partial, and the best streaming WER (2.51%). | https://artificialanalysis.ai/speech-to-text/streaming |
| Streaming ~$0.54/h | Confirmed via AA only: $9 per 1000 min = $0.54/h. Microsoft's own price for the streaming model is unconfirmed (docs point to the Foundry Models pricing page). | https://artificialanalysis.ai/speech-to-text/streaming |

Other corrections:

- Both models are **public preview** on Azure (no SLA). https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming
- MAI-Transcribe-2 batch accepts **WAV, MP3, FLAC only** (no Opus/AAC/M4A). https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe
- AA "speed factor" is measured on **10-minute** audio. It is a throughput metric, not short-clip latency. https://artificialanalysis.ai/speech-to-text

---

## 2. Candidate A: xAI Grok Voice Transcribe 2.0

| Item | Value | Source |
| --- | --- | --- |
| Model id | `grok-voice-transcribe-2.0` (default when `model` is omitted) | https://docs.x.ai/developers/model-capabilities/audio/speech-to-text |
| Batch endpoint | `POST https://api.x.ai/v1/stt`, multipart/form-data. Option fields must come **before** `file`. Not `/v1/audio/transcriptions` (that path 404s, per a LiteLLM PR). | https://docs.x.ai/developers/rest-api-reference/inference/speech-to-text, https://github.com/BerriAI/litellm/pull/41914 |
| Streaming endpoint | `wss://api.x.ai/v1/stt`, config as query params; binary audio frames; client sends `{"type":"finalize"}` (push-to-talk) or `{"type":"audio.done"}` | same |
| Auth | `Authorization: Bearer $XAI_API_KEY` | same |
| Containers (batch) | wav, mp3, ogg, opus, flac, aac, mp4, m4a, mkv (auto-detected). Raw pcm/mulaw/alaw need `audio_format` + `sample_rate`. | same |
| Sample rates | 8000, 16000, 22050, 24000, 44100, 48000 Hz | same |
| Streaming encodings | pcm (s16le), mulaw, alaw, opus (one packet per frame, ~4 KB/s). Recommended 16 kHz PCM16, 100 ms chunks. | same |
| Max size / duration | 500 MB (413 above). Max duration not stated (unconfirmed). | same |
| Keyterms | `keyterm` repeated field; **max 100 terms, max 50 chars each**; batch and streaming; no boost weight. No extra charge (secondary source). | same; https://vpsranking.com/news/ai/ai-2026-09-18-xai-grok-voice-transcribe-2/ |
| Languages | "38+" with auto-detect and mid-recording switching; `language` optional (biases recognition). | same |
| Word timestamps | Yes, `words[]` with `start`, `end`, `confidence` (and `speaker` with `diarize=true`) | same |
| Punctuation / casing | Shown in sample output; rules not documented. `format=true` (needs `language`) turns on inverse text normalization (numbers, currency, units) for 11 languages incl. English. `filler_words` default `false` = fillers removed. | same |
| Endpointing (stream) | `endpointing` default 400 ms (0-5000); `interim_results` every ~500 ms; `smart_turn` options | same |
| Rate limits | STT: "10 to 40 RPS and 100 to 500 concurrent sessions, depending on tier". Tiers by cumulative spend since 2026-01-01: $0, $50, $250, $1000, $5000. | https://docs.x.ai/docs/rate-limits |
| Regions | Global `https://api.x.ai`, routed "to the region with lowest latency"; may route between regions. Only regional endpoint is `us.api.x.ai`, which does **not** serve voice APIs. No Asia endpoint documented. | https://docs.x.ai/developers/regions |
| Data retention | "By default, all API requests and responses are stored ... for 30 days for auditing purposes"; "never trains on your API inputs or outputs without your explicit permission". Team-wide ZDR exists but is "not recommended for most customers". | https://docs.x.ai/docs/resources/faq-api/security |
| Account | Prepaid credits are "the most common way"; requests are rejected when credits run out unless invoiced billing is enabled. "Currently you can only purchase prepaid credits via Guest Checkout due to regulatory requirements." No free credit mentioned. India card status: docs conflict (older FAQ said Indian cards not supported; newer text routes them to Guest Checkout) - unconfirmed. | https://docs.x.ai/console/billing |
| Latency (published) | No official short-clip number. AA streaming: 0.49 s time-to-final after speech end, 2.73% streaming WER (v1.0 was 0.37 s). Batch speed factor 164.8 on 10-min files. | https://artificialanalysis.ai/speech-to-text/streaming |

Notes:

- Streaming time-to-final for v2.0 (0.49 s) is slower than MAI streaming (0.13 s), Scribe v2 Realtime (0.14 s) and Deepgram Flux (0.02 s). AA measures this from detected end of speech with forced endpointing where supported. For push-to-talk, `finalize` maps to that case.
- Network: no xAI region in Asia is documented. Assume US routing from India. Azure's P50 inter-region RTT Central India to East US is 201 ms and to West US 2 is 211 ms; this is a proxy only (https://learn.microsoft.com/en-us/azure/networking/azure-network-latency).

---

## 3. Candidate B: Microsoft MAI-Transcribe-2 (Azure Speech)

| Item | Value | Source |
| --- | --- | --- |
| Status | Public preview, version 2026-09-03 | https://ai.azure.com/catalog/models/MAI-Transcribe-2 |
| Batch endpoint | `POST https://<resource>.cognitiveservices.azure.com/speechtotext/transcriptions:transcribe?api-version=2025-10-15` (Fast Transcription API, "enhanced mode"). Synchronous: one request returns the transcript. | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe |
| Auth | `Ocp-Apim-Subscription-Key: <key>` (key is region-scoped) | https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe |
| Request | multipart/form-data: `audio` file + `definition` JSON: `{"enhancedMode":{"enabled":true,"model":"MAI-Transcribe-2","modelOptions":{"transcribeStyle":"clean","timestamps":"word"}},"phraseList":{"phrases":[...]},"locales":["en"]}` | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe |
| Formats | WAV, MP3, FLAC | same |
| Max size / duration | Conflicting: model card "300 MB / 2 hours"; REST ref "shorter than 2 hours ... smaller than 250 MB"; quotas page "< 500 MB", "< 5 hours". Irrelevant for 60 s clips. | https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf, https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe, https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits |
| Phrase list | `phraseList.phrases` (array of strings). "Terms are hints, not forced output." Limit for v2 unconfirmed; v1.5 "up to 200 keywords". No weight parameter documented for MAI (the classic Azure phrase-list weight 0.0-2.0 is a different feature). | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe, https://microsoft-foundry.github.io/forgebook/notebook/mai-transcribe-1-5/ |
| Styles | `transcribeStyle`: `verbatim` (default) or `clean` ("removes filler words and auto-formats common speech patterns") | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe |
| Languages | 60, auto-detect, code switching (Hinglish named). `locales` forces one language. | same |
| Word timestamps | `modelOptions.timestamps: "word"` returns `offsetMilliseconds`/`durationMilliseconds` | same |
| Punctuation / casing | Yes. Word "text" is "the recognized word, including punctuation"; model card sample shows cased, punctuated text. | https://learn.microsoft.com/en-us/rest/api/speechtotext/transcriptions/transcribe |
| Regions (batch) | LLM speech tab, "Transcribe with MAI-Transcribe": **centralindia**, eastus, northeurope, southeastasia, westus, westus2. Model card: "can be accessed globally ... served from" the same 6 regions "to which the requests are routed". | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/regions?tabs=llmspeech, https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf |
| Rate limits | LLM speech S0: 600 requests/min, not adjustable. F0: "Not applicable" (no free tier for this API). | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-services-quotas-and-limits |
| Data retention | "When doing real-time speech to text, fast transcription ... Microsoft does not retain or store the data provided by customers." "Azure Speech stores and processes speech data in the region where you create your resource." | https://learn.microsoft.com/en-us/azure/foundry/responsible-ai/speech-service/speech-to-text/data-privacy-security, https://learn.microsoft.com/en-us/azure/ai-services/speech-service/regions |
| Account | Azure subscription + "Microsoft Foundry resource for Speech". Azure free account: USD 200 credit for 30 days (India terms page), then pay-as-you-go. Speech F0 free hours cover real-time STT only ("5 audio hours free per month"), not fast transcription/LLM speech. | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe, https://azure.microsoft.com/en-in/offers/ms-azr-0044p/, https://azure.microsoft.com/en-us/pricing/details/speech/ |
| Latency (published) | No short-clip number. Model card: "1 hour of audio in about 10 secs". AA batch speed factor 313.7 (10-min files). | https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf, https://artificialanalysis.ai/speech-to-text |

### MAI-Transcribe-2-Streaming

| Item | Value | Source |
| --- | --- | --- |
| Protocol | WebSocket `wss://<resource>.services.ai.azure.com/mai/v1/realtime?intent=transcription`, "OpenAI Realtime API-like". Auth: Entra bearer or `api-key` header/query. Also via Speech SDK (>= 1.52.0 per secondary source, unconfirmed). | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming-realtime |
| Audio | Raw PCM16 mono, 16000 or 24000 Hz, base64 in `input_audio_buffer.append`. Send 10-20 ms chunks for lowest latency. | same |
| Finalize | `input_audio_buffer.commit` "produces completed transcription as soon as possible". No server VAD (`turn_detection` must be null). | same |
| Session limit | 1 hour | same |
| Requires | A model deployment in Foundry (Build > Models > Deploy a base model) | same |
| Regions | swedencentral, centralus, eastus2, southeastasia ("access globally", routed) | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming |
| Phrase list | Not mentioned in the Realtime API doc. Unconfirmed. | same |
| AA numbers | WER 2.51% (best streaming), 0.128 s to final, 0.122 s to first partial, $9/1000 min ($0.54/h) | https://artificialanalysis.ai/speech-to-text/streaming |

Network from India: Central India to Southeast Asia P50 RTT is 53 ms; to East US 2 is 204 ms; to Sweden Central 164 ms (Azure backbone, proxy only). https://learn.microsoft.com/en-us/azure/networking/azure-network-latency

---

## 4. Artificial Analysis leaderboards (pulled 2026-10-15)

### 4a. Non-streaming (batch), AA-WER v2

Method: ~8 h of audio; AA-AgentTalk 50%, VoxPopuli-Cleaned 25%, Earnings22-Cleaned 25%. Speed factor = audio seconds per processing second on 10-min files, median of last 7 days. Price = USD per 1000 min (divide by 16.67 for $/h). Source: https://artificialanalysis.ai/speech-to-text (values parsed from the page's embedded data, `raw/aa-batch-table.tsv`).

| # | Model (provider) | AA-WER | $/1000 min | $/h | Speed factor |
| --- | --- | --- | --- | --- | --- |
| 1 | StepAudio 3 ASR (StepFun) | 1.73% | 6.67 | 0.40 | 73.7 |
| 2 | Fun-Realtime-ASR-preview (Alibaba) | 1.73% | 0.00 (shown as 0; unconfirmed) | - | 20.6 |
| 3 | MAI-Transcribe-2 (Microsoft) | 2.04% | 1.67 | 0.10 | 313.7 |
| 4 | Scribe v2 (ElevenLabs) | 2.18% | 3.67 | 0.22 | 67.3 |
| 5 | Grok Voice Transcribe 2.0 (xAI/SpaceXAI) | 2.29% | 1.67 | 0.10 | 164.8 |
| 6 | MAI-Transcribe-1.5 (Microsoft) | 2.38% | 6.00 | 0.36 | 80.3 |
| 7 | Pulse Pro (Smallest.ai) | 2.43% | 4.00 | 0.24 | 284.1 |
| 8 | Gemini 3.5 Transcribe (Google) | 2.60% | 5.00 | 0.30 | 90.2 |
| 9 | Zoom Scribe V2 Pro | 2.75% | 3.33 | 0.20 | 118.9 |
| 10 | Voxtral Small (Mistral) | 2.77% | 4.00 | 0.24 | 65.5 |
| 11 | Gemini 3.1 Pro Preview (High) | 2.82% | 18.15 | 1.09 | 7.7 |
| 12 | Gemini 2.5 Pro | 2.86% | 11.39 | 0.68 | 10.6 |
| - | Universal-3.5 Pro (AssemblyAI) | ~3.0% (chart only; price/speed not in table) | - | - | - |
| 14 | Universal-3 Pro (AssemblyAI) | 3.12% | 3.50 | 0.21 | 109.9 |
| 16 | GPT Transcribe (OpenAI) | 3.31% | 4.50 | 0.27 | 56.9 |
| 21 | Voxtral Mini Transcribe 2 (Mistral) | 3.59% | 3.00 | 0.18 | 86.7 |
| 22 | Soniox v5 Async | 3.81% | 1.66 | 0.10 | 44.1 |
| 26 | GPT-4o Transcribe (OpenAI) | 3.96% | 6.00 | 0.36 | 36.6 |
| 28 | Speechmatics Enhanced | 4.05% | 12.50 | 0.75 | 69.7 |
| 41 | Whisper Large v3 Turbo (Groq) | 4.62% | 0.67 | 0.04 | 150.2 |
| 51 | Nova-3 (Deepgram) | 5.18% | 4.30 | 0.26 | 597.6 |

Deepgram Flux is streaming-only and appears only on the streaming board.

### 4b. Streaming

Method: time-to-final = seconds from SileroVAD end-of-speech to the final transcript (endpoint request sent when the model supports forced endpointing). Source: https://artificialanalysis.ai/speech-to-text/streaming (parsed, `raw/aa-streaming-table.tsv`).

| Model | WER (final) | Time to final (s) | First partial (s) | $/1000 min |
| --- | --- | --- | --- | --- |
| MAI-Transcribe-2-Streaming | 2.51% | 0.128 | 0.122 | 9.00 |
| Grok Voice Transcribe 2.0 (Streaming) | 2.73% | 0.490 | 0.489 | 3.33 |
| Muse Voice Transcribe | 3.06% | 0.163 | 0.127 | 3.00 |
| Cartesia Ink Preview (external endpoints) | 3.11% | 0.105 | 0.089 | 4.00 |
| Universal-3.6 Pro Realtime - Min Latency (AssemblyAI) | 3.57% | 0.192 | 0.188 | 7.50 |
| ElevenLabs Scribe v2 Realtime | 3.59% | 0.141 | 0.134 | 6.50 |
| GPT Live Transcribe (OpenAI) | 3.92% | 0.812 | 0.256 | 17.00 |
| Gemini 3.5 Transcribe Live | 4.00% | 0.395 | 0.250 | 9.00 |
| Cartesia Ink-2 (external endpoints) | 4.02% | 0.067 | 0.067 | 4.00 |
| Inworld STT 1 Realtime | 4.18% | 0.071 | 0.068 | 1.39 |
| Soniox v5 Real-Time | 4.50% | 0.054 | 0.047 | 2.00 |
| Deepgram Nova-3 Realtime | 6.59% | 0.066 | 0.064 | 4.80 |
| Deepgram Flux | 7.39% | 0.021 | 0.020 | 6.50 |
| Azure STT Real-time (classic) | 5.25% | 0.625 | 0.215 | 16.67 |

Caveat: AA WER sets are conversational, parliamentary and earnings-call English. None is dictated code prompts. Identifier accuracy needs an own test set.

---

## 5. Short-clip latency and regions (all providers)

Full detail with per-cell sources: `scratchpad/stt-vendors.md` sections 3-4.

### 5a. Published short-clip numbers

| Provider / mode | Number | Conditions | Source |
| --- | --- | --- | --- |
| Groq whisper-large-v3 (not turbo) | ~210 ms for 15 s, ~260 ms for 30 s | US-East client, median of 50 | https://dev.to/howmindswork/groq-vs-openai-whisper-real-benchmarks-for-voice-transcription-2026-46lk |
| OpenAI whisper-1 | ~820 ms for 15 s | same test | same |
| AssemblyAI Sync API | ~134 ms p50 (2 s clip, US/EU); ~1,900 ms for 15 s from Singapore (routed to EU) | vendor | https://www.assemblyai.com/blog/sync-api, https://assemblyai.com/blog/sync-speech-to-text-api-technical-walkthrough |
| AssemblyAI Async | 5-6 s for 2 s clip | vendor | https://www.assemblyai.com/blog/sync-api |
| Soniox async | ~3.3 s for 6 s | community PR | https://github.com/5uck1ess/cicero/pull/147 |
| Soniox live + finalize | final 24-41 ms after last audio | community PR, location not stated | same |
| xAI Grok 2.0, MAI-Transcribe-2, Deepgram, ElevenLabs, gpt-transcribe, Gemini, Voxtral | **No published 10-20 s batch number** | - | unconfirmed |

AA notes that batch speed factor "may vary ... particularly very short durations under 1 minute" (https://artificialanalysis.ai/speech-to-text).

### 5b. Network RTT from India

| Path | RTT | Source |
| --- | --- | --- |
| Mumbai to Hyderabad / Chennai | 16.6 / 19.9 ms | https://wondernetwork.com/pings/Mumbai |
| Mumbai to Singapore | 59.5 ms | same |
| Mumbai to London / Frankfurt / Stockholm | 133-150 ms | same |
| Mumbai to US cities | 240-253 ms | same |
| Azure Central India to Southeast Asia / East US / West US 2 | 53 / 201 / 211 ms | https://learn.microsoft.com/en-us/azure/networking/azure-network-latency |

### 5c. India-region availability (STT)

| Provider | Nearest self-serve processing | Source |
| --- | --- | --- |
| Microsoft MAI-Transcribe-2 (batch) | **centralindia** (Pune), plus southeastasia | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/regions?tabs=llmspeech |
| Microsoft MAI-Transcribe-2-Streaming | southeastasia (Singapore) | https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe-2-streaming |
| Deepgram Nova-3 / Flux | **`api.in.deepgram.com`, AWS Hyderabad, GA 2026-09-15, same price** | https://deepgram.com/learn/deepgram-india-endpoint-now-generally-available |
| Google Chirp 3 | asia-south1 Mumbai (Preview) | https://docs.cloud.google.com/speech-to-text/docs/release-notes |
| xAI | global, auto-routed; no Asia endpoint documented | https://docs.x.ai/developers/regions |
| ElevenLabs | India and Singapore residency are Enterprise only | https://elevenlabs.io/docs/overview/administration/data-residency |
| OpenAI | India is storage only; processing US/EU/UAE | https://developers.openai.com/api/docs/guides/your-data |
| AssemblyAI, Speechmatics, Mistral | US/EU (Speechmatics also AU) | see stt-vendors.md |
| Groq | no India; US, CA, Saudi Arabia, Finland, Australia | https://community.groq.com/t/what-geographic-regions-does-groqcloud-serve/833 |
| Soniox | US, EU, Japan; India "coming soon", sales-only | https://soniox.com/docs/stt/data-residency |

### 5d. Latency budget estimate for a 15 s clip (derived, not measured)

Assumptions: warm keep-alive HTTPS connection opened at hotkey press; home uplink ~10-20 Mbps; processing time = 15 s / AA speed factor plus an unknown fixed overhead.

| Path | Upload | RTT | Compute (15 s / speed factor) | Estimate |
| --- | --- | --- | --- | --- |
| MAI-Transcribe-2, Central India, FLAC 16 kHz mono (~250-300 KB) | ~0.15-0.25 s | ~0.02-0.05 s | 15/314 = ~0.05 s + overhead | ~0.3-0.5 s + overhead |
| Grok 2.0, US routing, Opus ~24 kbps (~45 KB) | ~0.03 s | ~0.25 s (plus slow-start rounds) | 15/165 = ~0.09 s + overhead | ~0.4-0.7 s + overhead |
| Any US host, cold connection, 480 KB WAV | 2 RTT handshake + 4-5 slow-start rounds | ~0.25 s each | - | can exceed 1.5 s before compute (stt-vendors.md 3d) |

Rule: keep the connection warm, send compressed audio, and measure p50/p90 from India before choosing. Streaming during speech plus a finalize message removes upload time from the critical path; then only one RTT plus time-to-final remains (e.g. MAI streaming via Singapore: ~0.05 + 0.13 s; Deepgram Nova-3 via Hyderabad: ~0.02 + 0.07 s).

---

## 6. Custom vocabulary comparison

Full table: `scratchpad/stt-vendors.md` section 2.

| Provider | Mechanism | Limits | Weights | Notes |
| --- | --- | --- | --- | --- |
| xAI Grok 2.0 | `keyterm` list | 100 terms x 50 chars | No | batch + stream |
| MAI-Transcribe-2 | `phraseList.phrases` | v2 unconfirmed (v1.5: 200) | Not documented | "hints, not forced output"; streaming support unconfirmed |
| Deepgram Nova-3 / Flux | `keyterm` list | 100 terms, 500 tokens total | No | +$0.078/h |
| ElevenLabs Scribe v2 | `keyterms` list | batch 1,000 (<50 chars, <=5 words); realtime 50 x 20 chars | No | +$0.05/h batch |
| OpenAI gpt-transcribe | `prompt` (free text) + `keywords` | numeric limit not published | No | free text can show style |
| AssemblyAI U3.5 Pro | `prompt` (1,500 words) OR `keyterms_prompt` (1,000) | realtime: prompt 1,750 chars + 100 keyterms | No | vendor warns of over-correction with large lists |
| Soniox v5 | `context` {general, text, terms} | 8,000 tokens | No | richest free-text context |
| Groq Whisper | `prompt` | 224 tokens | No | - |
| Gemini 3.5 Transcribe | `custom_vocabulary` | 1,000 (best <=100); not with word timestamps | No | - |
| Speechmatics | `additional_vocab` + `sounds_like` | <=1,000 recommended | No | pronunciation hints suit identifiers |
| Mistral Voxtral Mini 2 | `context_bias` | 100 terms | No | English-optimized |

Gaps: no provider documents how it writes camelCase, snake_case, paths or CLI flags. Free-text context (Soniox, AssemblyAI, OpenAI, Whisper) is the only documented way to show the wanted style. Term lists (xAI, MAI, Deepgram, ElevenLabs) only bias spelling. Wispr's Canto work found that context-trained models pick similar-sounding wrong terms about 5x more often from long lists, so keep lists short and ranked (`scratchpad/dictation-apps.md`).

Practical plan for a term list: build it per request from the frontmost project (file names, top identifiers, CLI tools) and cap at the provider limit. Spoken-to-written transforms ("camel case user id" to `userId`, "dash dash force" to `--force`) are better done by the cleanup LLM with the identifier list passed in as facts.

---

## 7. Cleanup LLM step

Full table: `scratchpad/cleanup-llms.md`. AA numbers are from Iowa with ~10k input tokens. Estimate = TTFT + 250 / tokens per second.

| Provider / model id | Setting | Tok/s | TTFT (s) | $ in / out per 1M | Est. 250 tok |
| --- | --- | --- | --- | --- | --- |
| Cerebras `gpt-oss-120b` | effort low | 1,642 | 0.41 (1.63 to answer, incl. reasoning) | 0.35 / 0.75 | 1.78 s |
| Cerebras `qwen-3.8-27b` | `reasoning_effort: "none"` | ~1,850 (vendor) | unconfirmed | 0.99 / 1.49 | ~0.5-0.7 s, unconfirmed |
| Groq `openai/gpt-oss-20b` | effort low | 951 | 0.76 (2.86 to answer) | 0.075 / 0.30 | 3.12 s |
| Google `gemini-3.5-flash` (Vertex Mumbai) | minimal | 186 | 0.80 | 1.50 / 9.00 | 2.14 s |
| Google `gemini-3.5-flash-lite` | AA tested above minimal | 438 | 7.06 | 0.30 / 2.50 | unconfirmed at minimal |
| Anthropic `claude-haiku-5-5` | AA: effort low, thinking on | 161 | 7.69 | 0.10 / 0.50 | 9.2 s as measured; ~2 s with thinking disabled, unconfirmed |
| OpenAI `gpt-6-luna` | none | 111 | 0.88 | 0.10 / 0.50 | 3.13 s |
| Mistral `mistral-small-2603` | non-reasoning | 146 | 1.07 | 0.15 / 0.60 | 2.78 s |

Haiku 5.5 id and price verified on https://platform.claude.com/docs/en/models/haiku-5-5/overview ($0.10 / $0.50 per MTok up to 100k-token prompts; adaptive thinking on by default). Other sources are cited in cleanup-llms.md.

Conclusions:

- No measured option adds less than ~1.8 s for 250 tokens. An always-on cleanup step breaks the 1 s target. Only Cerebras `qwen-3.8-27b` with reasoning "none" may fit (~0.5-0.7 s), and it is unmeasured.
- Add India RTT: ~0.2 s warm, ~0.6 s cold, to US hosts. Groq and Cerebras have no India data center (cleanup-llms.md).
- Risk: the transcript is itself an instruction to a coding agent. A small model can follow it instead of cleaning it. Wrap the transcript as data and test for this.
- Lower-latency option: use the STT's own cleanup (MAI `transcribeStyle: "clean"`, xAI `filler_words=false` default) for the default path, and run the LLM only on a second hotkey ("make this a clean prompt").

---

## 8. Wispr Flow and Aqua Voice

Full detail: `scratchpad/dictation-apps.md`. All numbers are vendor claims.

Aqua Voice:

- Own ASR "Avalon", "derived from Whisper"; plus LLM post-processing; screen-reading "Deep Context". https://aquavoice.com/llms.txt, https://app.aquavoice.com/research/avalon-model-card.pdf
- Avalon model card, AISpeak-10 key-term accuracy (coding/AI prompts): Avalon 97.4%, ElevenLabs Scribe v1 78.8%, Whisper Large v3 65.1%, Canary 1B 51.5%. Parakeet models 50-75%. Dataset not public. https://app.aquavoice.com/research/avalon-model-card.pdf
- Examples fixed by Avalon: "zshrc", "PyTorch", "Vercel", lowercase "uv". Same source.
- OpenASR average WER 6.23% (card) / 6.24% (blog). https://aquavoice.com/blog/avalon-openasr-leaderboard
- Text ~450 ms after key release; 800-entry dictionary; spoken casing ("camelCase user ID" to `userId`); @file tags in Cursor/Windsurf; batch API $0.39/h with a `prompt` field (dictation-apps.md has the source URLs).

Wispr Flow:

- Own ASR "Canto" (Sept 2026) plus fine-tuned Llama for formatting on Baseten; older help text also listed OpenAI, Anthropic, Cerebras, Fireworks (page now 404, unconfirmed).
- Latency target 700 ms p99: ASR <200 ms, LLM <200 ms, network <=200 ms; LLM must emit 100+ tokens in <250 ms. Audio streams in 1 s chunks during speech; warm-up call at start.
- Sends text context, not screenshots: app type, text around the cursor, visible IDE names (VS Code screen-reader mode), dictionary, history.

Lessons for this app: stream (or at least pre-open the connection) during speech; budget ~200 ms each for ASR, network and LLM; pass identifiers from the project as context; keep lists short; test on own coding clips, because public WER does not predict identifier accuracy (Avalon vs Parakeet).

---

## 9. Recommendation

**Default STT: MAI-Transcribe-2 (batch, Fast Transcription API) in an Azure Speech resource in `centralindia`.**

- Best AA batch WER among low-cost APIs (2.04%), $0.10/h, sync REST, in-country region (~20-50 ms RTT), "does not retain or store" fast-transcription data, `clean` style removes fillers, phrase list.
- Risks: public preview (no SLA); $0.10/h is promotional until 2026-12-31; WAV/MP3/FLAC only (send 16 kHz mono FLAC); phrase-list limit for v2 unknown; no free tier for this API (Azure free account $200/30 days covers trial use); multipart + `definition` JSON needs its own adapter.

**Backup STT: xAI Grok Voice Transcribe 2.0 (batch `POST /v1/stt`).**

- 2.29% AA WER, $0.10/h, keyterms 100 x 50, Opus/OGG upload (small payload), same multipart style.
- Risks: US routing (~200-250 ms RTT from India), 30-day retention of requests by default, prepaid credits via Guest Checkout only, India card handling unclear.

**Upgrade path if batch misses 1 s:** stream during speech and finalize on release. MAI-Transcribe-2-Streaming (Southeast Asia, 0.128 s time-to-final, 2.51% WER, $0.54/h, `input_audio_buffer.commit`) or Deepgram Nova-3 via Hyderabad (0.066 s, but 6.59% streaming WER). Grok streaming has `finalize` but 0.49 s time-to-final.

**Cleanup LLM:** off by default for the 1 s path. On a second hotkey, use Cerebras `qwen-3.8-27b` (`reasoning_effort: "none"`), backup Cerebras `gpt-oss-120b` (low) or `claude-haiku-5-5` with thinking disabled if quality matters more than ~2 s. Measure all three from India first.

---

## 10. Unresolved questions

1. Real p50/p90 hotkey-to-text time from India for MAI-Transcribe-2 (centralindia) and Grok 2.0 on 10-20 s clips. No published number exists.
2. MAI-Transcribe-2 phrase-list count and length limits; whether MAI-Transcribe-2-Streaming accepts a phrase list.
3. MAI-Transcribe-2 price after 2026-12-31; Microsoft's own price for the streaming model (only AA's $9/1000 min seen).
4. Does a `centralindia` resource keep MAI processing in India, or can "global" routing send it to another of the six regions?
5. xAI: which region serves India traffic; whether Indian cards work via Guest Checkout today.
6. Do keyterm/phrase lists help with camelCase, snake_case, paths and flags, or only spelling? Needs a private test set of the owner's own prompts.
7. TTFT from India for Cerebras `qwen-3.8-27b` (none) and `claude-haiku-5-5` with thinking disabled.
8. Brief said "MAI-Transcribe-2 streaming ~120 ms"; AA says 128 ms after speech end, which excludes network time. Real end-to-end from India is unmeasured.
