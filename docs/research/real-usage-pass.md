# Real usage pass: 10 days of the owner's dictations

Date: 2026-10-25 (work at 15:36-16:40 IST). Inputs: a read-only export of the release app's history and dictionary (owner go, 2026-10-25), the kept FLACs, and paid runs on OpenRouter. Raw rows, scripts and the export are in `<runbooks>/2026-10-25-kotoba-real-usage/` (personal text; not in git). This file holds numbers only. Spend: $1.44 of a $2.00 cap.

## Summary

- 258 dictations from 2026-10-16 to 2026-10-25, 99.5 min of audio, 17,591 words. 230 went to cmux (a terminal). Median length 11 s, p90 56 s.
- The stop path is the speech server. Stop to ⌘V sent: p50 1,341 ms, p90 3,611 ms (221 plain dictations, all lengths). The server wait is 1,244 / 3,298 ms of it; capture end, upload and paste together are about 30 ms at p50.
- After a quiet minute the server is slower: p50 1,634 ms against 1,015 ms within a minute. 119 of 221 dictations came after a quiet minute.
- The tail is mostly one bad evening: 2026-10-22 18:30-19:20 IST had 8 of the 12 slowest answers (5.3-13.5 s).
- Segment upload works on real speech. For 40 s and longer, stop to ⌘V sent fell from p50 3,184 ms (n 8, before 0.4.6) to 1,932 ms (n 27). A 393 s dictation pasted in 986 ms. The -40 dBFS pause rule finds no cut in 14 of 67 recordings of 20 s or more.
- MAI with the phrase list is still the most accurate speech model on this audio, and the slowest. On 60 real clips: WER 2.3%, all 12 dictionary-term uses right, p50 1,424 ms. The 6 others had 3.4-8.7% WER and 1-6 of 12 terms, at p50 602-1,154 ms.
- Raw MAI text needs cleanup: "uh" 250 times and "you know" 303 times in 231 transcripts; 55 transcripts have a lowercase sentence start after `.`, `?` or `!` (92 times).
- Cleanup can be fast. DeepSeek V4.1 Flash on Together, with the shipped Code prompt v3: p50 559 ms, p90 1,152 ms on 60 real transcripts, against 1,048 / 2,174 ms for Gemini 3.5 Flash-Lite (the old default). A judge found no lost content in any of the 60, and a change of meaning in 2. It is now the default cleanup model (this change).

## 1. Where the time goes (app history, no new requests)

From `latency_marks`, pasted plain dictations (221), release app on MAI through OpenRouter:

| Length | n | Stop to ⌘V p50 | p90 | Server p50 | Upload p50 |
| --- | --- | --- | --- | --- | --- |
| < 5 s | 38 | 945 ms | 2,386 ms | 879 ms | 6 ms |
| 5-10 s | 57 | 1,126 ms | 3,940 ms | 1,050 ms | 12 ms |
| 10-20 s | 54 | 1,297 ms | 3,061 ms | 1,244 ms | 23 ms |
| 20-40 s | 37 | 1,658 ms | 3,367 ms | 1,484 ms | 41 ms |
| 40 s + | 35 | 2,633 ms | 4,058 ms | 2,366 ms | 67 ms |

Stop to upload start (capture end) is 12 ms p50, the answer to ⌘V sent 5 ms p50. The latency gate (10-20 s: p50 ≤ 1,000 ms, p90 ≤ 1,500 ms) is missed by the server alone.

Server wait by time since the last dictation ended (dictations under 20 s): 0-15 s 958 ms (n 36), 15-60 s 985 ms (n 32), 1-5 min 1,411 ms (n 29), 5-30 min 1,546 ms (n 19), over 30 min 1,668 ms (n 14).

Cold and very short is the worst cell: under 3 s after a quiet minute, server p50 1,973 ms (n 6), against 1,056 ms for 6-10 s (n 14). A cause that fits: the silent primer goes at the announcement, so in a short dictation it is still on its way at the stop, and on a cold route a second request at the same time is the slow one (`latency-pass-2.md` section 2.5). n 6 is too small to act on; see the questions.

The cleanup chord was used 8 times: stop to ⌘V p50 2,546 ms, of which the cleanup request (Gemini) was 1,532 ms.

## 2. Speech models on real clips (paid)

