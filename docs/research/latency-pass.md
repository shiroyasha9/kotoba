# Latency pass: where the stop-to-paste time goes, and the route primer

Date: 2026-10-17 (work at 01:35-02:45 IST). Agent `latency`, branch `latency`. Paid probe spend: see "Cost". Raw rows, the probe log and the saved log lines are in `<runbooks>/2026-10-17-kotoba-latency/` (not in git). No app database was read.

## Summary

- The local part of the stop path is small. The server wait after the upload is the whole problem: on OpenRouter MAI-Transcribe-2 it is about 0.8 s when a request came in the last minute, and about 2.4 s after a quiet minute. The owner dictates minutes apart, so most real dictations pay the slow case and miss the gate.
- The key-down warm-up (`HEAD` on `/models/<route>/endpoints`) opens TCP and TLS, but it does not warm this path. A `GET /key` or a rejected transcription `POST` does not warm it either. One small billed transcription (half a second of silence) does.
- Change: at the announcement of a dictation, the provider sends that primer (`TranscriptionProvider.prime`). Measured gain on the probe: about 1.6-2.0 s less server wait for a 15 s clip after a quiet period. Cost: one billed second, $0.000028, per announced dictation; it goes to the usage ledger.
- New tool: `make latency-log` gives the gate and the per-stage split from `log show`, with no database read. The per-dictation latency line is now a notice, so the log store keeps it.

## 1. Baseline from data that exists

### 1.1 The app's own log (release 0.3.x, 2026-10-16)

`log show` kept only the providers' upload lines (notice level). The per-dictation latency line was at info level, which the log store does not keep, so the stop-to-paste split of past dictations is only in the database (not read). The 16 upload lines (copy: `baseline-upload-lines.txt` in the runbooks folder; the 14:10-14:23 IST lines left the log store by 02:10 IST):

| Upload lines (all reused the warmed HTTP/2 connection, en0) | n | Server wait p50 | p90 | max |
| --- | --- | --- | --- | --- |
| All | 16 | 2,157 ms | 2,842 ms | 3,593 ms |
| After a quiet minute (no upload in the 60 s before) | 10 | 2,409 ms | 2,842 ms | 3,593 ms |
| Within a minute of the last upload | 6 | 790 ms | 2,269 ms | 2,269 ms |

The handover of the body to the network stack ("upload") took 1-89 ms for 0.8-593 KB. Server wait is from the last body byte to the first answer byte; it includes some upload still in the kernel buffer (`NetworkTiming.uploadSent`).

### 1.2 Earlier bench runs

The sequential bench passes send requests back to back, so they measure the warm case only: kotoba-bench-v1 `mai` p50 881 / p90 1,461 ms (2026-10-15 20h IST); termcap `app` list p50 752 / p90 832 ms (2026-10-16 10h IST). The stream spike of 2026-10-16 (10:51 IST) sent one request about every 20 s with a new process each time and saw 2.6-3.1 s. The gap between those numbers is the cold path, not the time of day.

## 2. Probes (2026-10-17, 01:40-02:55 IST)

Harness: `bench/latency/run.ts` (`bun run latency --exp <name>`). One request at a time (a hedge pair as two at once), the variant order rotated per clip, the app's request shape (base64 FLAC in JSON, `provider.zdr`, the bench dictionary as `phraseList`) unless named. Times are request start to response headers. This Mac's default route was a VPN tunnel (`utun9`, Cloudflare SIN, about 60 ms RTT); Wi-Fi alone reaches Cloudflare BOM.

