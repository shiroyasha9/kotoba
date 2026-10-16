# kotoba-bench-v1

Speech-to-text and cleanup benchmark for kotoba, scored against Wispr Flow history.

## Data

Input and results live outside git (the audio is personal). The owner's copy is in the runbooks folder `2026-10-15-kotoba-bench/`:

- `clips/<transcriptEntityId>.wav`, `manifest.json`, `dictionary.json`: the Wispr Flow export.
- `references.jsonl` and `review-set.json`: hand-corrected references from the review page (`review/README.md`).
- `results/`: `audio/` (16 kHz mono FLAC, WAV only if a provider rejects FLAC), `audio.jsonl`, `stt-raw.jsonl`, `cleanup-raw.jsonl`, `latency-raw.jsonl`, `run-log.jsonl` and `report.md`.

Every HTTP attempt is appended to a raw JSONL file as it completes. The report and the cost cap are computed from those files only.

## Environment

- `KOTOBA_BENCH_DATA`: the data folder above. `--data DIR` overrides it.
- `KOTOBA_ENV_FILE`: an env file with `OPENROUTER_API_KEY`. `bun run bench` loads it with `bun --env-file="$KOTOBA_ENV_FILE"`.

## Run

```sh
cd bench
bun install
bun run bench --dry-run            # plan and cost estimate, no network calls
bun run bench --limit 5            # small paid smoke run
bun run bench                      # accuracy pass (STT, cleanup), latency pass, report
bun run bench --only stt           # or cleanup, latency, report
bun run bench --only cleanup --prompt writing   # kotoba's Writing prompt on clips from Writing apps
bun run review                     # local page to hand-correct references, http://127.0.0.1:4788/
```

- Accuracy pass: `--concurrency` requests in flight (default 100). Its latency is contended (one home uplink) and is not for gates.
- Latency pass: one request at a time, `grok`, `mai` and `grok+keyterms+format` only (`LATENCY_VARIANTS` in `stt.ts`), on 40 seeded-random 10-20 s clips, the variant order reversed on every other clip. Its p50/p90 are the gate numbers.
- Passthrough STT variants run on `--probe` clips first (default 20) and extend to every clip only when their text matches the base variant on fewer than 90% of them. `--probe 0` runs every variant on every clip.
- Resume-safe: a (clip, variant) pair with a successful row is not sent again. Rerun the same command after a stop.
- Cost cap: $2 of `usage.cost` across all raw files, including earlier runs. `--cap USD` instead lets this run add at most USD on top of what the raw files already record (`probe-raw.jsonl` included). Each STT variant first runs alone on its shortest clip to measure the real price per audio second; a variant whose projected cost would pass the cap is skipped.
- 429, 5xx and network errors retry with backoff (6 attempts).

## What it measures

- STT via OpenRouter `/audio/transcriptions`: `x-ai/grok-stt-1.0` (plain, with xAI `keyterm`, and with `keyterm` plus `format` or `filler_words`; a 2026-10-15 probe showed OpenRouter forwards both), `microsoft/mai-transcribe-2` (plain, with Azure `phraseList`, and with `transcribeStyle: "clean"`). Provider options go through `provider.options.<tag>`; the report column "same text as base" flags options that the provider probably dropped.
- Baselines: Wispr `asrText` and `formattedText`; Wispr `e2eLatency` (ms).
- Cleanup: the output of the STT variant with the lowest WER over all scored clips, through Qwen 3.8 27B (Cerebras only), Gemini 3.5 Flash-Lite and Claude Haiku 5.5 with streaming, plus a no-LLM dictionary find/replace. Scored on the edited subset (against `editedText`) and on a seeded sample of 100 clips (against `pastedText`, a proxy for Wispr's accepted output).
- Synthetic Writing bench (`bun run writing`, data folder `KOTOBA_WRITING_DATA` or `--data DIR` with a copy of `dictionary.json`): the texts in `writing/texts.ts` (messages, mail and notes with fillers and self-corrections; half are traps that read like a question or a command to the assistant) spoken by the TTS in `tts.ts` (shared with `hinglish/`), transcribed with `mai+phraseList`, then cleaned with the Writing prompt. `--dry-run` plans the cost; the cap is $0.25 over its raw files. It writes `results/report.md` and `results/pairs.md` (every input and output, with the real Writing-app clips of `KOTOBA_BENCH_DATA` or `--real DIR` at the end).
- Writing cleanup (`--prompt writing`): kotoba's Writing prompt (`writingSystemPrompt`) through the same models, on the clips dictated into Writing apps (`WRITING_APPS` in `cleanup.ts`: the Writing apps of kotoba's standard rules, chat, mail and notes; browsers stay in Code). Its rows are the `<model>+writing` variants, in their own report table. kotoba ships Writing only after this run passes (`docs/release.md`).
- Reference: `editedText` when it differs from `formattedText` (after trimming), else `pastedText`, else `formattedText`.
- Metrics: normalized WER and technical-term recall (`score.ts`).

## Checks

```sh
bun run typecheck
bun test
```
