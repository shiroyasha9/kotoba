# Benchmark sources - Wispr Flow local data and OpenRouter STT

Collected 2026-10-15. All times are IST. We opened no SQLite or DB file and read no app-data file contents. We used only names, sizes and dates. We used no API key.

## 1. Wispr Flow local data on this Mac

App: `/Applications/Wispr Flow.app`, version 1.6.1147.

### What exists

| Path (under `~/Library/`) | Size | Notes |
|---|---|---|
| `Application Support/Wispr Flow/` | 700 MB | Main data dir. Oldest item `avatars/` 2025-12-01. |
| `.../flow.sqlite` | 383.6 MB (383,569,920 B), mtime 2026-10-15 19:21 | Main DB. Also `flow.sqlite-wal` 8.1 MB, `flow.sqlite-shm` 32 KB. |
| `.../backups/` | 320 MB | One full backup: `backup-2026-10-14T06-30-00.818Z.sqlite` (334.9 MB, 2026-10-14 12:00). Also 37 leftover `.backup-<date>.sqlite.tmp-wal` / `-shm` pairs (all 0 bytes), dated 2026-06-12 to 2026-10-14 (UTC in the names). The app makes a daily backup at 06:30 UTC and keeps one. |
| `.../meetings/` | 436 KB | 3 meeting dirs (UUID names). Each has `live.ndjson` (78-128 KB) and `refined.ndjson` (30-61 KB); 2 of 3 have `audio-devices.json`. File mtimes 2026-08-05, 2026-09-24, 2026-10-01. The names suggest a raw live transcript and a refined pass (not confirmed - we did not read them). |
| `.../Local Storage`, `Session Storage`, other Chromium dirs, `Cache` (808 KB), `sentry` (36 KB), `config.json` (46 KB), `feature-flags-cache.json`, `session.json` | small | Electron/Chromium profile state. |
| `.../blob_storage/` | 0 B | Empty. |
| `Caches/com.electron.wispr-flow/` | 540 KB | `Cache.db` (+wal) = NSURLCache HTTP cache. |
| `Caches/com.electron.wispr-flow.ShipIt/` | 16 KB | Updater. |
| `Caches/com.electron.wispr-flow.accessibility-mac-app/` | 0 B | |
| `HTTPStorages/com.electron.wispr-flow/` | 616 KB | `httpstorages.sqlite` (+wal), cookies store. |
| `Logs/Wispr Flow/` | 0 B | Empty. |
| `Preferences/com.electron.wispr-flow.plist` | 237 B | |
| `Containers/*wispr*`, `Group Containers/*wispr*` | none | Not present. |

### Findings

- **Database file:** Yes. `flow.sqlite` (383.6 MB) plus one 334.9 MB backup.
- **Stored audio files:** **0.** A search for `.wav .webm .opus .m4a .ogg .flac .mp3 .aac .pcm` in all Wispr dirs above returned no files. So no audio date range exists on disk as files.
- **Inference (not verified):** The public docs say that desktop audio stays on the device for 14 days (see below). No audio files exist, and the DB is large (384 MB). Thus the audio is probably kept as BLOBs inside `flow.sqlite`. To confirm this, we must look at the DB schema, which the rules for this task do not allow.
- **Total size:** about 702 MB (700 MB Application Support + ~1.2 MB caches/HTTPStorages).

### Public descriptions of Wispr Flow local storage

- Wispr help, "Can I upload audio files to Wispr Flow for transcription?": "Flow clears local audio from already-uploaded history records older than 14 days, but keeps transcript text." "Records not yet uploaded keep their audio." Applies to Mac and Windows. A search summary of the same page also says you can play back or download a recording as `.wav` from History for up to 14 days, that audio is stored locally per device and does not sync, and that no audio is saved under a "Never store" policy. https://docs.wisprflow.ai/articles/7689167034-can-i-upload-audio-files-to-wispr-flow-for-transcription
- Wispr help, "Delete transcripts and history in Wispr Flow": the Mac/Windows options are "Store data locally" (default, "Stores dictation transcripts locally"), "Auto-delete local data every 24hrs", and "Never store data locally" ("stops storing new transcripts and polish records locally"). Deleting local history "does not necessarily remove copies already uploaded to Wispr's servers." https://docs.wisprflow.ai/articles/4465314211-delete-transcripts-and-history-in-wispr-flow
- Wispr Consumer Data Usage Policy (May 2024): by default Flow stores data locally, and audio recordings are on that list. https://www.wispr.ai/data-usage
- Wispr enterprise privacy overview (search snippet only, page returned 404 on fetch): transcripts, and optionally audio, are stored locally to support recovery cases. https://wisprflow.ai/post/enterprise-privacy-and-security-overview
- Third-party blog (secondary source) on the same three retention options: https://www.yaps.ai/ja/blog/is-wispr-flow-safe
- **Raw ASR vs edited/final text:** No public source documents the `flow.sqlite` schema. The docs mention "transcripts" and "polish records" (two kinds of record), but no page says that the raw ASR output and the user's later edits are kept as separate fields. One unofficial page (not citable) named a `History` table with "formatted text". **Not confirmed.**
- **Retention:** transcripts are kept until deletion (default). Audio is kept for 14 days after upload (desktop), and audio that is not uploaded is kept with no limit.

