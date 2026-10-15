# Cloud STT vendors for a push-to-talk dictation app (India, Oct 2026)

Research date: 2026-10-15. Sources are web pages read on that date. Numbers without a source are marked "derived" (my calculation) or "unconfirmed".

Use case: Apple Silicon Mac in India. Clips are 10-60 s at about 200 wpm. The text is coding-agent prompts with identifiers, paths and CLI flags. Target: 1 s or less from hotkey release to pasted text for a 10-20 s clip.

---

## 0. Key findings

1. **Deepgram is the only vendor with self-serve STT inference in India.** `api.in.deepgram.com` runs in AWS Hyderabad (ap-south-2). It became GA on 2026-09-15 at the same price as the global endpoint. Nova-3 and Flux run there, and Whisper does not. [Deepgram blog](https://deepgram.com/learn/deepgram-india-endpoint-now-generally-available), [regional endpoints](https://developers.deepgram.com/reference/regional-endpoints). Mumbai to Hyderabad RTT is 16.59 ms. [WonderNetwork](https://wondernetwork.com/pings/Mumbai)
2. **Network distance is a large part of the 1 s budget.** Average ping from Mumbai is 59.52 ms to Singapore, 133-150 ms to London, Frankfurt and Stockholm, 176-180 ms to Helsinki and Riyadh, and 240-253 ms to US cities. [WonderNetwork](https://wondernetwork.com/pings/Mumbai). AssemblyAI measured about 1,900 ms for a 15 s clip sent from Singapore through the global endpoint, which routed it to the EU. The same API returns in about 134 ms p50 inside the US or EU. [AssemblyAI walkthrough](https://assemblyai.com/blog/sync-speech-to-text-api-technical-walkthrough)
3. **For push-to-talk, streaming during speech and then sending a finalize message is the fastest pattern.** In the Artificial Analysis (AA) streaming table, the time to final transcript after end of speech is 0.021 s for Deepgram Flux, 0.054 s for Soniox v5, 0.066 s for Deepgram Nova-3, 0.141 s for ElevenLabs Scribe v2 Realtime and 0.191 s for AssemblyAI U3.5 Realtime Pro. GPT Live Transcribe is 0.812 s. [AssemblyAI benchmarks page, reproducing AA, read 2026-09-09](https://www.assemblyai.com/benchmarks). These numbers do not include the network RTT from India.
4. **Async job APIs with polling do not meet a 1 s target.** Soniox batch took about 3.3 s for 6 s of audio. [cicero PR #147](https://github.com/5uck1ess/cicero/pull/147). AssemblyAI Async takes 5-6 s for a 2 s clip. [AssemblyAI Sync launch](https://www.assemblyai.com/blog/sync-api). Speechmatics batch is also a job API.
5. **For technical vocabulary, free-text context is better than a term list.** Free-text context lets you describe the domain and give formatting examples, and not only list words. These providers accept free-text context: Soniox (`context.text` plus `terms`, 8,000 tokens), AssemblyAI Universal-3.5 Pro (`prompt` up to 1,500 words async or 1,750 chars streaming), OpenAI `gpt-transcribe` (`prompt` plus `keywords`) and Groq Whisper (`prompt`, 224 tokens). Deepgram, ElevenLabs, Gemini, Mistral, Cartesia and Google Chirp 3 accept term lists only. Speechmatics accepts a term list with `sounds_like` pronunciations, which can help with identifiers that people say differently from how they spell them.
6. **AA batch speed factors use 10-minute files.** AA says that values "may vary ... particularly very short durations under 1 minute". Do not use them to rank providers for 10-20 s clips. [AA STT leaderboard](https://artificialanalysis.ai/speech-to-text)

---

## 1. Summary table

Prices are per hour of audio, pay-as-you-go, and do not include add-ons unless the table says so. "Sync REST" means one HTTP request returns the transcript.

| Provider / model | Batch $/hr | Stream $/hr | Batch API shape | Finalize message (stream) | Vocab mechanism | Nearest region to India |
|---|---|---|---|---|---|---|
| Deepgram Nova-3 (mono) | $0.258 ($0.0043/min) | $0.288 ($0.0048/min, promo) | Sync REST `/v1/listen` | `{"type":"Finalize"}` | `keyterm` list, 500 tokens, +$0.078/hr | **India (Hyderabad), self-serve** |
| Deepgram Flux English | n/a (stream only) | $0.39 ($0.0065/min) | n/a | `ForceEndTurn` (Flux); no `Finalize` | `keyterm` | India (Hyderabad) |
| ElevenLabs Scribe v2 / v2 Realtime | $0.22 (+$0.05 keyterms) | $0.39 (+$0.08 keyterms) | Sync REST (webhook optional) | manual `commit` (default strategy) | `keyterms` list | Default routing includes Singapore (TTS only confirmed); India and SG residency are Enterprise only |
| OpenAI gpt-transcribe / gpt-live-transcribe | $0.27 ($0.0045/min) | $1.02 ($0.017/min) | Sync REST, `stream=true` deltas | `input_audio_buffer.commit` | `prompt` (free text) plus `keywords` | Processing in US/EU/UAE only; India is storage-only |
| OpenAI gpt-4o-transcribe | $0.36 ($0.006/min) | (via Realtime) | Sync REST | `input_audio_buffer.commit` | `prompt` | same as above |
| AssemblyAI Universal-3.5 Pro (async) | $0.21 (+$0.05 keyterms, +$0.05 prompt) | n/a | Async job plus polling | n/a | `prompt` (1,500 words) OR `keyterms_prompt` (1,000 terms) | Global (nearest), US, EU |
| AssemblyAI Sync API (U3.5 Pro) | $0.45 | n/a | **Sync REST** (80 ms-120 s, WAV/PCM only) | n/a | prompt, keyterms (<2,048 chars), conversation context | Global, US, EU |
| AssemblyAI Universal-3.6 Pro Realtime | n/a | $0.45 (keyterms incl., prompt +$0.05) | n/a | `{"type":"ForceEndpoint"}` | `prompt` (1,750 chars) AND `keyterms_prompt` (100) | Global (nearest), EU |
| Groq whisper-large-v3-turbo | $0.04 (10 s min per request) | none | Sync REST | none | `prompt`, 224 tokens | US, CA, Saudi Arabia, Finland, Australia; no India |
| Google Gemini 3.5 Transcribe / Live | ~$0.30 (~$0.005/min) | ~$0.54 (~$0.009/min) | Sync ("unary") | `audioStreamEnd` (finalize effect unconfirmed) | `custom_vocabulary` list | Vertex: global/us/eu; ML processing in US/EU |
| Google Chirp 3 (Speech V2) | $0.96 ($0.016/min); dynamic batch $0.18 (up to 24 h wait) | $0.96 | Sync `Recognize` (<1 min) | stream half-close (unconfirmed) | adaptation phrases, 1,000 | asia-south1 (Preview), asia-southeast1 (GA in most copies) |
| Mistral Voxtral Mini Transcribe V2 / Realtime | $0.18 ($0.003/min) | $0.36 ($0.006/min) | Sync REST | not documented | `context_bias`, 100 terms | Global (no location commitment), EU, US |
| Mistral Voxtral Small (chat with audio) | ~$0.24 (AA $4/1,000 min) | n/a | Sync chat completions | n/a | free-text chat prompt (unconfirmed for STT use) | same |
| Speechmatics Melia / Standard / Enhanced | $0.129 / $0.45 / $0.75 | (Melia none) / $0.45 / $0.80 | Async job | `ForceEndOfUtterance` | `additional_vocab` plus `sounds_like` | EU1, US1, AU1; `global.rt` to nearest |
| Soniox v5 (async / rt) | $0.10 | $0.12 | Async job plus polling | `{"type":"finalize"}` | `context` (general, text, terms), 8,000 tokens | US, EU, Japan; India "coming soon"; not self-serve |
| Smallest.ai Pulse Pro / Pulse | $0.24 ($0.004/min) | ~$0.24 (AA $4/1,000 min) | Sync REST (webhook optional) | unconfirmed | Pulse streaming: keywords with intensifier; Pulse Pro: none documented | Atoms on AWS Mumbai; Waves API region unconfirmed |
| Cartesia Ink-2 | n/a (no batch documented) | ~$0.39 (Scale) to ~$0.54 (Pro), derived | n/a | text message `finalize` | `keyterm`, 100 terms / 1,200 chars | Default routes to closest; India deployment is Enterprise only |

Sources for each cell are in the per-provider sections below.

---

## 2. Custom vocabulary and context

| Provider | Parameter | Type | Limits | Weights | Batch / stream | Extra cost |
|---|---|---|---|---|---|---|
| Deepgram Nova-3, Flux | `keyterm` (repeat the query param); `keyterms` in `Configure` mid-stream | term list | "up to 100" terms; 500 tokens per request total; best practice 20-50 terms | No. "does not support weights or intensifiers" (the legacy `keywords` has `:INTENSIFIER`) | Both. Mid-stream update only on global endpoint, not EU/AU/India | +$0.0013/min ($0.078/hr) |
| ElevenLabs Scribe v2 | `keyterms` | term list | Batch: 1,000 terms, <50 chars, max 5 words each; chars `<>{}[]\` not allowed. Realtime: 50 terms, 20 chars each | No | Both | Batch +$0.05/hr (API ref says 20% surcharge); RT +$0.08/hr. >100 keyterms sets a 20 s minimum billable duration per request |
| OpenAI gpt-transcribe, gpt-live-transcribe | `prompt` plus `keywords` (one per line, no `<`, `>`, CR, LF) | **free text plus term list** | gpt-transcribe: no numeric limit published ("model's length limit"); whisper-1 prompt 224 tokens | No | Both | None stated |
| AssemblyAI U3.5 Pro async | `prompt` OR `keyterms_prompt` (mutually exclusive on async) | **free text** or term list | prompt up to 1,500 words; keyterms 1,000 terms, 6 words each | No | Batch | +$0.05/hr each |
| AssemblyAI Sync API | prompt, `keyterms_prompt`, conversation context | **free text plus term list** | keyterms total < 2,048 chars | No | Sync batch | included in $0.45/hr (unconfirmed) |
| AssemblyAI U3.6 Pro Realtime | `prompt` AND `keyterms_prompt` (can combine), `UpdateConfiguration` mid-stream | **free text plus term list** | prompt 1,750 chars; keyterms 100 | No | Stream | keyterms included; prompt +$0.05/hr |
| Groq Whisper | `prompt` | **free text** | 224 tokens | No | Batch | None |
| Google Gemini 3.5 Transcribe | `custom_vocabulary` | term list | 1,000 terms (best at 100 or fewer); cannot combine with diarization or word timestamps | No | Both | None stated |
| Google Chirp 3 | speech adaptation phrases | term list | 1,000 phrases | (boost exists in V2 adaptation; not checked for chirp_3, unconfirmed) | Both | unconfirmed |
| Mistral Voxtral Mini Transcribe V2 | `context_bias` | term list | 100 words or phrases; optimized for English | No | Batch (Realtime: not documented) | None stated |
| Speechmatics | `transcription_config.additional_vocab` with `content` and `sounds_like` | term list plus pronunciations | recommend 1,000 or fewer; reject over 20,000; entry dropped if >6 words | No | Batch, Realtime, Agent | None stated |
| Soniox | `context` {`general`, `text`, `terms`, `translation_terms`} | **free text plus term list** | 8,000 tokens (~10,000 chars) | No | Both (RT confirmed in WebSocket ref; async uses same concept page) | None stated |
| Smallest.ai Pulse | keywords with intensifier | term list | changelog says max 10k; intensifier scale conflicts across doc versions | Yes (intensifier) | **Streaming only**; not on pre-recorded HTTP | unconfirmed |
| Smallest.ai Pulse Pro | none documented | - | - | - | - | - |
| Cartesia Ink-2 | `keyterm` (repeat query param) | term list | 100 terms, 1,200 chars total; set at connect only | No | Stream | None stated |

Notes:
- Deepgram keyterm limits: [keyterm docs](https://developers.deepgram.com/docs/keyterm). Price: [Deepgram pricing](https://deepgram.com/pricing).
- ElevenLabs batch limits and surcharge: [API reference](https://elevenlabs.io/docs/api-reference/speech-to-text/convert). Realtime 50 x 20 chars and per-hour add-on: [STT capabilities](https://elevenlabs.io/docs/capabilities/speech-to-text), [API pricing](https://elevenlabs.io/pricing/api). The 20% surcharge and the $0.05/hr add-on are both on official pages. On $0.22/hr base, 20% is $0.044/hr, so they are close but not equal.
- OpenAI: [STT guide](https://developers.openai.com/api/docs/guides/speech-to-text), [realtime transcription guide](https://developers.openai.com/api/docs/guides/realtime-transcription).
- AssemblyAI: [models reference](https://www.assemblyai.com/md/models), [pricing](https://www.assemblyai.com/md/pricing), [streaming API ref](https://www.assemblyai.com/docs/api-reference/streaming-api/streaming-api), [push-to-talk Sync blog](https://www.assemblyai.com/blog/build-push-to-talk-dictation-sync-api). AssemblyAI says to start without `keyterms_prompt` or `prompt`, because U3.5 Pro "is tuned to work without them". The keyterms page warns that large lists of common terms can cause overcorrection and hallucination. [Keyterms Prompting](https://www.assemblyai.com/docs/custom-vocabulary)
- Groq: [Groq STT docs](https://console.groq.com/docs/speech-to-text).
- Gemini: [Gemini transcribe docs](https://ai.google.dev/gemini-api/docs/transcribe), [Vertex model page](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-5-transcribe). Free-text prompt is not documented.
- Chirp 3: [Chirp 3 page](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3).
- Mistral: [Voxtral Transcribe 2 launch](https://mistral.ai/news/voxtral-transcribe-2), [offline transcription docs](https://docs.mistral.ai/studio/audio/speech_to_text/offline_transcription).
- Speechmatics: [custom dictionary](https://docs.speechmatics.com/speech-to-text/features/custom-dictionary).
- Soniox: [context concepts](https://soniox.com/docs/stt/concepts/context), [WebSocket API](https://soniox.com/docs/stt/api-reference/websocket-api).
- Smallest: [keyword boosting](https://docs.smallest.ai/models/documentation/speech-to-text-pulse/features/keyword-boosting), [changelog 2026-07-22](https://docs.smallest.ai/models/changelog/pulse-stt/2026/7/22), [Pulse Pro card](https://docs.smallest.ai/models/model-cards/speech-to-text/pulse-pro.md).
- Cartesia: [STT WebSocket ref](https://docs.cartesia.ai/api-reference/stt/websocket.md), [keyterms](https://docs.cartesia.ai/use-the-api/stt/keyterms).

For identifiers (camelCase, snake_case, paths, flags): no provider documents how it writes these. Free-text context (Soniox `context.text`, AssemblyAI `prompt`, OpenAI `prompt`, Whisper `prompt`) is the only documented way to show the model a sample of the wanted style. The effect on casing and separators is unconfirmed. Test it on your own clips.

---

## 3. Short-clip latency

### 3a. Published measurements

| Provider / mode | Measurement | Conditions | Source |
|---|---|---|---|
| AssemblyAI Sync API | ~134 ms p50 | 2 s clip, US/EU client | [Sync launch](https://www.assemblyai.com/blog/sync-api) |
| AssemblyAI Sync API | ~1,900 ms | ~15 s live clip from Singapore, routed to EU | [walkthrough](https://assemblyai.com/blog/sync-speech-to-text-api-technical-walkthrough) |
| AssemblyAI Async | 5-6 s | 2 s clip | [Sync launch](https://www.assemblyai.com/blog/sync-api) |
| Soniox batch (async) | ~3.3 s | 6 s clip | [cicero PR #147, 2026-10-02](https://github.com/5uck1ess/cicero/pull/147) |
| Soniox live | final 24-41 ms after last audio | live WebSocket; test-machine location not stated | [cicero PR #147](https://github.com/5uck1ess/cicero/pull/147) |
| Groq (whisper-large-v3, not turbo) | ~180 / 210 / 260 / 380 ms for 5 / 15 / 30 / 60 s | US-East server, median of 50 requests, Apr 2026 | [dev.to](https://dev.to/howmindswork/groq-vs-openai-whisper-real-benchmarks-for-voice-transcription-2026-46lk) |
| OpenAI (whisper-1 per code sample) | ~750 / 820 / 1,100 / 1,800 ms for 5 / 15 / 30 / 60 s | same test | [dev.to](https://dev.to/howmindswork/groq-vs-openai-whisper-real-benchmarks-for-voice-transcription-2026-46lk) |
| OpenAI Whisper | "1-3 seconds for a 15-second clip" | not stated | [Parrot blog](https://www.tryparrot.app/blog/transcription-apis-compared) |
| Deepgram pre-recorded | "often under 1 second for short clips" | not stated | [Parrot blog](https://www.tryparrot.app/blog/transcription-apis-compared) |
| Deepgram, ElevenLabs, OpenAI gpt-transcribe, Gemini, Mistral, Smallest, Speechmatics batch | **no published short-clip batch number found** | - | unconfirmed |

Batch throughput on 10-minute files (AA "speed factor" = audio seconds per processing second, median over 7 days). Not valid for short clips:

| Model | AA-WER | Speed factor | $/1,000 min |
|---|---|---|---|
| Deepgram Nova-3 | 5.2% | 597.6 | 4.30 |
| Smallest Pulse Pro | 2.4% | 284.1 | 4.00 |
| Speechmatics Melia | 4.9% | 174.7 | 4.00 |
| Groq Whisper Large v3 Turbo | 4.6% | 150.2 | 0.67 |
| AssemblyAI Universal-3 Pro | 3.1% | 109.9 | 3.50 |
| Gemini 3.5 Transcribe | 2.6% | 90.2 | 5.00 |
| Voxtral Mini Transcribe 2 | 3.6% | 86.7 | 3.00 |
| ElevenLabs Scribe v2 | 2.2% | 67.3 | 3.67 |
| Voxtral Small | 2.8% | 65.5 | 4.00 |
| GPT Transcribe | 3.3% | 56.9 | 4.50 |
| Soniox v5 Async | 3.8% | 44.1 | 1.66 |
| GPT-4o Transcribe | 4.0% | 36.6 | 6.00 |
| Google Chirp 3 | 4.3% | 29.6 | 16.00 |

Source: [AA STT leaderboard](https://artificialanalysis.ai/speech-to-text). Note: Groq's price on AA ($0.67/1,000 min = $0.04/hr) matches Groq docs.

### 3b. Streaming: time to final after end of speech

| Model | AA t_final (s), forced endpoint where supported | AA-WER stream | Pipecat TTFS median / p95 (ms) | Pipecat WER |
|---|---|---|---|---|
| Deepgram Flux | 0.021 | 7.39% | - | - |
| Soniox v5 | 0.054 | 4.50% | 260 / 305 | 1.11% |
| Deepgram Nova-3 | 0.066 | 6.59% | 247 / 298 | 1.32% |
| Cartesia Ink-2 (external endpoint) | 0.067 | 4.02% | 299 / 328 | 1.14% |
| Smallest Pulse | 0.132 | 4.98% | 398 / 533 | 1.85% |
| ElevenLabs Scribe v2 Realtime | 0.141 | 3.59% | 281 / 348 | 3.05% |
| AssemblyAI U3.5 Realtime Pro | 0.191-0.202 | 4.02-4.03% | 282 / 354 | 1.12% |
| AssemblyAI U3.6 Pro Realtime | - | - | 307 / 401 | 0.89% |
| Speechmatics RT Enhanced / linden-1 | 0.317 | 8.05% | 369 / 438 (linden-1) | 1.11% |
| Gemini 3.5 Transcribe Live | 0.395 | 4.00% | 458 / 532 | 1.93% |
| Voxtral Mini Realtime | 0.682 | 5.24% | 525 / 973 | 4.49% |
| GPT Live Transcribe | 0.812 | 3.92% | - | - |
| OpenAI gpt-4o-transcribe | - | - | 637 / 965 | 3.10% |
| Google Chirp 3 Streaming | 1.276 | 4.80% | - | - |

Sources: AA streaming table as reproduced on [AssemblyAI benchmarks](https://www.assemblyai.com/benchmarks) (read by AssemblyAI 2026-09-09; the primary [AA streaming page](https://artificialanalysis.ai/speech-to-text/streaming) did not render numbers for me; AA says it sends the forced endpoint request at speech end when the model supports it). Pipecat: [pipecat-ai/stt-benchmark](https://github.com/pipecat-ai/stt-benchmark), 1,000 samples, Silero VAD, test location not stated. The benchmark does not say if it sends finalize. AssemblyAI hosts the AA reproduction, so treat its framing with care.

### 3c. Finalize / force-endpoint messages

| Provider | Message | Notes | Source |
|---|---|---|---|
| Deepgram Nova-3 | `{"type":"Finalize"}` | returns `from_finalize: true`; not guaranteed if little audio is buffered | [Finalize](https://developers.deepgram.com/docs/finalize) |
| Deepgram Flux | `ForceEndTurn` | ends the turn and emits `EndOfTurn` | [Force End Turn](https://developers.deepgram.com/docs/flux/force-end-turn) |
| Soniox | `{"type":"finalize"}` | emits `<fin>` token; send after ~200 ms of trailing silence; billed on full stream duration | [manual finalization](https://soniox.com/docs/stt/rt/manual-finalization) |
| AssemblyAI streaming | `{"type":"ForceEndpoint"}` | streaming billed on session duration, including idle | [streaming ref](https://www.assemblyai.com/docs/api-reference/streaming-api/streaming-api), [pricing](https://www.assemblyai.com/md/pricing) |
| ElevenLabs Scribe v2 RT | manual commit (default `commit_strategy`) | auto-commit every 90 s | [commit strategies](https://elevenlabs.io/docs/eleven-api/guides/how-to/speech-to-text/realtime/transcripts-and-commit-strategies) |
| OpenAI gpt-live-transcribe | `input_audio_buffer.commit` | turn_detection must be null; `delay` = minimal...xhigh | [realtime transcription](https://developers.openai.com/api/docs/guides/realtime-transcription) |
| Speechmatics | `ForceEndOfUtterance` | final ~250 ms later (vendor) | [Speechmatics blog](https://www.speechmatics.com/company/articles-and-news/you-cant-hurry-love-but-you-can-hurry-final-transcripts) |
| Cartesia Ink-2 | text `finalize` | reply `flush_done` | [WebSocket ref](https://docs.cartesia.ai/api-reference/stt/websocket.md) |
| Gemini Live | `audioStreamEnd: true` | whether it forces a final for buffered audio is unconfirmed | [live transcribe](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe) |
| Mistral Voxtral Realtime | not documented | `target_streaming_delay_ms` (240-2,400 ms examples) | [realtime docs](https://docs.mistral.ai/studio/audio/speech_to_text/realtime_transcription.md) |
| Groq | no streaming STT | - | [Groq STT docs](https://console.groq.com/docs/speech-to-text) |

### 3d. Network cost from India (derived)

- One HTTPS request on a new connection needs about 2 RTT (TCP plus TLS 1.3) before the body. TCP slow start adds more RTTs for a large body. These are general protocol facts, not measured here.
- Derived example: a 15 s clip as 16 kHz mono 16-bit WAV is about 480 KB. Opus at about 24 kbps is about 45 KB. To a US host (RTT ~250 ms), a cold connection plus about 4-5 slow-start rounds for 480 KB can use 1.5 s or more before any compute. To Hyderabad (RTT ~17 ms) the same steps take about 0.1 s. These are estimates, not measurements.
- Mitigations: keep a warm, kept-alive connection (AssemblyAI provides an unauthenticated `GET /warm` for this, [blog](https://www.assemblyai.com/blog/build-push-to-talk-dictation-sync-api)). Send compressed audio. Or stream during speech, so that only the finalize round trip remains after release.

---

## 4. Regions near India

| Provider | India / Asia option | Self-serve? | Source |
|---|---|---|---|
| Deepgram | `api.in.deepgram.com`, AWS ap-south-2 Hyderabad; also EU, AU. No Whisper in IN; no mid-stream keyterm `Configure` in IN | Yes, same price | [blog](https://deepgram.com/learn/deepgram-india-endpoint-now-generally-available), [regional endpoints](https://developers.deepgram.com/reference/regional-endpoints) |
| ElevenLabs | India `api.in.residency.elevenlabs.io`, Singapore `api.sg.residency.elevenlabs.io`, EU; separate workspace and key | Enterprise only | [data residency](https://elevenlabs.io/docs/overview/administration/data-residency) |
| ElevenLabs default | `api.elevenlabs.io` routes by geography: USA, Netherlands, Singapore. The page covers TTS only; STT routing is unconfirmed | Yes | [server location](https://elevenlabs.io/docs/api-reference/specifying-server-location) |
| OpenAI | `in.api.openai.com` is storage only; regional processing only in US, EU, UAE; `/v1/audio/transcriptions` and `/v1/realtime` process in US/EU | Needs approval for non-US residency | [data controls](https://developers.openai.com/api/docs/guides/your-data) |
| AssemblyAI | global (routes to nearest region), US, EU. No Asia region published | Yes | [streaming ref](https://www.assemblyai.com/docs/api-reference/streaming-api/streaming-api), [walkthrough](https://assemblyai.com/blog/sync-speech-to-text-api-technical-walkthrough) |
| Groq | no India data center; regions US, Canada, Saudi Arabia, Finland, Australia; community post suggests Dammam for India | - | [Groq community](https://community.groq.com/t/can-i-get-the-models-to-be-hosted-inside-of-india-regeion/190), [Groq regions](https://community.groq.com/t/what-geographic-regions-does-groqcloud-serve/833) |
| Google Chirp 3 | asia-south1 (Mumbai) Preview since 2025-11-13; asia-southeast1 GA in most doc copies (copies conflict) | Yes | [release notes](https://docs.cloud.google.com/speech-to-text/docs/release-notes), [Chirp 3](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3) |
| Google Gemini 3.5 Transcribe | Vertex `global`, `us`, `eu`; ML processing US and EU. Gemini Developer API: no region choice | Yes | [Vertex model page](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/gemini/3-5-transcribe) |
| Mistral | `api.mistral.ai` (no location commitment), `api.eu.mistral.ai`, US endpoint. Transcription coverage of regional routing is unconfirmed | Yes | [regional inference](https://docs.mistral.ai/studio/regional-inference) |
| Speechmatics | EU1, US1, AU1; `global.rt.speechmatics.com` routes RT to nearest. No Asia region | Yes | [regions](https://docs.speechmatics.com/administration/regions), [changelog 2026-07-20](https://speechmatics.featurebase.app/changelog/20260720-rt-saas) |
| Soniox | US, EU, Japan; India listed "coming soon" | No (contact sales/support) | [data residency](https://soniox.com/docs/stt/data-residency) |
| Smallest.ai | Atoms platform on AWS Mumbai (ap-south-1) per AWS Marketplace; Waves STT API region unconfirmed | unconfirmed | [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-5het7at3rymmy) |
| Cartesia | default `api.cartesia.ai` routes to closest endpoint; dedicated India deployment for Enterprise | India: Enterprise only | [regional endpoints](https://docs.cartesia.ai/enterprise/regional-endpoints) |

RTT from Mumbai (average ping): Hyderabad 16.59 ms, Chennai 19.86, Singapore 59.52, London 133.24, Frankfurt 141.68, Stockholm 149.85, Helsinki 176.40, Riyadh 180.30, Portland 240.48, Dallas 241.66, Washington 246.49, New York 252.68, Sydney 306.59. [WonderNetwork](https://wondernetwork.com/pings/Mumbai)

---

## 5. Price, formats, small-file limits

| Provider | Batch $/hr | Stream $/hr | Compressed input (batch) | Stream input | Limits | Source |
|---|---|---|---|---|---|---|
| Deepgram Nova-3 | $0.258 mono, $0.312 multi | $0.288 mono, $0.348 multi (promo) | Yes: Opus, Ogg, FLAC, M4A, WebM, 100+ formats | (page does not split batch vs stream) | 2 GB; 10 min request timeout | [pricing](https://deepgram.com/pricing), [formats](https://developers.deepgram.com/docs/supported-audio-formats), [pre-recorded](https://developers.deepgram.com/docs/pre-recorded-audio) |
| Deepgram Flux | - | $0.39 EN, $0.468 multi | - | unconfirmed | - | [pricing](https://deepgram.com/pricing) |
| ElevenLabs Scribe v2 | $0.22 | $0.39 | Yes: AAC, AIFF, OGG, MP3, OPUS, WAV, FLAC, M4A, WebM; `file_format=pcm_s16le_16` gives lower latency | PCM (8-48 kHz), μ-law; Opus not documented | min 100 ms; <5 GB | [capabilities](https://elevenlabs.io/docs/capabilities/speech-to-text), [API ref](https://elevenlabs.io/docs/api-reference/speech-to-text/convert), [pricing](https://elevenlabs.io/pricing/api) |
| OpenAI gpt-transcribe | $0.27 | gpt-live $1.02 | mp3, mp4, mpeg, mpga, m4a, wav, webm (no flac/ogg listed) | PCM 24 kHz in example | 25 MB | [STT guide](https://developers.openai.com/api/docs/guides/speech-to-text), [model page](https://developers.openai.com/api/docs/models/gpt-transcribe), [live model](https://developers.openai.com/api/docs/models/gpt-live-transcribe) |
| OpenAI gpt-4o / mini | $0.36 / $0.18 | - | same | - | 25 MB | [Spokenly](https://spokenly.app/blog/gpt-transcribe) (third party) |
| AssemblyAI U3.5 Pro async | $0.21 | - | unconfirmed list | - | - | [pricing](https://www.assemblyai.com/md/pricing) |
| AssemblyAI Sync | $0.45 | - | **No: WAV or raw PCM only** | - | 80 ms-120 s; 40 MB | [Sync launch](https://www.assemblyai.com/blog/sync-api), [blog](https://www.assemblyai.com/blog/build-push-to-talk-dictation-sync-api) |
| AssemblyAI U3.6 Pro RT / Universal-Streaming | - | $0.45 / $0.15 | - | pcm_s16le, pcm_mulaw, opus, ogg_opus, aac | 8-96 kHz | [streaming ref](https://www.assemblyai.com/docs/api-reference/streaming-api/streaming-api) |
| Groq turbo | $0.04 | none | flac, mp3, mp4, mpeg, mpga, m4a, ogg, wav, webm (docs suggest wav for lower latency) | - | 25 MB free, 100 MB dev; 10 s min billed | [Groq docs](https://console.groq.com/docs/speech-to-text) |
| Gemini 3.5 Transcribe | ~$0.30 | ~$0.54 | WAV, MP3, AIFF, AAC, OGG, FLAC, MPEG, M4A, L16, Opus, ALAW, MULAW, WebM | PCM 16 kHz example | Vertex: file up to 15 min; live up to 10 min | [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [transcribe docs](https://ai.google.dev/gemini-api/docs/transcribe) |
| Google Chirp 3 | $0.96 | $0.96 | see encoding docs (unconfirmed) | LINEAR16 example | sync Recognize for <1 min | [pricing search summary](https://cloud.google.com/speech-to-text/pricing/) (page did not render; $0.016/min unconfirmed from primary), [Chirp 3](https://docs.cloud.google.com/speech-to-text/docs/models/chirp-3) |
| Mistral Voxtral Mini V2 / RT | $0.18 | $0.36 | mp3, wav, m4a, flac, ogg (playground list; API list unconfirmed) | pcm_s16le | up to 3 h per request | [launch](https://mistral.ai/news/voxtral-transcribe-2), [RT docs](https://docs.mistral.ai/studio/audio/speech_to_text/realtime_transcription.md) |
| Speechmatics | Melia $0.129; Std $0.45; Enh $0.75 | Std $0.45; Enh $0.80 | unconfirmed | unconfirmed | - | [pricing](https://www.speechmatics.com/pricing), [Melia](https://speechmatics.com/company/articles-and-news/introducing-melia-multilingual-speech-to-text-model) |
| Soniox v5 | $0.10 | $0.12 | aac, aiff, amr, asf, flac, mp3, ogg, wav, webm, m4a, mp4 | `audio_format: "auto"` (ogg, flac, wav, s16le...) | context 8,000 tokens | [pricing](https://soniox.com/pricing), [async docs](https://soniox.com/docs/stt/async/async-transcription), [WS API](https://soniox.com/docs/stt/api-reference/websocket-api) |
| Smallest Pulse Pro | $0.24 | (Pulse) ~$0.24 | WAV, MP3, FLAC, Opus, μ-law, A-law, raw PCM | - | English only; 25 RPM on Standard | [Pulse Pro card](https://docs.smallest.ai/models/model-cards/speech-to-text/pulse-pro.md) |
| Cartesia Ink-2 | - | 3 credits/s; "$0.39" per hour on Scale | - | PCM s16/s32/f16/f32, μ-law, A-law; no Opus | 100 keyterms; English only per migration guide | [pricing](https://cartesia.ai/pricing), [WS ref](https://docs.cartesia.ai/api-reference/stt/websocket.md) |

Derived conversions: per-minute x 60. Cartesia Pro: $5 per 100K credits, 10,800 credits/hr, about $0.54/hr (derived from [pricing](https://cartesia.ai/pricing)).

---

## 6. Per-provider notes

**Deepgram.** Nova-3 pre-recorded is a sync REST call that "often" finishes "after only a few seconds" for files. [docs](https://developers.deepgram.com/docs/pre-recorded-audio). No published short-clip number. It has the highest AA batch speed factor (597.6), but it also has the weakest batch accuracy in this set (AA-WER 5.2%). Streaming Nova-3 has the best Pipecat TTFS (247 ms median) but a high AA streaming WER (6.59%). New accounts get $200 credit. [pricing](https://deepgram.com/pricing). The India endpoint removes about 230 ms of RTT per round trip compared with US hosts.

**ElevenLabs.** Scribe v2 has the best AA batch WER (2.2%). Batch is sync REST. Realtime has a low time to final (0.141 s), but its Pipecat WER (3.05%) is weaker than Soniox, AssemblyAI and Deepgram on that dataset. Realtime keyterms are small: 50 terms of 20 chars each.

**OpenAI.** `gpt-transcribe` launched 2026-07-28 ([Gigazine](https://gigazine.net/gsc_news/en/20260729-gpt-live-transcribe)). It accepts `prompt`, `keywords` and `languages`, and supports `stream=true` deltas. GPT Live Transcribe is the slowest streaming model in the AA table except Chirp 3, and at $1.02/hr it is the most expensive. India gets storage only, so inference runs in the US or EU.

**AssemblyAI.** Model naming is inconsistent across pages. The models reference gives API value `universal-3-pro` for "Universal-3.5 Pro" async, but the pricing page gives `universal-3-5-pro`. The Sync API (launched 2026-07-14, `https://sync.assemblyai.com/transcribe`, header `X-AAI-Model: universal-3-5-pro`) was built for push-to-talk. It does not accept compressed audio. From Asia it routes to the EU (~1.9 s for 15 s from Singapore).

**Groq.** It has the cheapest batch price ($0.04/hr), sync REST and a Whisper `prompt`. It has no streaming. The only community latency number uses `whisper-large-v3` from US-East, so the turbo number from India is unconfirmed. The nearest regions (Saudi Arabia, Finland) are about 180 ms RTT from Mumbai.

**Google.** Gemini 3.5 Transcribe has strong batch WER (AA 2.6%). It is "unary" sync. Its vocabulary is a term list only, and it cannot be combined with word timestamps. There is a free tier. Third parties say free-tier content may be used to improve Google products. [OrcaRouter](https://www.orcarouter.ai/blog/gemini-3-5-transcribe-intelligent-transcription), [WaveSpeed](https://wavespeed.ai/blog/cost-and-billing/gemini-3-5-transcribe-pricing/). Chirp 3 is the only option with a Mumbai region (Preview), but it is slow (AA speed factor 29.6; streaming t_final 1.276 s) and expensive ($0.96/hr).

**Mistral.** Voxtral Mini Transcribe V2 costs $0.18/hr. Mistral says it "processes audio approximately 3x faster than ElevenLabs' Scribe v2" (vendor claim). `context_bias` has 100 terms and is optimized for English. Voxtral Small is a chat model with audio input (`voxtral-small-latest`); AA lists it at 2.8% WER.

**Speechmatics.** Batch is a job API, which is a poor fit for 1 s. Realtime has `ForceEndOfUtterance` (~250 ms, vendor). The `sounds_like` option is unique and useful for identifiers. Melia (batch-only, from $0.129/hr, 10 h/month free) launched 2026-06-17.

**Soniox.** It has the lowest prices ($0.10 / $0.12 per hour), the richest context object (8,000 tokens of free text plus terms), and the second-best AA streaming time to final (0.054 s). Async is job plus polling, which was measured at ~3.3 s for 6 s, so use real-time with `finalize` for dictation. There is no India region yet, and regional deployment needs sales contact.

**Smallest.ai.** Pulse Pro has AA batch WER 2.4% and speed factor 284.1. It is sync HTTP and costs $0.24/hr, but it is English only and has no documented vocabulary feature. Keyword boosting (with intensifiers) exists only on Pulse streaming.

**Cartesia.** Ink-2 is streaming only, English only per the migration guide, and uses manual `finalize`. It has strong Pipecat numbers (299 ms, 1.14% WER). Opus input is not supported.

---

## 7. Unresolved questions

1. No published short-clip (10-20 s) batch latency exists for Deepgram Nova-3, ElevenLabs Scribe v2, OpenAI gpt-transcribe, Gemini 3.5 Transcribe, Voxtral Mini V2 or Smallest Pulse Pro. A measurement from India is needed.
2. Does ElevenLabs geographic routing (Singapore backend) apply to STT, or only to TTS?
3. Does Groq route Indian traffic to Saudi Arabia, Finland or the US? Is there a regional hostname?
4. Does the Deepgram India endpoint give the same latency as the global endpoint for Flux and Nova-3 streaming? Do keyterm limits differ there (beyond the documented mid-stream `Configure` restriction)?
5. Do `prompt`-based providers (OpenAI, AssemblyAI, Soniox, Groq) keep camelCase, snake_case, paths and CLI flags when the context shows them? No provider documents this.
6. Is the AssemblyAI keyterms and prompt add-on charged on the Sync API? What are its exact parameter names and limits (the blog says `keyterms_prompt` with <2,048 chars; the launch post says `word_boost`)?
7. OpenAI `gpt-transcribe`: what are the numeric limits for `prompt` and `keywords`?
8. Does Gemini Live `audioStreamEnd` force a final transcript for buffered audio, and how fast?
9. Mistral Voxtral Realtime: is there a flush or finalize message? Does it support `context_bias`?
10. What is the Speechmatics supported audio format list, and is there a sync batch path for short files?
11. Google Speech-to-Text pricing page did not render. The $0.016/min Chirp 3 rate comes from a search summary of the official page, not a direct read.
12. Primary AA streaming numbers were read through AssemblyAI's reproduction (read 2026-09-09), not from the AA page directly.
13. Is Smallest.ai Waves STT served from India for self-serve API keys?
