# Quality and performance, pass 2: faster paste, better words, less memory

Date: 2026-10-16 (work at 09:45-10:45 IST). Agent `quality-perf-2`. Read-only on code: no source changed, no commit, no paid API call, no database read. Inputs: `docs/spec.md`, the research files named below, the kotoba-bench-v1 report and raw rows in `<runbooks>/2026-10-15-kotoba-bench/results/` (numbers only, no clip text), the synthetic Hinglish run in `<runbooks>/2026-10-16-kotoba-hinglish/`, the hot path in `KotobaCore` and `KotobaProviders`, current vendor docs (read 2026-10-16), and free network timings from this Mac.

## Summary

- The stop path in the app does about 20 ms of local work. The rest is one HTTP round trip through OpenRouter. In kotoba-bench-v1 that round trip has a fixed part of about 580-890 ms and a part that grows with the clip of about 6-26 ms per audio second (fit over the 40-clip sequential pass, section 1). So the fixed upstream part (OpenRouter to Azure, and Azure itself) is the largest cost, and upload is the second.
- The in-app gate (stop tap to Cmd-V sent) has never been measured on real dictations. The latency log does not split upload time from server time. Fix this first (L1): it costs nothing and tells which of the other changes is worth its effort.
- Network path matters more than expected. At 10:38 IST today a tunnel interface (`utun`) was the default route on this Mac, and every provider host had about 60 ms TCP connect (openrouter.ai served from Cloudflare SIN, Azure `centralindia` too). On 2026-10-15 the same hosts had 5-10 ms (Cloudflare BOM, Pune). A 325 KB upload on a fresh TCP window took about 390 ms on the 60 ms path although the uplink measured about 37-51 Mbps. kotoba's body for a 15 s clip is about 318 KB (FLAC as base64 in JSON).
- Upload while recording (L2) removes the upload from the stop path on every route: about 60-110 ms on a 10 ms path, about 300-400 ms on a 60 ms path (estimates from the timings above). Two facts are unverified: that OpenRouter accepts a slowly streamed body, and that a FLAC stream with an unfinished header is accepted. A spike of about $0.003 answers both.
- Accuracy is better than the headline 8.1% WER shows. On the 62 hand-corrected references, MAI + phraseList has WER 3.3% (95% CI 1.6-5.8%) and term recall 84.6% (44/52); Wispr's own ASR has 6.0% and 50.0%. The weak point is the reference set itself: 62 clips cannot separate two good providers. Every LLM cleanup doubled WER on the same clips (5.3% raw vs 10.5-19.9%).
- A latent accuracy fault: `PersonalDictionary.keyterms` (`KotobaCore/Sources/KotobaCore/PersonalDictionary.swift:22`) sends the first 100 terms in stored order, and new terms are appended at the end (`:159`). When auto-learning grows the list past 100, the newest learned words, and every rule's spelling, stop reaching the model, with no sign to the owner. Rank and cap (Q2) fixes this.
- New vendor facts (read 2026-10-16): ElevenLabs Scribe v2 is now on OpenRouter at $0.11/h (AA-WER 2.2%, up to 1,000 keyterms), AssemblyAI Universal-3.6 Pro at $0.30/h (free-text `prompt`). OpenRouter and xAI serve HTTP/2 only (no h3). MAI-Transcribe-2 still has no published phrase-list limit, no free-text prompt and no post-2026 price.
- Idle memory: the release shape idles at 15.4-15.9 MB (`memory-spike.md`), but `make build` makes the Debug app the owner runs daily (`Makefile:20`). Its footprint and CPU cost are not measured.
- First three changes: L1 (split the network time in the latency log, then run the gate), Q2 (rank and cap dictionary terms), L2 spike (upload while recording). Section 7.

## 1. Where the time goes now

### 1.1 The stop path in code

From the stop event to Cmd-V (`KotobaCore/Sources/KotobaCore/PipelineRecording.swift:121`, `TranscriptDelivery.swift:43`):