## 2. OpenRouter speech-to-text models

Sources: `GET https://openrouter.ai/api/v1/models?output_modalities=transcription` (no key, 26 models). Per-model `GET /api/v1/models/<slug>/endpoints` (no key). Raw JSON is saved in `scratchpad/or/`. Note: the plain `/api/v1/models` (461 models) does not list STT models. Use `output_modalities=transcription` or `=all` (668).

### Models and prices

The API gives `pricing.prompt` per second of audio for duration-priced models (`openai/whisper-1` = $0.0001/s = $0.006/min, which is OpenAI's list price). **Exception:** the two Microsoft MAI models show `0.1` and `0.36`. These numbers are the same as Microsoft's published **$/hour** prices, so we read them as $/hour. The API does not state the unit. **Not confirmed.** Three models are priced per token.

| Model id | Provider tag | $/min | $/hour |
|---|---|---|---|
| `x-ai/grok-stt-1.0` (name "SpaceXAI: Grok STT 1.0", canonical `x-ai/grok-stt-20260723`) | xai | 0.0017 | 0.100 |
| `microsoft/mai-transcribe-2` (canonical `-20260903`, diarization: yes) | azure | 0.0017* | 0.10* |
| `microsoft/mai-transcribe-1.5` | azure | 0.0060* | 0.36* |
| `assemblyai/universal-3-6-pro` | assemblyai | 0.0050 | 0.300 |
| `assemblyai/universal-3-5-pro` | assemblyai | 0.0050 | 0.300 |
| `deepgram/nova-3` | deepgram | 0.0043 | 0.258 |
| `elevenlabs/scribe-v2` (diarization: yes) | elevenlabs | 0.0018 | 0.110 |
| `elevenlabs/scribe-v2-medical` (diarization: yes) | elevenlabs | 0.0018 | 0.110 |
| `fish-audio/transcribe-1-pro` | fish-audio | 0.0060 | 0.360 |
| `fish-audio/transcribe-1` | fish-audio | 0.0060 | 0.360 |
| `google/chirp-3` | google-vertex | 0.0160 | 0.960 |
| `google/gemini-3.5-transcribe` | google-ai-studio | token: $2/M in, $12/M out | - |
| `meta/muse-voice-transcribe-1.0` (1-day uptime 81%) | meta | 0.0030 | 0.180 |
| `mistralai/voxtral-mini-transcribe` | mistral / mistral/eu | 0.0030 / 0.0033 | 0.180 / 0.198 |
| `mistralai/voxtral-small-24b-2507-stt` | deepinfra/bf16 | 0.0030 | 0.180 |
| `mistralai/voxtral-mini-3b-2507` | deepinfra/bf16 | 0.0010 | 0.060 |
| `nvidia/nemotron-3.5-asr-streaming-multilingual-0.6b` | deepinfra/us | 0.0002 | 0.012 |
| `nvidia/parakeet-tdt-0.6b-v3` | together | 0.0015 | 0.090 |
| `openai/gpt-transcribe` | openai | 0.0045 | 0.270 |
| `openai/gpt-4o-transcribe` | openai | token: $2.50/M in, $10/M out | - |
| `openai/gpt-4o-mini-transcribe` | openai | token: $1.25/M in, $5/M out | - |
| `openai/whisper-1` | openai | 0.0060 | 0.360 |
| `openai/whisper-large-v3` | deepinfra/us / together / groq | 0.0004 / 0.0015 / 0.0018 | 0.027 / 0.090 / 0.111 |
| `openai/whisper-large-v3-turbo` | deepinfra/us / groq | 0.0002 / 0.0007 | 0.012 / 0.040 |
| `qwen/qwen3-asr-1.7b` | deepinfra/us | 0.0004 | 0.027 |
| `qwen/qwen3-asr-0.6b` | deepinfra/us | 0.0002 | 0.012 |

\* unit inferred, see above.

**xAI Grok Voice Transcribe 2.0:** **not listed on OpenRouter** as a separate id. The only xAI STT entry is `x-ai/grok-stt-1.0` (created 2026-07-23 UTC). OpenRouter does not say whether xAI now serves 2.0 behind this slug. Secondary reports say xAI released Grok Voice Transcribe 2.0 on 2026-09-18 at $0.10/h batch, made it the API default, and allows pinning `grok-voice-transcribe-1.0`. That makes it possible that this slug now gets 2.0, but this is **not confirmed**. Sources: https://unite.ai/xai-releases-grok-voice-transcribe-2-0-speech-to-text-model/ , https://www.llmreference.com/provider/xai-console/grok-voice-transcribe-2.0 , xAI STT/TTS launch post ($0.10/h batch, $0.20/h streaming): https://x.ai/news/grok-stt-and-tts-apis

**Microsoft MAI-Transcribe-2:** listed as `microsoft/mai-transcribe-2`, Azure only. Microsoft price is $0.10/audio hour, which press reports call an introductory rate through end-2026: https://www.eweek.com/news/microsoft-10-cent-ai-transcription-mai-transcribe-2/ , https://www.channelinsider.com/ai/news-microsoft-mai-transcribe-2-ai-transcription/

### Endpoint, params, formats (OpenRouter STT guide)

Source: https://openrouter.ai/docs/guides/overview/multimodal/stt (also `.md`), and blog https://openrouter.ai/blog/tutorials/transcription-on-openrouter/ , collection https://openrouter.ai/collections/speech-to-text-models

- Endpoint: `POST /api/v1/audio/transcriptions`. JSON with `input_audio: {data: <base64, no data URI>, format}`. An OpenAI-compatible multipart form is also accepted.
- TS SDK: `openRouter.stt.createTranscription({ model, inputAudio: { data, format } })` returns `.text`.
- Normalized top-level params: `language` (ISO-639-1, auto-detected if you omit it), `temperature` (0-1), `response_format` (`json` | `verbose_json`), `timestamp_granularities` (`segment`/`word`, only with verbose_json).
- **prompt:** not a top-level param. In multipart it is "accepted but ignored". It passes through only as a provider option (Groq example: `provider.options.groq.prompt`).
- **keyterms / phrase list:** not documented at all. Only route is `provider.options.<provider-tag>.<native field>`. Only the serving provider's options are forwarded, with the provider's own field names. Some providers drop unknown fields and do not tell you. Azure can return an error. Documented examples: Deepgram `punctuate`, `diarize`, `smart_format`, `detect_language`; Azure `diarization.enabled` (MAI-Transcribe-2).
- `supported_parameters` is `[]` for all 26 models in the Models API. The API gives no per-model param list.
- Formats: `wav`, `mp3`, `flac`, `m4a`, `ogg`, `webm`, `aac`. Support changes with the provider. `opus` is not listed.
- Limits: multipart 25 MB. Base64 JSON above 25 MB is accepted only for OpenAI and Groq models. `input_audio.url` works for models that take URLs. Upstream timeout is 60 s per request. `text`/`srt`/`vtt` output returns 400. `openai/gpt-4o-transcribe` and `microsoft/mai-transcribe-1.5` reject `verbose_json`.
- Response: `text`, plus `usage.seconds`, `usage.input_tokens`/`output_tokens`/`total_tokens`, `usage.cost` (USD). Header `X-Generation-Id`.
- Routing: if more than one provider serves a model, the load is balanced between them. `order`, `only`, `ignore` are **not applied** to transcription. Only `provider.zdr` and `provider.data_collection` apply. BYOK is supported.
- **Region:** The STT guide does not mention regions or data residency. The only region signal is the endpoint `tag` in the endpoints API: `deepinfra/us` (US) and `mistral/eu` (EU, $0.000055/s vs $0.00005/s). The tags for xAI (`xai`) and Azure (`azure`) give no region. Because `only`/`order` do not apply to STT, you cannot choose the region-tagged endpoint (e.g. `mistral/eu`) for a request. **Not confirmed.**

## Unresolved questions

- Does `flow.sqlite` keep audio BLOBs, raw ASR text, and user-edited text as separate columns? Only a schema read can confirm this, and the rules for this task do not allow it.
- Is the `0.1` / `0.36` price for the MAI models in $/hour? The API does not state a unit. A one-request `usage.cost` check would confirm it, but that is a paid call.
- Does `x-ai/grok-stt-1.0` on OpenRouter now route to Grok Voice Transcribe 2.0?
- Can xAI keyterm biasing (reported up to 100 terms on 2.0) pass through `provider.options.xai`? Not documented.