60 kept recordings of 2.5-25 s (12 per 5 s band), Ogg Opus 24 kbps as the app sends, one request at a time, model order rotated per clip, zero data retention, the owner's 34 terms in each model's own field. 2026-10-25 15:47-15:55 IST, $0.29. Reference: Gemini 3.1 Pro with the audio, the vocabulary and the 7 machine texts shuffled as hints (15:56-16:03 IST, $0.47). WER is normalized (case, punctuation, um/uh dropped).

| Model, option | WER (95% CI) | Terms | p50 | p90 | Price per hour |
| --- | --- | --- | --- | --- | --- |
| MAI-Transcribe-2, phraseList (the app) | 2.3% (1.4-3.6) | 12/12 | 1,424 ms | 3,123 ms | $0.10 |
| AssemblyAI Universal-3.6 Pro, keyterms_prompt | 3.4% (2.0-5.5) | 6/12 | 918 ms | 1,514 ms | $0.30 |
| ElevenLabs Scribe v2, keyterms | 4.2% (2.5-6.1) | 1/12 | 1,154 ms | 1,597 ms | $0.22 |
| Voxtral Mini Transcribe 3, context_bias | 4.2% (2.7-6.4) | 2/12 | 783 ms | 1,110 ms | $0.20 |
| Deepgram Nova-3, smart_format | 6.9% (5.3-8.8) | 1/12 | 602 ms | 1,052 ms | $0.26 |
| Whisper large v3 turbo on Groq, prompt | 8.7% (6.8-11.0) | 3/12 | 859 ms | 1,569 ms | $0.02 |

Paired against MAI, every other model is worse; the closest is AssemblyAI at +1.1 pp (95% CI +0.2 to +2.2). Deepgram with `keyterm` gave the same text as without it on all 60 clips: OpenRouter forwards only an allowlist of Deepgram options (`punctuate`, `diarize`, `smart_format`, `detect_language`; OpenRouter STT guide, read 2026-10-25), so the term list does not reach Deepgram.

Limit: the reference saw MAI's text among its hints, which can favour MAI. On the 17 clips where MAI and the reference differ by 2 words or more, the differences read as MAI errors (a product name heard as a common word, "fix" as "phase"), not as reference errors.

Decision: stay on MAI. The 0.5-0.8 s it costs buys about half the word errors and every dictionary term.

## 3. Cleanup models on real transcripts (paid)

60 real MAI transcripts from cmux (15 each of under 20, 20-49, 50-119 and 120+ words), Code prompt v3 with the owner's vocabulary, as the app sends it (not streamed, zero data retention, pinned hosts). One request at a time, model order rotated per input. 2026-10-25 16:05-16:20 IST, $0.23. Judge: Claude Sonnet 5.5, one call per input, the 6 outputs unnamed and shuffled (16:21-16:25 IST, $0.46).

| Model, host | p50 | p90 | Judge: no loss and no change | Lost | Changed | Pasteable | $ per 1,000 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DeepSeek V4.1 Flash, Together | 559 ms | 1,152 ms | 58/60 | 0 | 2 | 37/60 | 0.19 |
| Gemini 3.5 Flash-Lite, Google (old default) | 1,048 ms | 2,174 ms | 53/60 | 3 | 6 | 31/60 | 0.51 |
| Qwen 3.8 27B, Cerebras | 482 ms | 670 ms | 46/60 | 9 | 17 | 39/60 | 0.97 |
| gpt-oss-120b, Cerebras | 531 ms | 926 ms | 43/60 | 16 | 23 | 36/60 | 0.50 |
| Mercury 3, Inception | 553 ms | 1,076 ms | 43/60 | 11 | 12 | 29/60 | 0.07 |
| Llama 3.3 70B, Groq | 414 ms | 895 ms | 24/57 | 35 | 40 | 23/57 | 0.56 |

Lost and changed are counts of meaning units over all 60 inputs. "Pasteable" also needs every filler gone; most misses there are "I mean" or "you know" kept, which the judge counted as fillers.

Measured, not judged: Llama 3.1 8B on Groq (244 ms p50, but 9 of 60 rate-limited upstream), Mercury 2.5 (785 ms), gpt-oss-20b on Groq (658 ms), Gemini 3.1 Flash-Lite (1,257 ms, 2 failures), gpt-oss-120b on Groq (1,281 ms), Claude Haiku 5.5 (1,559 ms).

Time against length (least squares over the 60): DeepSeek about 534 ms + 1.5 ms per word; Gemini about 1,350 ms + 1.5 ms per word. The fixed part is most of it, so cleaning each segment during a long dictation would save little: about 0.2 s at 150 words.

