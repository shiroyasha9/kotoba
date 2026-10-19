# Latency pass 2: where the stop-to-paste time goes in 0.4.x, and a smaller upload

Date: 2026-10-19 23:24 to 2026-10-20 00:40 IST. Agent `latency-2`, branch `latency-2`. Raw rows, the saved log lines, the scripts and the run log are in `<runbooks>/2026-10-19-kotoba-latency-2/` (not in git). No app database was read. Paid spend: section 5.

## Summary

- The release app missed the gate on 2026-10-19: 10-20 s dictations p50 1,280 ms, p90 2,984 ms from the stop to ⌘V sent (n 16). The local steps take about 15 ms. The upload takes 139 ms p50 (the owner's Mac sends through a VPN tunnel, `utun4`, in 59 of 60 dictations). The server wait is the rest: 1,037 ms p50 within a minute of the last answer, 1,245 ms after a quiet minute, and it grows to 2.7 s for dictations of 40 s or more.
- The primer (`latency-pass.md`) works in part: after a quiet minute, server wait p50 went from 2,409 ms (0.3.x) to 1,466 ms, but warm is 948 ms, and the cold p90 is still 2,954 ms (n 22).
- The largest measured win that keeps quality: upload Ogg Opus at 24 kbps instead of FLAC. One fifth of the bytes (57 KB against 303 KB for a 15 s clip), stop-to-answer p50 1,238 to 995 ms and p90 2,281 to 1,632 ms (20 clips, warm, same path). WER is the same: 5.68% FLAC against 5.71% (Apple's encoder) on 80 clips, paired 95% CI -0.25 to +0.35 pp.
- Implemented in this branch (lead go, 2026-10-20 00:20 IST, after the `arch-capture` merge): the capture writes an Ogg Opus copy of each recording while it records (`App/OpusUploadWriter.swift`, framed by `OggOpusStream` in KotobaProviders), the first request sends it on MAI through OpenRouter and deletes it when it ends. Every other route, every retry and History's Transcribe Again send the FLAC, which stays the kept recording.
- Dropped after measurement: a hedge (two requests at once) on a cold route (the second request of a pair is 1-4 s slower every time, section 2.5), streaming the upload during the recording (with Opus, about 30 ms is left to win), other ZDR speech models (none clearly faster at MAI's WER).
- Measured, left for the lead and the owner: upload during the recording in segments split at pauses: for 51-82 s dictations, the stop waits only for the last segment, p50 1,875 to 1,059 ms and p90 3,868 to 1,383 ms; WER 4.3% to 5.0% on 7 clips (section 2.4).

## 1. Baseline: the release app's log, 2026-10-19

Source: `log show --last 7d` for `tech.teensy.kotoba`, category `latency` (saved as `release-latency-log-7d.txt`; only 2026-10-19 15:32-22:40 IST was still in the log store). `make latency-log FROM=<file>` and `scripts/primer-effect.ts` in the runbooks folder. kotoba Dev had no lines.

| 10-20 s dictations, MAI via OpenRouter (n 16) | p50 | p90 | max |
| --- | --- | --- | --- |
| Stop to ⌘V sent | 1,280 ms | 2,984 ms | 3,154 ms |
| Stop to uploadStart (capture end, FLAC close) | 9 ms | 16 ms | 16 ms |
| uploadStart to uploadSent (body build, upload) | 139 ms | 254 ms | 278 ms |
| Server, within a minute of the last answer (n 8) | 1,037 ms | 1,745 ms | 1,745 ms |
| Server, after a quiet minute (n 8) | 1,245 ms | 2,943 ms | 2,943 ms |
| First byte to response (answer body) | 2 ms | 4 ms | 6 ms |
| Response to ⌘V sent (replacements, save, chord release, paste) | 5 ms | 11 ms | 13 ms |

All lengths (n 60): stop to ⌘V sent p50 1,223 ms, p90 3,154 ms; after a quiet minute (n 24) 1,726 / 3,367 ms; within a minute (n 36) 1,063 / 1,540 ms.

| By length (all 60) | 0-5 s (n 12) | 5-10 s (n 18) | 10-20 s (n 16) | 20-40 s (n 9) | 40 s+ (n 5) |
| --- | --- | --- | --- | --- | --- |
| Server wait p50 | 873 ms | 921 ms | 1,057 ms | 1,595 ms | 2,736 ms |
| Body build and upload p50 | 7 ms | 74 ms | 139 ms | 292 ms | 469 ms |

- The body is base64 FLAC in JSON, about 20 KB per audio second. Through the VPN (Cloudflare SIN, about 57 ms RTT) a 368 KB body took 270 ms to leave; the one dictation on Wi-Fi (`en0`) sent 236 KB in 17 ms.
- The primer by its state at the stop:

| Quiet before the key-down, primer state at the stop | n | Server p50 | p90 |
| --- | --- | --- | --- |
| Under 40 s (warm), silent primer done | 32 | 948 ms | 1,356 ms |
| 60 s or more, silent and large primer done | 22 | 1,466 ms | 2,954 ms |
| 40-60 s, large primer done | 3 | 1,021 ms | 4,052 ms |
| 40 s or more, large primer still on its way | 3 | 885-1,941 ms | - |

  The cold set is bimodal: about 1.0-1.2 s or 2.3-3.4 s, with no link to the time since the primer answered (0.6-36 s). The primers themselves wait 1.4-3.4 s on a cold route.
- The cleanup chord (n 3): Gemini 3.5 Flash-Lite answered in 1,260-2,746 ms after the transcript (server wait 1,162-2,561 ms). Polish had no log lines; its bench numbers are in `polish.md` (DeepSeek V4.1 Flash on Together: p50 1.06 s, p90 1.33 s).

## 2. Probes, 2026-10-19 23:32 to 2026-10-20 00:12 IST

Harness: `bun run latency --exp <name>` (`bench/latency/run.ts`; new: `formats`, `codec`, `long`, `segments`, `hedgecold`, `coldcodec`, `score`, and `--parallel`, `--codecs`, `--min`, `--max`, `--zdr`). The app's request shape (base64 in JSON, ZDR, the bench dictionary as `phraseList`), one request at a time unless named, times from request start to response headers (so they include the upload). Path: the VPN tunnel as in the owner's use (`utun4`, Cloudflare SIN). Quality passes ran 6 rounds at once; their times are not used.

### 2.1 Containers the route takes (one 4.5 s clip)

FLAC, WAV, MP3 and Ogg Opus: 200. WebM Opus and M4A (AAC): 400 "Provider returned 400". Apple's encoders write AAC and Opus but no MP3, and ExtAudioFile writes no Ogg ('fmt?'); Opus in CAF writes, but the route does not take CAF.

### 2.2 FLAC against Opus, warm (20 clips of 10-20 s, order rotated)

| Body | Size p50 | Stop to answer p50 | p90 | min |
| --- | --- | --- | --- | --- |
| FLAC (the app) | 303 KiB | 1,238 ms | 2,281 ms | 968 ms |
| Opus 24 kbps (libopus, voip) | 57 KiB | 995 ms | 1,632 ms | 863 ms |
| Opus 16 kbps | 38 KiB | 915 ms | 1,639 ms | 834 ms |

### 2.3 Quality: 80 clips of 5-40 s, against the owner's references

| Body | WER | Paired difference to FLAC, 95% CI | Term recall | Same text as FLAC |
| --- | --- | --- | --- | --- |
| FLAC | 5.68% (232/4,083) | - | 13/21 | 75/80 (FLAC sent twice) |
| Apple Opus 24 kbps, kotoba's Ogg framing (the app's encoder) | 5.71% | -0.25 to +0.35 pp | 14/21 | 54/80 |
| libopus 24 kbps | 5.76% | -0.21 to +0.34 pp | 14/21 | 61/80 |
| libopus 32 kbps | 5.85% | -0.18 to +0.60 pp | 14/21 | 54/80 |

MAI is not deterministic: the same FLAC twice gave another text on 5 of 80 clips. 24 kbps is the pick: no loss, and 32 kbps is no better.

### 2.4 Long dictations, and upload in segments during the recording

- One 81 s clip cut to 15/30/45/60 s, FLAC, 3 runs each: p50 2,943 (1,232-4,457), 1,762, 1,975, 1,965 ms. A slow period on the route; it shows the spread, not a slope.
- Segments: 12 clips of 40 s or more, cut at the middle of the first pause of 0.4 s (under -40 dB) after each 15 s; 7 had such pauses (51-82 s, 3-5 segments). The whole clip, then its segments one after the other (as an app would send them while the owner speaks), 2 runs:

| | n | p50 | p90 | Body p50 |
| --- | --- | --- | --- | --- |
| Whole clip (what the stop waits for today) | 14 | 1,875 ms | 3,868 ms | 1,546 KiB |
| Last segment (what the stop would wait for) | 14 | 1,059 ms | 1,383 ms | 344 KiB |

  WER, segments joined with a space: 5.0% (74/1,488) against 4.3% (64/1,488) for the whole clip, 7 clips. No word was lost at a cut; the extra errors are fillers kept at segment starts and words the model hears differently without the context.

### 2.5 Hedge on a cold route (10 sets)

Each set as the app on a cold route: 65 s quiet, the silent primer, the large one when it answered, then 12 s after the start the same 10-20 s clip as two requests at once (A, B), then once more (C).

| | p50 | p90 | max |
| --- | --- | --- | --- |
| Faster of the pair | 1,330 ms | 2,456 ms | 2,798 ms |
| Slower of the pair | 3,594 ms | 4,908 ms | 5,205 ms |
| C, alone right after | 1,243 ms | 2,910 ms | 3,302 ms |

Pairs (fast/slow, ms): 1432/3412, 2456/3459, 1831/3474, 995/5205, 1351/4908, 1038/4047, 1188/3396, 1223/3357, 1330/3728, 2798/4375. In every pair one request is 1-4 s slower: on a cold route, a second request at the same time pays a cold path the first does not. So the two are not independent draws, and the faster one is likely what a single request gets. The control set (`coldcodec`, the same sets with one request, FLAC or Opus by turns) ran at 2026-10-20 00:00-00:11 IST, when the route was slow (silent primers 1.1-11.3 s); its rows are in the raw file and not used.

### 2.6 Other models through OpenRouter, ZDR endpoints only (10 clips, rotated)

| Model | p50 | p90 | WER | Terms |
| --- | --- | --- | --- | --- |
| MAI-Transcribe-2 (the app, phrase list) | 1,259 ms | 1,764 ms | 5.1% | 3/4 |
| AssemblyAI Universal-3.6 Pro (no keyterms sent) | 1,039 ms | 1,928 ms | 6.1% | 1/4 |
| Fish Audio Transcribe 1 | 1,191 ms | 1,448 ms | 5.9% | 1/4 |
| Voxtral Mini Transcribe | 404: no ZDR endpoint | | | |

OpenAI GPT Transcribe, Gemini 3.5 Transcribe and Meta Muse Voice have no ZDR endpoint (`GET /endpoints/zdr`) and were not sent.

### 2.7 The encoder's cost (standalone probe, `App/OpusUploadWriter.swift` compiled with `OggOpusStream`)

- Apple's Opus encoder runs at about 145x real time: a whole 20 s recording at the stop would cost about 140 ms, so the copy is written during the recording.
- Fed in the capture writer's 300 ms chunks: 2.0 ms mean, 3.9 ms worst per chunk on the writer thread (under 1% of one core); the close (the encoder's tail and the last page) 0.3-1.8 ms. So the stop gets about 2-6 ms longer and the body build about 1-2 ms shorter.
- Output: `ffmpeg -err_detect crccheck` finds no CRC error; AVAudioFile reads it at exactly the recording's length (336,128 frames at 16 kHz read as 1,008,384 at 48 kHz).
- Memory: +0.5 MiB footprint after the first recording (the codec loads), flat over the next ones (3 rounds: +0.48, +0.53, +0.56 MiB).

## 3. Changes

### 3.1 In this branch

1. `OggOpusStream` (`KotobaProviders/Sources/KotobaProviders/OggOpusStream.swift`): the two Opus header pages and audio pages of whole packets (RFC 3533, RFC 7845), a page per 50 packets (one second) or before 255 lacing values. A full page waits for the next packet, so the last page always holds packets and its granule (the recording's own length) trims the encoder's padding (Codex review, 2026-10-20). Tests: `OggOpusStreamTests` (6): the header bytes ffmpeg checked, a decode by AVAudioFile at the exact length, lacing, the page limits, the trim on a full last page.
2. `OpusUploadWriter` (`App/OpusUploadWriter.swift`): AVAudioConverter to Opus at 24 kbps, 20 ms packets, framed by `OggOpusStream`.
3. `CaptureWriter` (`App/CaptureWriter.swift`, "Upload copy"): after each FLAC chunk it writes the same chunk to the copy, at the path the capture gives it. The writer is made at the first chunk on the writer thread, not at the key-down. At its first failure (or a failed FLAC write) the copy is dropped and deleted, and the stop returns no copy: the upload sends the FLAC, with nothing for the owner to see. Pause and resume (Esc, Undo) keep the same writer.
4. `RecordedAudio.upload` and `AudioCapture` (KotobaCore): the copies go in one folder of their own (`<temporary folder>/<bundle id>.upload-copies`, so kotoba and kotoba Dev keep apart), which the first `prepare` after a launch empties (a copy that a quit or a crash left). `discard(_:)` deletes the copy with the FLAC, so a discard, an Esc that ends in a discard and the mic test leave no copy. Tests: `AudioCaptureUploadCopyTests` (5), through the `CaptureHardware` fake.
5. The first request only (`TranscriptionSteps.transcribe`, `KotobaCore/Sources/KotobaCore/TranscriptionSteps.swift:47-52`; `DictationPipeline.Settings.request(for:at:)`, `KotobaCore/Sources/KotobaCore/PipelineInterface.swift:254`): the request carries the copy, and the copy is deleted when that request ends, answered or not (Codex review, 2026-10-20: a copy kept for later outlived a History delete and a quit). So the copy is on disk only from the recording to its first answer; a retry, and History's Transcribe Again, send the FLAC. `TranscriptionRoute.takesOggOpus`: MAI through OpenRouter sends the copy as `input_audio.format: "ogg"`, opened before the body is written; every other route sends the FLAC. Tests: `PipelineUploadCopyTests` (3), `OpenRouterOpusUploadTests` (5).
6. Bench: the probes of section 2 in `bench/latency/run.ts`.

Measured cost (standalone probe of `OpusUploadWriter`, Release-like `-O`): key-down none (the writer is made on the writer thread; its init takes 9.3 ms the first time in a process and 0.26 ms after, and delays only the copy's first chunk); 6.7 ms of encode per second of recording on the writer thread (an 81 s clip in 300 ms chunks), so under 1% of one core; 0.4-1.8 ms at the stop to close the copy; +0.5 MiB footprint once the codec loads. The body build reads 57 KB instead of 303 KB for a 15 s dictation.

## 4. Checked, no change

- Upload during the recording as one streamed request (`latency-pass.md` section 4): with Opus, a 15 s body is 57 KB, which leaves the Mac in 1-60 ms even through the VPN. About 30 ms is left to win, for an open request through every recording. Dropped.
- Hedge: section 2.5. On a cold route the second request of a pair is the slow one, so a hedge does not sample two independent paths. On a warm route (2026-10-17, 20 pairs) it cut the two spikes, at twice the speech cost. Not built; it needs an in-app A/B with `make latency-log` (owner decision: it doubles the speech bill).
- HTTP/2 and connection reuse: every upload line reused the warmed HTTP/2 connection (`reused true, protocol h2, connect none, tls none`). Nothing to win.
- Local steps after the answer: 2 ms answer body and 5 ms p50 (11 ms p90) to ⌘V sent. Nothing to win.
- Other models: section 2.6. AssemblyAI is about 0.2 s faster at p50 on 10 clips, slower at p90, and its WER is higher without keyterms. Not a clear win; an owner decision with a full bench.
- A streaming speech endpoint: OpenRouter's speech API is still batch only (2026-10-19 docs). The routes in `latency-pass.md` section 4 (Vercel WebSocket, Azure direct) need an account.

## 5. Cost

$0.33 of `usage.cost` in the two raw files (`results/latency-raw.jsonl`, `quality/results/latency-raw.jsonl`), of the $1.50 cap. Paid wall time about 34 minutes, over the 30 minute cap: the two cold sets (`hedgecold`, `coldcodec`) need 65 s of quiet each and took 15 and 11 minutes.

## 6. Owner trial

1. `make build`, run kotoba Dev, dictate as usual for a day (Wi-Fi with and without the VPN).
2. `make latency-log DEV=1 LAST=1d`: the upload lines show `sent` about 4 KB per audio second (FLAC: about 20 KB), and stop to ⌘V sent for 10-20 s dictations near p50 1.0 s.
3. Listen to two History recordings: the kept file is still the FLAC.
4. After a dictation, an Esc whose Undo window passed, and a Settings mic test: the folder `tech.teensy.kotoba.dev.upload-copies` in the temporary folder (`$TMPDIR`) is empty.

## Unresolved questions

1. Does a cold route still need the large primer when the dictation's own body is a fifth of the size? The `coldcodec` control ran during a slow period; rerun it, or read `make latency-log` after a day of use (the after-a-quiet-minute set).
2. Does a single request on a cold route get the faster time of a hedge pair (section 2.5)? Needs the `coldcodec` FLAC sets on a normal day.
3. Segments for long dictations (section 2.4): is +0.7 pp WER on 7 clips real, and is the gain worth an upload per pause? Lead and owner decision; it needs the capture to cut at pauses and the pipeline to join texts.