| Step | Where | Cost | Source |
| --- | --- | --- | --- |
| Capture end: wait for the hardware cycle that holds the stop moment, drain the ring, flush the converter, close the FLAC | `App/AudioCapture.swift:179`, `App/CaptureWriter.swift:298` | stop wait 5.6-13.2 ms; close not measured | `memory-spike.md`, "Stop wait" |
| Body build: copy the FLAC as base64 into a temp file (OpenRouter), or as binary multipart (Azure, xAI) | `KotobaProviders/Sources/KotobaProviders/ProviderHTTP.swift:53`, `OpenRouterProvider.swift:42` | about 7.85 ms per MiB in a probe, so about 2 ms for 240 KB | `perf-pass-codex.md` |
| Pending row save | `TranscriptDelivery.swift:58` | runs while the upload runs | code |
| Upload, OpenRouter, Azure, response | `ProviderHTTP.swift:72` | p50 881 / p90 1461 ms (bench, sequential, 10-20 s clips) | bench report |
| Clipboard write, Cmd-V | `TranscriptDelivery.swift:138`, `App/Paste.swift:117` | about 1 ms; snapshot taken at the cue, no fixed sleep | code |
| Chord release (tap mode: the stop is the second key-down) | `PipelineDelivery.swift:54` | overlaps the network wait | code |

The connection is warmed at key-down with a `HEAD` request (`ProviderHTTP.swift:42`). It opens TCP and TLS and reads the key. It does not grow the TCP send window: a HEAD sends a few hundred bytes. So the first large upload on the warm connection still starts in slow start. This is inference from TCP rules (RFC 6928 initial window of 10 segments); L1 measures it.

### 1.2 Fixed part and per-second part (bench raw rows)

Least-squares fit of latency against audio seconds over the sequential latency pass (`latency-raw.jsonl`, 40 clips per variant, 10-20 s clips, warm keep-alive from bun, 2026-10-15 about 20:10 IST):

| Variant | p50 ms | Fixed part (intercept) ms | Per audio second ms | Body per audio second |
| --- | --- | --- | --- | --- |
| mai | 881 | 582 | 26.3 | 21.5 KB |
| mai+zdr | 904 | 890 | 6.5 | 21.5 KB |
| grok | 1112 | 1217 | 3.3 | 21.5 KB |

Reading: for a 15 s clip, about 100-390 ms grows with the body (upload, upstream transfer, compute) and about 600-900 ms does not. MAI's compute is about 15 s / 314 = 48 ms (AA speed factor, `speech-apis.md` 4a). The fit is noisy (40 points per variant), but both MAI variants agree that the fixed part is the larger one. The synthetic Hinglish run (2026-10-16, 01:11 IST) had MAI p50 about 1,020 ms on 9 s clips: higher on shorter clips, so the fixed part also moves with the time of day.

### 1.3 Network from this Mac today

Free timings with `curl`, 2026-10-16 10:37-10:38 IST (05:07 UTC):

| Measure | Value |
| --- | --- |
| Default route | a tunnel interface (`utun4`); `scutil --nwi` lists it before `en0` |
| TCP connect: openrouter.ai, api.x.ai, ai-gateway.vercel.sh, centralindia.api.cognitive.microsoft.com | 59-64 ms each (2026-10-15: 5-10 ms) |
| openrouter.ai Cloudflare colo | SIN (2026-10-15: BOM) |
| Uplink, 6 MB POST to speed.cloudflare.com (SIN) | 4.6-6.4 MB/s (37-51 Mbps) |
| 325 KB POST, cold connection, after TLS | 375-570 ms (5 runs after the first: 375-400 ms) |
| 60 KB POST, cold connection, after TLS | 180-270 ms |

At 45 Mbps, 325 KB needs about 58 ms on the wire. The measured 375-400 ms is about 6 round trips: slow start, not bandwidth. A body of the same size on a 10 ms path costs about 6 x 10 ms + 58 ms = about 120 ms. So the same dictation can be 250-300 ms slower when the tunnel is on. The owner decides whether provider hosts go around the tunnel; kotoba can only log the path (L1).

## 2. Latency items

### L1. Split the network time in the latency log, then run the gate