With DeepSeek, a cleaned dictation should take about the speech time plus 0.56 s at p50 (1.9 s for today's 1,341 ms), against plus 1.5 s with Gemini (the 8 real cleanup dictations: 2,546 ms).

## 4. Changes in this pass

1. `CleanupModel.deepSeekFlash` (`KotobaProviders/Sources/KotobaProviders/OpenRouterCleaner.swift`) is the default cleanup model: reasoning `none`, temperature 0, Polish's host order (Together, PrimeIntellect, InferenceNet, no other host). An owner who picked a model in Settings keeps it. Price list: $0.30 / $1.20 per 1M tokens.
2. The dictionary file adds "kotoba", pinned, once per dictionary (`DictionaryStore.addAppTerms`, `user_version` 0 to 1). MAI wrote the app's name as "Codex" (a listed term) when it was not listed; "kotoba" occurs in none of the 231 transcripts.

## 5. Evening pass: MAI's clean style, swear words, Apple on device (2026-10-25, 20:10-20:30 IST)

Same 60 clips and references as section 2, MAI with the phrase list through OpenRouter, the two variants in turn per clip. $0.13 (raw rows in the runbooks folder).

| MAI variant | WER (95% CI) | Terms | p50 | "um"/"uh" | "you know" | Words |
| --- | --- | --- | --- | --- | --- | --- |
| verbatim (the app before this change) | 2.40% (1.5-3.6) | 12/12 | 1,747 ms | 22 | 33 | 2,470 |
| `transcribeStyle: "clean"` | 3.91% (2.8-5.2) | 12/12 | 1,781 ms | 0 | 22 | 2,412 |

- WER counts against a verbatim reference, so a dropped repetition ("let's, let's") or false start counts as an error. Of the 58 words clean drops, nearly all are fillers, repeated words and false starts. One change of meaning in 60 clips: a word both variants misheard became a different wrong word, and two words fewer. Punctuation and casing changes are small; a lowercase sentence start after `.` stays (141 and 140).
- Time: paired median +74 ms per clip, inside this hour's spread (p25 -1.2 s, p75 +1.6 s). No cost change.
- The option takes effect only inside `enhancedMode.modelOptions` (Microsoft's request shape). At the top of `provider.options.azure` it changed 3 of 60 texts, which is the noise of a repeated request.
- Decision: both MAI routes send `clean` (`MAIEnhancedMode`, `KotobaProviders/Sources/KotobaProviders/ProviderHTTP.swift`). The cleanup chord still runs the LLM on top.

Swear words: 4 recordings with one each, 7 variants. `profanityFilterMode: "Masked"` through OpenRouter masked none (with and without `clean`), so OpenRouter or MAI ignores it there and a "mask" setting cannot work on the default route. Azure direct masks by default, by Microsoft's docs, so it now sends `None`, to paste what the speaker said on both routes.

Apple DictationTranscriber (macOS 27.0.1, M3 Pro, `longDictation` preset, the 34 terms as `contextualStrings`, free):

| Locale | WER (95% CI) | Terms | Final text after the last buffer, p50 |
| --- | --- | --- | --- |
| en-IN, with terms | 22.4% (18.6-26.8) | 0/12 | 601 ms (fed at once) |
| en-IN, no terms | 22.4% | 0/12 | 678 ms |
| en-US, with terms | 18.7% (15.3-22.5) | 0/12 | 683 ms |

- It writes 15% fewer words than the reference, and drops whole clauses (one 18 s clip: 27 of 64 words). Fed in real time (6 clips) it writes the same words; its final text then comes 83-829 ms after the last buffer.
- The terms change nothing on real audio (60 of 60 texts the same with and without them), against 7 of 7 on one synthetic en-US clip.
- Not usable for dictation here. The `shortDictation` preset returned no final text in this harness.

## Unresolved questions

- Short cold dictations: does the silent primer, still on its way at the stop, slow the real request? A latency mark for "primer in flight at the stop" would answer it from real use.
- 14 of 67 recordings of 20 s or more have no -40 dBFS pause; at -35 dBFS 8 have none. Is a lower threshold worth a WER check?
- The Code prompt lists "you know" as a filler, and "I mean" is not listed; the judge counted both. Should "I mean" go?
- Deepgram's term list does not reach it through OpenRouter. Is Deepgram (Hyderabad endpoint, streaming) worth a direct key?