| Probe | Result |
| --- | --- |
| Clip length, back to back (one clip cut to 3-30 s, 3 runs) | p50 1,077 ms (3 s), 796 (6 s), 907 (10 s), 966 (15 s), 1,025 (20 s), 1,178 (30 s). About 750 ms fixed, about 10 ms per audio second. |
| Request shape, back to back (10 clips of 10-20 s) | app shape p50 944 / p90 1,109 ms; no ZDR and no phrase list 998 / 1,181; multipart with raw FLAC (25% smaller body) 958 / 1,242. No shape wins. |
| Other models through OpenRouter (10 clips) | MAI 907 / 1,214 ms; Grok 963 / 1,144; Deepgram Nova-3 1,371 / 1,677; Whisper large v3 turbo 1,498 / 4,719; Parakeet 1,541 / 1,745; Scribe v2 1,702 / 1,864. MAI stays the fastest. |
| Hedge: the same request twice at once (20 clips) | One of a pair: p50 921-1,090 ms, max 3,380. Faster of two: p50 909 / p90 1,115 ms. The two spikes (3,380 and 2,840 ms) each had a fast twin. |
| Idle: 90 s quiet, a 3 s request, then after 3, 15 or 45 s a 15 s clip (2 runs) | The 3 s request after quiet: 2,455-2,599 ms (n 6). The 15 s clip after it: 1,551-1,657 ms (n 6), the same for every gap up to 45 s. |
| Primer: 90 s quiet, a primer, 10 s (a recording), then a 15 s clip | No primer: 3,407-4,021 ms (n 6). `GET /key`: 3,069-3,100 (n 3). `POST` with `{}` (400 from OpenRouter, free): 3,046-3,121 (n 3). 0.5 s of silence, app shape: 1,240-1,955 (n 3). 0.5 s of silence without the phrase list (what the app sends; the last run with the app's exact 110-byte FLAC): 1,904-2,003 (n 3). |
| Path: Wi-Fi (en0, BOM) against the VPN (SIN), curl, a new connection per request (10 clips) | Both bimodal, about 0.8-1.4 s or 2.0-3.5 s; Wi-Fi p50 2,084 ms, VPN p50 2,466 ms. Not decisive. |

### 2.1 Why a primed clip is still slower than a warm one (2026-10-17, 02:44-03:40 IST)

`--exp spacing`: after 90 s quiet, a primer, a gap, then the same 15 s clip three times back to back (A, B, C). B and C are the warm reference (about 1.05-1.2 s on this path, with the usual spikes to 2.8 s).

| Primer (then 10 s, unless named) | Primer body | Clip A after it |
| --- | --- | --- |
| None | - | 3,499 / 1,797 ms |
| The app's silence, 0.5 s; gaps 2, 10, 25 s | 110 B | 1,859-1,977 ms (n 8, every gap) |
| Two silent primers, one after the other | 110 B each | 1,921 ms |
| Speech, first 3 s of the clip | about 70 KB | 2,169 / 1,594 ms |
| White noise, 1 s, 16-bit 48 kHz stereo FLAC | 127-153 KB | 1,646 / 1,534 / 1,326 ms |
| White noise, 1 s, 32-bit 48 kHz stereo WAV | 384 KB | 1,066 / 2,733 ms |
| White noise, 15 s | 376 KB | 2,871 / 1,165 / 1,116 ms |
| The clip itself, 15 s | about 360 KB | 1,152-1,247 ms (n 4) |

- The primer was not in flight: every primer had answered before its gap started, and the gap (2-25 s) does not change A.
- A second silent primer does not help. A large body does, whatever its length or content: with a primer of 360-384 KB, A is at the warm level (one spike in five, as for warm requests). So part of the cold path warms with the bytes sent (an upstream connection's congestion window is the likely cause; not verified), and survives at least 10 s of quiet.
- On Wi-Fi without the VPN (curl on en0, Cloudflare BOM, a new connection per set, 2 runs each): after the silent primer clip A took 1,081 / 1,160 ms; after the 384 KB primer, 803 / 882 ms. So the extra gain of a large primer is about 0.3 s on Wi-Fi and about 0.75 s on the VPN path.
- Cost of a large primer: still one billed second ($0.000028; checked: `usage.seconds` 1 for the app's exact WAV), but about 0.5 MB up per primer (base64). Built for cold starts only (section 3, item 1).

Reading: the slow part is on the provider side after the edge, and it is warm for at least 45 s after a billed transcription. A request that OpenRouter answers itself (auth, a 400) warms about 0.4 s of it; the rest needs a request that goes to the upstream. Which part is cold (OpenRouter's upstream connection, Azure, or both) cannot be seen from here: the response has no timing headers, and the generation stats endpoint is not documented for speech.

## 3. Changes

1. **Route primer** (`TranscriptionProvider.prime`, KotobaCore; `OpenRouterProvider.prime`, KotobaProviders). At the announcement (after the tap threshold, so a dropped shortcut press sends nothing), the pipeline sends the route's primer as tracked work and never waits for it. The OpenRouter primer is 110 bytes of FLAC silence with the route's model, language and data policy (ZDR), no dictionary terms, through the same body writer and long-lived connection as a dictation. Its cost goes to the usage ledger with the dictation, with no audio and no words, so minutes and words per minute stay what the owner dictated. A failed primer is ignored. The direct routes (xAI, Azure) have no primer: their cold start is not measured. Tests: `PipelinePrimerTests` (4), `OpenRouterPrimerTests` (4).
   - Gain: about 1.5-2.0 s less server wait after a quiet period (section 2: 3.5 s to 1.9-2.0 s with the app's primer on the probe; 2.4 s to 0.8 s p50 in the app's own split, section 1.1). Not yet measured in the app; see the owner trial.
   - Cost: one request per announced dictation, billed as one second ($0.10/h, so $0.000028; $0.028 per 1,000 dictations). About 300 bytes up. No work at idle, no work on the stop path.
   - Long recordings (lead decision, 2026-10-17): while the recording is live, the pipeline sends one more primer every `Settings.primerInterval` (40 s: warm was measured 45 s after a primer, less a 5 s margin), as a timer on the pipeline clock. Each timer counts from the last primer sent, so after an Undo the next one goes at once when the last is older than 40 s. The stop and Esc cancel it, and a primer is never sent while one is in flight (the one that comes back arms the next). A route with no primer (xAI and Azure direct, `TranscriptionProvider.hasPrimer` false) sends none and arms no timer (lead, 2026-10-17). At most 90 primers per hour of continuous recording (the first one plus 89 more), $0.0025 per hour. Tests: 6 more in `PipelinePrimerTests` (10 in all).
   - Large primer on a cold route (lead decision, 2026-10-17; a measured stopgap): at the announcement, when the route answered nothing (no transcription, no primer) within `Settings.primerInterval` (40 s), the primer is one second of white noise as a 48 kHz stereo 32-bit WAV, 384,044 bytes (512,179 bytes of JSON body). Otherwise, and for every re-prime, it is the silent one. `RouteWarmth` (KotobaCore) wraps the provider port and keeps when the route last answered, for every caller (dictation, retry, Transcribe Again). MAI accepted the app's exact bytes and billed one second; clip A after it took 1,231 / 1,106 ms (VPN path, section 2.1). The body is built once per route and language and kept (`PrimerBodies`): one buffer of its final size with the WAV made and base64-encoded in place, about 1.2 ms, and about 0.55 MiB of footprint, the same as a plain 512 KB `Data` (a standalone probe; building the WAV and its base64 whole first held about 1.5 MiB). A primer then copies and encodes nothing.
     - Data: in the owner's Wispr Flow history (938 dictations on 92 days, `SELECT timestamp, duration FROM History WHERE timestamp IS NOT NULL ORDER BY timestamp`, read-only on the backup copy), 69% of dictations came with no answer in the 40 s before. So about 69 large primers per 100 dictations: about 35 MB up per 100 dictations (about 35 MB a day at 100 a day). Re-primes stay silent, so a long recording adds no large ones.
     - Root fix, on the list: a streaming speech endpoint (section 4), which needs no primer.
     - Limits: the warm state is not kept per route, so the first dictation after a route switch (or after "Transcribe Again With" another model) can get the silent primer on a cold route; left as is, route switches are rare (lead, 2026-10-17). With a key that fails, every cold announcement sends a 0.5 MB primer that fails. The 40 s window is the re-prime interval too (warm measured 45 s).
   - Limit: a recording shorter than the primer's own round trip (about 1-2 s when cold) gets less of the gain; the two requests then run side by side on the HTTP/2 connection.
2. **Persistent latency line and `make latency-log`**. The per-dictation line on `Log.latency` is now a notice with `model=` and `audioMs=`, so the log store keeps it. `scripts/latency-log.sh` reads `log show` (or a saved copy, `FROM=`) and prints the gate and the stop path split (stop to uploadStart, body build and upload, server, answer body, paste), split by the quiet time before each dictation; the primer's upload lines are summed apart. No database read. Cost: one log line per dictation at notice level.
3. **`bun run latency`** (`bench/latency/run.ts`): the probes above, so later agents measure the same way (`--exp duration|shape|hedge|models|idle|primer|spacing|report`). Raw rows go to `<out>/results/latency-raw.jsonl` as they come; the report reads only that file.

## 4. Checked, no change

- Silence trim before upload (lead candidate, 2026-10-17; Superwhisper, Handy): measured on the 252 bench clips (99 min) with `ffmpeg silencedetect`, at least 0.3 s of silence at each end, 0.3 s kept at each end so soft onsets and last words stay. At -45 dB: 0.7% of the audio is trimmable (p50 0 s, p90 0.58 s per clip; 98 clips). At -35 dB (looser, more risk): 2.1% (p50 0.29 s, p90 1.38 s; 191 clips). At about 10 ms per audio second (section 2), that is 3-14 ms per dictation, and 0.7-2.1% of the billed seconds (at most $0.002 per hour of audio). The bench clips are Wispr Flow recordings; kotoba's own files start at key-down and can hold some more lead silence, but not enough to change this. Skipped: the gain is small and a cut can clip speech. Script and rows: `trim/` in the runbooks folder.

- Request shape (multipart raw FLAC, no ZDR, no phrase list): no gain back to back (section 2).
- Upload while recording: not built or measured end to end tonight. The stream spike (2026-10-16, `<runbooks>/2026-10-16-kotoba-stream-spike/`) streamed the JSON body to OpenRouter during a 20 s recording: a FLAC stream fails (502: the header's `total_samples` is 0 until the file closes), a WAV with an open size (`0xFFFFFFFF`) is accepted. OpenRouter must have the whole JSON before it calls the provider, so streaming removes only our own upload after the stop: 22-89 ms for 300-600 KB on Wi-Fi in the app's log, about 200-300 ms on the 60 ms VPN path, plus the 2 ms body build. It does not touch the server time, which is most of the wait. It would take: `uploadTask(withStreamedRequest:)` with a bound stream pair fed by the capture writer (WAV, about 1.4x the bytes of FLAC as base64), a cancel for Esc and a resume for Undo, a fallback to the file upload, a limit near OpenRouter's 60 s upstream timeout, and provider-seam tests: about 2 days, with an open request through every recording.
- A streaming speech endpoint (words while speaking, a final answer about 0.2-0.5 s after the stop) would remove most of the server wait, but OpenRouter's speech API is batch only; MAI streaming is on Vercel AI Gateway as a WebSocket at about $0.54/h (5.4x) through Paris (+200 ms, `mai-routing.md`), or on Azure direct with the owner's own resource. A new route, a new price and a new accuracy bench; not tested.
- Other models: all slower than MAI through OpenRouter on this path.
- Hedging (two requests at once): it cut both spikes in 20 pairs, at twice the speech cost and upload. The primer removes the larger, systematic cold cost first; hedge only if `make latency-log` still shows a tail after it (owner decision: it doubles the speech bill).
- Local stop path: stop to `uploadStart` (capture end, FLAC close) and response to paste are measured by the new log line from now on; no old data exists outside the database.

## 5. Cost

$0.1146 in `latency-raw.jsonl` (`usage.cost`) plus about $0.012 for the curl A/Bs (path and Wi-Fi primer; cost not logged, estimated from audio seconds at $0.10/h): about $0.127 of the $2.00 cap. Wall time about 2.5 hours, most of it the 90 s quiet periods.

## 6. Owner trial (kotoba Dev)

1. `make build`, then launch kotoba Dev from `build/DerivedData`.
2. Five dictations of 10-20 s, each after 2 minutes or more of quiet; then five of 10-20 s, 10-20 s apart.
3. `make latency-log DEV=1 LAST=1h`: stop to Cmd-V sent "after a quiet minute" should be near "within a minute", both under 1.5 s at p90. The "primer lines" set shows the primers' own wait.
4. The large primer's upload copy: in Instruments (Allocations) on a Release build, start a dictation after 2 minutes of quiet and check that the 512 KB primer body is not copied on each send (one allocation at the first cold primer, none after).

## Unresolved questions

1. Which part is cold: OpenRouter's upstream connection, Azure, or both? A direct Azure route (owner's own resource) would show whether Azure itself has the cold start.
2. How long does the warm state last past 45 s? The 40 s re-prime interval is safe by the probe; a longer measured window (`--exp idle` with longer gaps) would allow fewer primers.
3. Do the direct routes (xAI, Azure) have the same cold start? Not measured; no primer is sent on them.
4. Should the pipeline skip the primer when the route answered in the last 30-45 s? It saves $0.000028 per such dictation and adds state; not done.