- Change: `UploadMetrics` (`ProviderHTTP.swift:264`) already logs reuse, protocol, connect and TLS. Add from `URLSessionTaskTransactionMetrics`: `requestStartDate` to `requestEndDate` (upload), `requestEndDate` to `responseStartDate` (server wait), `countOfRequestBodyBytesSent`, `remoteAddress`. Return the two instants in `Transcript` (the spec's provider output already names "timing", `docs/spec.md` "Transcription providers"), and record them as two new `LatencyMark`s (`uploadSent`, `firstByte`) so `make latency` can split them. Log the interface type of the path (`NWPath`) with the line, so a tunnel shows.
- Gain: none by itself. It decides L2, L3 and L4 with data instead of estimates.
- Evidence: no in-app gate number exists (`docs/progress.md` follow-up; `log show` for the latency category returned nothing, since info lines are not kept).
- Cost: S. One metrics callback per request, after the response; no hot-path work.
- Measure: `make latency RUN=1` after 30 or more real 10-20 s dictations (owner go: it reads the app database).
- Risk: low. The marks come from the system's metrics, which arrive after the answer; the pipeline must not wait for them.

### L2. Upload while recording

- Change: open the POST when the dictation is announced (after the tap threshold, so a discarded shortcut press sends nothing), with `URLSession.uploadTask(withStreamedRequest:)` and a bound stream pair. The writer thread (`CaptureWriter.swift:227`) already writes FLAC frames every 100 ms; it also hands the new bytes to the stream (base64 for OpenRouter, raw for multipart). At the stop, only the last frames and the closing fields remain. The FLAC file stays the record of truth: on any stream error, on Esc/Undo, or past a length limit (OpenRouter's upstream timeout is 60 s), the dictation falls back to today's upload from the file. The retry queue does not change.
- Gain (estimate): the upload leaves the stop path. About 60-110 ms on a 10 ms path at 45 Mbps; about 300-400 ms on today's 60 ms path (section 1.3). It also hides the body build (about 2 ms). It does not touch the fixed upstream part.
- Evidence: section 1.2 (per-second part 100-390 ms for 15 s), section 1.3 (slow start dominates). Wispr streams 1 s chunks during speech (`speech-apis.md` 8).
- Unknowns, each a stop condition for the spike: (a) whether OpenRouter's Worker accepts a request body that arrives over 10-60 s; (b) whether `AVAudioFile` writes FLAC frames as it goes and fills STREAMINFO only at close; a stream would then carry `total_samples = 0`, which the FLAC format allows ("unknown"), but MAI's decoder may not; (c) whether Azure direct accepts a chunked multipart body (Microsoft documents only size and duration limits, read 2026-10-16).
- Cost: L. A second consumer of the writer's bytes, a cancel path for Esc/Undo, a fallback, tests through the provider seam.
- Measure: spike first (5 requests of about 20 s, about $0.003, under 5 minutes, owner go). Then `uploadSent` to `firstByte` from L1 before and after.
- Risk: medium. More moving parts on the hot path; an open request during every recording. The fallback keeps "never lose a dictation".

### L3. MAI direct from Azure `centralindia`

- Change: none in code. The route exists (`AzureProvider.swift`), untested live. The owner needs an Azure Speech resource in `centralindia` (Azure free account: $200 for 30 days, `speech-apis.md` 3).
- Gain (estimate): part of the 600-900 ms fixed part. OpenRouter cannot pick a region, and its Azure region for MAI is unpublished (`mai-routing.md` 1). If that region is in the US, the extra hop is about 200 ms RTT per round trip (`speech-apis.md` 5b). Range: 0-400 ms. Low confidence.
- Evidence: Pune endpoint 9 ms TCP on 2026-10-15 (`mai-routing.md` 4). Also removes base64 (body 239 KB instead of 318 KB).
- Cost: S in code; owner account set-up; a bench variant (bench/stt.ts, about 2 h agent work).
- Measure: bench latency pass on the same 40 clips, `mai` vs `azure-direct`: 10 min of audio x 2, about $0.035, about 5 minutes. Plus the accuracy pass on 252 clips (about $0.17), because spec question 4 (`transcribeStyle` default) is open.
- Risk: low in code. Public preview, no SLA; one more key to manage.

### L4. Hedge the tail

- Change: when no answer has come `h` ms after upload start, send the same audio again (a second connection, or the other MAI route) and take the first answer; `FirstOf` (`TranscriptionSteps.swift:160`) already does "first of two". Bill both.
- Gain (estimate): p90 only. If tails are independent, sending both at once moves p90 from about 1,461 ms to about the single-request p68 (about 1,000 ms). A late hedge (`h` near p50) does not help the 1.5 s gate, because the second request needs a full round trip.
- Evidence: bench p90/p50 = 1.66 for `mai`; max 2,035 ms. "The Tail at Scale" pattern. Correlation between two OpenRouter requests is unknown: both share the edge and the upstream.
- Cost: M. Up to 2x STT cost (at most +$0.10 per hour of audio) and 2x upload bytes, which hurts on a slow path.
- Measure: bench variant "mai x2 in parallel", 40 clips, about $0.035, about 3 minutes. Compare p90 of the minimum with p90 of one.
- Risk: medium. It works against the root cause only if the tail is upstream noise, not upload. Decide after L1.

### L5. Smaller audio: Opus

- Change: encode Opus (about 3 KB/s at 24 kbps) instead of FLAC (about 16 KB/s) for routes that accept it.
- Gain (estimate): 5x smaller body, so 2-3 slow-start rounds instead of 5-6: about 40 ms on a 10 ms path, about 150 ms on a 60 ms path. Small once L2 ships.
- Evidence: MAI documents WAV, MP3, FLAC only; the general fast-transcription page lists OPUS/OGG but does not say it applies to MAI (read 2026-10-16). OpenRouter lists `ogg` but not `opus`. xAI accepts Opus.
- Cost: M (encoder and container), plus an accuracy check: 252 clips, about $0.17.
- Risk: medium-high: lossy audio may cost identifier accuracy; MAI may reject it.

### Checked, no change

- HTTP/3: openrouter.ai and api.x.ai send no `alt-svc` and their DNS HTTPS records give `h2` only (checked 2026-10-16). URLSession uses h3 only when the server offers it; `assumesHTTP3Capable` would race QUIC to a server that does not speak it.
- Provider by clip length: MAI is faster than Grok in every length bucket of the bench (contended p50: 637-1,207 ms vs 787-2,404 ms) and more accurate in every bucket on the hand-corrected set. No routing by length.
- Paste path: event-driven, no fixed sleep, key code cached, first CGEvent built at launch (`App/Paste.swift:91`). Nothing left to take out.
- Keychain read: done during the warm-up; `send` reads the cached key.
- Grok `format`: contended p50 +600 ms in the bench for +3.6 points of term recall over keyterms alone. Keep it off by default.

## 3. Accuracy items

### Q1. More hand-corrected references (prerequisite)

- Change: none in code. The owner corrects about 100-150 more clips on the review page (`bench/review/`), weighted to 10-20 s cmux clips and short (<10 s) clips, where WER is highest (MAI + phraseList 7.1% under 10 s vs 1.5-4.3% above).
- Gain: decisions. Today's CI (1.6-5.8% for the best variant on 62 clips) is wider than the gap between any two good providers.
- Evidence: bench report, "hand-corrected reference" section (2026-10-16 regeneration). The 234 other clips use Wispr's pasted text as the reference, which favors Wispr's formatter.
- Cost: owner time, about 1 minute per clip. No API cost.
- Measure: `bun run bench --only report`.
- Risk: none. Later, kotoba's own dictations with their audio (kept 7 days by default) and their edits (readback, "Fix Last Dictation…") can become a second set.

### Q2. Rank and cap the dictionary terms per request

- Change: `PersonalDictionary.keyterms` picks terms by rank, not by stored position: rule spellings and recently learned or recently heard terms first, then the rest, to the route cap. Show the owner which terms do not fit. This is `beyond-wispr.md` idea 5.
- Gain: keeps today's measured gain (term recall 61.5% -> 84.6% on hand-corrected clips with about 36 terms) as the dictionary grows. Without it, terms after position 100 never reach the model, and new terms are appended at the end (`PersonalDictionary.swift:159`).
- Evidence: phrase lists help when short and relevant and hurt when long (`beyond-wispr.md` 3: degradation past about 100 phrases in biasing studies; Azure's general cap is 2,000 phrases, "a longer phrase list will impact quality and latency", read 2026-10-16). MAI's own cap is still unpublished.
- Cost: S. A pure function in KotobaCore with table tests; the rank needs a "last used" signal (the history already has transcripts; the dictionary rows need a timestamp: a schema change, so it follows the migrations rule in `AGENTS.md`).
- Measure: bench size sweep on MAI + phraseList: the current list, 100 terms (current + 64 plausible identifiers the owner never says), 300 terms. Score term recall and false insertions (a list term in the output that is not in the reference). 3 variants x 99.2 min = about $0.50, about 5 minutes; about 2 h harness work.
- Risk: low. A rank can drop a needed term; the sweep shows how large the cap may be for MAI.

### Q3. Context terms from the active coding session

- Change: `beyond-wispr.md` idea 1, built as written there: at key-down, read the newest Claude Code or Codex session file and the repo (name, branch, file names), pick identifier-shaped tokens, merge them ahead of the dictionary terms (Q2's rank), never wait at the stop. Off by default (spec story 34).
- Gain (estimate): on the hand-corrected set, 8 of 52 technical terms are still missed with the dictionary. Context biasing studies report up to 88% relative error reduction on biased words (`beyond-wispr.md` 3).
- Cost: M.
- Measure: rebuild per-clip term lists from the session that was active at each clip's time (private data stays in the runbooks folder); 252 clips, about $0.17, plus about half a day of harness work.
- Risk: privacy (terms leave the Mac), and a wrong repo when two agents run at once.

### Q4. New STT candidates on OpenRouter

- Facts (read 2026-10-16): `elevenlabs/scribe-v2` added 2026-10-07 at $0.11/h on OpenRouter (half the direct price), AA-WER 2.2%, `keyterms` up to 1,000 (under 50 characters, at most 5 words; above 100 keyterms ElevenLabs bills at least 20 s per request). `assemblyai/universal-3-6-pro` added 2026-10-14 at $0.30/h, free-text `prompt` plus `keyterms_prompt`. `openai/gpt-transcribe` at $0.27/h, `prompt` plus `keywords`. Whether OpenRouter passes these options through (`provider.options.<tag>`) is unverified; the bench's "same text as base" column detects a dropped option.
- Gain: unknown. MAI + phraseList is already at 3.3%. Free-text context is the only documented way to show identifier style (`stt-vendors.md` 2).
- Cost: about $1.25 for the three on 252 clips (Scribe $0.18, AssemblyAI $0.50, OpenAI $0.45) plus latency passes on 40 clips (about $0.10), about 15 minutes; about 2 h harness work. Do it after Q1, or the result cannot rank them.
- Risk: latency from India is unknown for all three (none documents an India region for self-serve API keys).

### Q5. Hinglish without Sarvam

- Change: keep MAI with `language: "en"` (fewest Devanagari words, `languages.md`). Test two cheap levers on the synthetic set: (a) a phrase list of common Hinglish words in Latin script ("hai", "nahi", "kya", "karna", "abhi") to bias MAI's script, and (b) the local Devanagari-to-Latin step that `languages.md` proposes, run only when the transcript holds Devanagari.
- Gain (estimate): (a) unknown; "terms are hints, not forced output". (b) turns the 42-45% Devanagari letters into readable Latin; it cannot bring back the about 8% English words that MAI wrote in Devanagari.
- Evidence: synthetic run, romanized WER 3.8% for MAI `en` (`languages.md`).
- Cost: (a) 120 clips x 2 variants, 18.7 min each, about $0.06, about 3 minutes. (b) S; measure ICU `StringTransform` time on the hot path, skip it when no Devanagari is present (one scan).
- Risk: (a) uses phrase-list slots that Q2 also needs. Sarvam (`saaras:v4`, `mode=translit`, about Rs 30/h, REST under 30 s, read 2026-10-16) stays the reference when the owner wants it.

### Q6. Cleanup LLM

- Fact: on the hand-corrected clips, every cleanup doubled WER: raw 5.3% vs Gemini 3.5 Flash-Lite 10.5%, Qwen 3.8 27B on Cerebras 10.7%, Claude Haiku 5.5 19.9% (34 clips). Term recall rose a little (81.5% raw vs 85.2-88.9%).
- Reading: the references are close to what was said; a cleanup removes fillers and rewrites, so WER cannot tell a good cleanup from a bad one. The metric, not only the model, is the problem.
- Change: keep cleanup off the default path (as built). Before prompt work, build a small "what I meant to type" set (the 18 Wispr-edited clips plus owner edits from kotoba's own history) and score term recall, "obeyed the transcript" failures and owner preference. Keep Gemini Flash-Lite as default: Qwen on Cerebras was fastest on the edited set (p50 679 ms) but had 9 failed attempts in 100 and p90 4.96 s under contention.
- Cost: S-M. Risk: low.

### Q7. Audio preprocessing

- Keep 16 kHz mono FLAC from the first buffer (`CaptureWriter.swift:77`). It is what MAI expects; it is lossless.
- Do not add Apple voice processing or AGC: it changes the signal, adds latency and can pull Bluetooth into call mode (`docs/spec.md` "Microphone").
- Silence trim at start and end: the cue plays after capture starts, so each clip has some lead silence. Trimming 0.5-1 s saves about 5% of bytes and cost. Gain is small; the risk is a cut first word, which story 3 forbids. Not now.

## 4. Idle memory and launch

### M1. Run a Release build every day

- Change: `make build` uses `-configuration Debug` (`Makefile:20`), and the owner runs that bundle. Add a Release build for daily use (same Developer ID, so TCC grants stay) and keep Debug for development. `docs/progress.md` already lists this follow-up.
- Gain: unknown, measured release idle is 15.4-15.9 MB (`memory-spike.md`, Sparkle). Debug adds `kotoba.debug.dylib` and unoptimized code; the hot path CPU is small, so expect a memory gain more than a latency gain.
- Cost: S. Measure: `make memory` on both builds, 30 s idle, 3 rounds each, no window opened.
- Risk: low.

### M2. Footprint after use

- Not measured: footprint after many dictations and hours of idle (`memory-spike.md` question 2). Measure after 50 dictations and after 1 h idle with `make memory`. URLSession pools, SQLite caches and the readback learner can grow.
- Cost: owner time only.

### M3. SwiftUI windows

- Settings keeps +19-21 MB and History +24 MB after close (`memory-spike.md`). The spec accepts it. AppKit panes would remove most of it at a large cost (L). Not now.

### Launch

- The router builds three provider connections and the cleaner one at launch (`App/AppDelegate.swift:22`, `:91`): four URLSessions, cost not measured. `perf-pass-codex.md` kept them; no new evidence.
- No measure exists for launch to hotkey ready. A signpost at `startHotkeys` would give it. Low value: launch happens at login.

## 5. Ranked list

Impact, confidence and effort each on a 1-3 scale; score = impact x confidence / effort.

| Rank | Item | Area | Impact | Confidence | Effort | Score | API cost to decide |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | L1 split network time, run the gate | latency | 3 | 3 | 1 | 9.0 | $0 |
| 2 | Q2 rank and cap terms | accuracy | 2 | 3 | 1 | 6.0 | about $0.50 |
| 3 | Q1 more hand-corrected references | accuracy | 3 | 3 | 2 | 4.5 | $0 |
| 4 | M1 Release build daily | memory | 2 | 2 | 1 | 4.0 | $0 |
| 5 | Q3 context terms from the session | accuracy | 3 | 2 | 2 | 3.0 | about $0.17 |
| 6 | L2 upload while recording | latency | 3 | 2 | 3 | 2.0 | about $0.003 (spike) |
| 7 | L3 MAI direct `centralindia` | latency | 3 | 1 | 2 | 1.5 | about $0.21 |
| 8 | Q4 Scribe v2, U3.6 Pro, gpt-transcribe | accuracy | 2 | 1 | 1 | 2.0 | about $1.35 |
| 9 | Q5 Hinglish phrase list, transliteration | accuracy | 2 | 1 | 1 | 2.0 | about $0.06 |
| 10 | M2 footprint after use | memory | 1 | 2 | 1 | 2.0 | $0 |
| 11 | L4 hedge the tail | latency | 2 | 1 | 2 | 1.0 | about $0.035 |
| 12 | Q6 cleanup metric, then prompt | accuracy | 1 | 1 | 2 | 0.5 | about $0.05 |
| 13 | L5 Opus | latency | 1 | 1 | 2 | 0.5 | about $0.17 |
| 14 | M3 AppKit windows | memory | 2 | 3 | 3 | 2.0 | $0 |

Q4, Q5 and M3 score 2.0 but rank below L2 and L3: Q4 needs Q1 first, Q5 serves only Hinglish dictation, and M3 does not change the idle gate (measured with no window opened).

## 6. Proposed bench runs (each needs the owner's go)

The bench cost cap counts every raw file ($1.37 spent in kotoba-bench-v1); use `--cap USD` per run.

| Run | For | Clips | Cost | Duration | Harness work |
| --- | --- | --- | --- | --- | --- |
| Streaming spike: 5 requests of about 20 s, body streamed over the clip length, OpenRouter MAI | L2 | 5 | about $0.003 | under 5 min | a small bun script |
| Phrase-list size sweep: current, 100, 300 terms | Q2 | 252 | about $0.50 | about 5 min | about 2 h |
| Session context terms | Q3 | 252 | about $0.17 | about 3 min | about half a day |
| Azure direct vs OpenRouter, latency and accuracy | L3 | 40 + 252 | about $0.21 | about 10 min | about 2 h, plus the owner's Azure resource |
| Scribe v2, U3.6 Pro, gpt-transcribe | Q4 | 252 + 40 each | about $1.35 | about 15 min | about 2 h |
| Hinglish phrase list, synthetic set | Q5 | 120 x 2 | about $0.06 | about 3 min | about 1 h |
| MAI x2 in parallel | L4 | 40 | about $0.035 | about 3 min | about 1 h |

Prices: MAI $0.10/h (promotion to 2026-12-31), Scribe v2 $0.11/h, U3.6 Pro $0.30/h, gpt-transcribe $0.27/h on OpenRouter (read 2026-10-16). Audio: 252 clips = 99.2 min; 40 latency clips about 10 min.

## 7. The three changes I would do first

1. **L1: split the network time in the latency log, then run the gate.** No API cost, small code, and it answers the question every other latency item depends on: how much of the round trip is upload, and how much is upstream. Run `make latency RUN=1` on 30 or more real dictations, with and without the tunnel.
2. **Q2: rank and cap the dictionary terms.** It fixes a fault that grows with every learned word, in a pure KotobaCore function. Run the size sweep (about $0.50) to set MAI's cap from data.
3. **L2 spike: upload while recording.** It is the only change that takes the upload off the stop path on every route. Spike first (about $0.003) to clear the two stop conditions (slow body accepted by OpenRouter, FLAC stream with an open header accepted by MAI); build only if L1 shows the upload is more than about 100 ms of the gate.

In parallel, at no API cost: the owner corrects more references (Q1) and switches to a Release build (M1).

## Unresolved questions

1. Was the tunnel at 10:38 IST the owner's normal daily path, or a one-off? If normal, do the provider hosts go around it? The answer changes L2's gain by about 3x.
2. Which Azure region serves OpenRouter's MAI traffic? A paid request's headers or OpenRouter's `/generation` stats for an STT id may tell; not checked (needs the owner's key).
3. Does OpenRouter's Worker accept a request body that arrives over 10-60 s, or does it time out or reject it?
4. Does `AVAudioFile` write FLAC frames progressively, and does MAI accept a FLAC stream with `total_samples = 0`? A local check with `flac -t` on a copied partial file answers the first part for free.
5. After a 15-60 s recording, is the warmed connection still reused? `UploadMetrics` logs it, but at info level, which is not kept; L1 should log it where `make latency` can read it.
6. What is MAI-Transcribe-2's phrase-list cap, and where does a long list start to add false terms? Microsoft has not published it (read 2026-10-16).
7. Does OpenRouter pass ElevenLabs `keyterms`, AssemblyAI `prompt` and OpenAI `prompt`/`keywords` through `provider.options`?
8. Does `x-ai/grok-stt-1.0` on OpenRouter serve Grok Voice Transcribe 2.0? xAI's own default is `grok-voice-transcribe-2.0`; OpenRouter lists only the 1.0 slug (read 2026-10-16).
9. What is MAI-Transcribe-2's price after 2026-12-31? The Azure page still shows a placeholder.
10. How much does the Debug build cost in idle footprint compared with Release, on the same machine?
