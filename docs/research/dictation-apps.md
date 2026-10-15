# Dictation apps for technical prompts: Aqua Voice, Wispr Flow, and others

Research date: 2026-10-15. Scope: architecture, accuracy and latency claims that matter when you dictate identifiers, camelCase, file paths and CLI flags to coding agents.

Rules for this document:

- Each claim has a source URL.
- "Unconfirmed" means that I could not find a primary source, or the primary source is now gone.
- All benchmark numbers are vendor self-reports unless the text says otherwise.
- No sign-up, no payment, no API key was used.

Raw downloads (untrusted data, for reference only):

- `scratchpad/raw/aqua/avalon-model-card.pdf`
- `scratchpad/raw/aqua-llms/llms.txt`
- `scratchpad/raw/wispr/` (Wispr API docs, llms.txt files, Canto page)
- `scratchpad/raw/others/` (Superwhisper docs, VoiceInk README)

---

## 1. Aqua Voice

### 1.1 Pipeline

- Aqua uses its own ASR model, Avalon, plus "language-model post-processing" for format and context. Source: https://aquavoice.com/llms.txt
- Avalon launched in August 2025. It replaced an "earlier Whisper-based pipeline". Source: https://aquavoice.com/llms.txt
- Deep Context is "a client-side engine that reads what's on screen". Source: https://aquavoice.com/llms.txt
- Inference runs in a data center. In April 2025 a founder wrote: "we can't run asr and an llm locally at the speed that is required". Source: https://news.ycombinator.com/item?id=43634005
- Two dictation modes. Source: https://aquavoice.com/llms.txt
  - Instant Mode (default): push-to-talk, release, then text. It runs on Aqua's own Avalon models.
  - Realtime Mode (Max plan, formerly "Streaming Mode", renamed July 2026): shows words live. It "streams audio to a third-party realtime speech provider". The provider is not named in public text (unconfirmed; the list is in the Vanta Trust Center).
- The LLM used for post-processing is not named in any public source I found. Unconfirmed.

### 1.2 Avalon model card (PDF)

Source for this section: https://app.aquavoice.com/research/avalon-model-card.pdf (authors Jack McIntire and Finnian Brown, Aqua Voice; no date on the PDF; it cites 2025 work).

What Avalon is:

- An ASR model "optimized for human-computer interaction".
- "Derived from Whisper". The card does not name the exact Whisper checkpoint. Whisper Large v3 is the likely base, but this is unconfirmed.
- Goals: better on coding and AI terms, "domain-aware normalization" (conservative normalization of unfamiliar terms), and better robustness on poor audio.
- Training data: subsets of public audio datasets, audio from the internet, data from opt-in Aqua users, and synthetic data "using a process similar to ContextASR-Bench".
- Training: two epochs on an NVIDIA H100 cluster. No parameter count. No data hours.

Public benchmark WER (%, lower is better), run with the Hugging Face OpenASR leaderboard code (Table 2):

| Dataset | Avalon | Canary 1B | ElevenLabs Scribe v1 | Voxtral Mini 3B | Whisper Large v3 | AssemblyAI Best |
|---|---|---|---|---|---|---|
| AMI | 11.58 | 13.90 | 14.43 | 16.30 | 15.99 | 15.64 |
| Earnings22 | 11.38 | 12.19 | 12.14 | 10.69 | 11.11 | 13.54 |
| GigaSpeech | 9.50 | 10.12 | 9.66 | 10.24 | 10.12 | 9.50 |
| LibriSpeech clean | 1.68 | 1.48 | 1.79 | 1.88 | 1.98 | 1.74 |
| LibriSpeech other | 3.28 | 2.93 | 3.31 | 4.10 | 4.58 | 3.11 |
| SPGISpeech | 2.10 | 2.06 | 3.30 | 2.37 | 2.95 | 1.81 |
| TED-LIUM | 3.02 | 3.56 | 3.17 | 3.68 | 3.56 | 3.43 |
| VoxPopuli | 7.33 | 5.79 | 7.20 | 7.14 | 8.56 | 7.47 |
| Average | 6.23 | 6.50 | 6.88 | 7.05 | 7.36 | 7.03 |

- The card has no OpenAI gpt-4o-transcribe and no Deepgram numbers.
- The blog reports a 6.24% average (not 6.23%), #6 overall and #1 proprietary on the OpenASR leaderboard, October 2025. Source: https://aquavoice.com/blog/avalon-openasr-leaderboard

AISpeak, Aqua's own coding and AI-term benchmark:

- Clips of people prompting an AI. Built from 2025 data. Three sets with harder terms as the number goes up.
  - AISpeak-10: 1,278 samples, 4 h
  - AISpeak-50: 3,793 samples, 13 h
  - AISpeak-500: 9,198 samples, 31 h
- Metric: accuracy on "highlighted" key terms per clip (Table 4). The card says Avalon also has lower WER on the test split, but it gives no WER number for AISpeak.

| Set | Avalon | Canary 1B | Canary 1B Flash | Voxtral Mini 3B | ElevenLabs Scribe v1 | Whisper Large v3 | IBM Granite 8B |
|---|---|---|---|---|---|---|---|
| AISpeak-10 | 97.4 | 51.5 | 56.9 | 59.5 | 78.8 | 65.1 | 54.7 |
| AISpeak-50 | 97.5 | 71.8 | 74.5 | 79.4 | 86.7 | 82.4 | 72.8 |
| AISpeak-500 | 95.8 | 74.1 | 76.1 | 82.9 | 87.5 | 84.9 | 75.0 |

- NVIDIA Parakeet models scored 50-75% on AISpeak. The authors "speculatively" think Parakeet is overfit to public datasets.
- Examples from the card: "zshrc" (Whisper: "C, short C"), "PyTorch" (Whisper: "high torch"), "Vercel" (Whisper: "Versacell"), "gpt-4o, gpt-4.1, o3" (Whisper adds a false "GPT-" before o3), "uv" kept lowercase (Whisper: "UV").
- The AISpeak dataset is not public, as far as I can find. Unconfirmed.
- The card gives no latency numbers.

### 1.3 Avalon 1.5 (2026)

- Released April 2026 with the iOS app. Source: https://aquavoice.com/blog/aqua-voice-for-ios
- OpenASR average WER 5.55, down from 6.24 for Avalon 1. Source: https://aquavoice.com/blog/aqua-voice-for-ios
- Wins 76% of blind head-to-head tests against ElevenLabs Scribe v2. Source: https://aquavoice.com/blog/aqua-voice-for-ios
- Speed claim conflicts between sources:
  - The iOS post says "more than twice as fast" as Scribe v2. Source: https://aquavoice.com/blog/aqua-voice-for-ios
  - llms.txt says "more than 2x faster than Avalon 1". Source: https://aquavoice.com/llms.txt
- First natively multilingual Avalon. Better on ReazonSpeech and an "AISpeak Japanese" set. No numbers in text. Source: https://aquavoice.com/blog/aqua-voice-for-ios
- Better AI vocabulary "without dictionary setup". No number. Source: https://aquavoice.com/blog/aqua-voice-for-ios
- llms.txt says Avalon scores 97.3% "on the full AISpeak set". The set definition is not given. Source: https://aquavoice.com/llms.txt
- No Avalon 2 or newer model card found as of 2026-10-15.

### 1.4 Latency claims (Aqua)

- Startup under 50 ms. Text in "about a second (as fast as ~450ms)". Sources: https://aquavoice.com/llms.txt, https://news.ycombinator.com/item?id=43634005
- Instant Mode: text appears ~450 ms after you stop speaking. Source: https://aquavoice.com/llms.txt
- llms.txt also says "Startup <200ms" for Instant Mode in another section. This conflicts with "<50ms". Source: https://aquavoice.com/llms.txt
- In April 2025 a founder claimed Wispr Flow was "closer to 1000 [ms] in our tests". Source: https://news.ycombinator.com/item?id=43634005
- No p50/p99 split and no per-stage budget is published. Unconfirmed.

### 1.5 Technical vocabulary and context features

- Deep Context: reads the active screen to resolve variable names, libraries, handles and CLI flags. Off by default. "processed securely and never stored". Sources: https://aquavoice.com/llms.txt, https://aquavoice.com/blog/voice-coding-cursor-claude-code
- Example from Aqua: "canonical title on the context response model" becomes `` `canonical_title` on the `ContextResponse` model ``. Source: https://aquavoice.com/llms.txt
- Whether Deep Context uses screenshots, OCR or the accessibility tree is not stated. Unconfirmed.
- Spoken casing: "camelCase user ID" becomes `userId`; "snake_case max retries" becomes `max_retries`. Source: https://aquavoice.com/blog/voice-coding-cursor-claude-code
- Paths and flags: "Avalon's training data includes them". No specific rules for `~`, `--flag` or `-f` are documented. Source: https://aquavoice.com/blog/voice-coding-cursor-claude-code
- Custom Dictionary: up to 800 entries on Pro. Keeps casing and is context-aware ("factorio" still becomes "Factorio" at sentence start). Sources: https://aquavoice.com/blog/voice-coding-cursor-claude-code, https://aquavoice.com/llms.txt
- Custom Instructions: natural-language style rules, for example "keep identifiers in camelCase". Source: https://aquavoice.com/llms.txt
- Replacements: spoken phrase expands to stored text. Source: https://aquavoice.com/llms.txt
- File Tagging in Cursor and Windsurf: "main ts" becomes `@main.ts`, "main dot pi" becomes `@main.py`. Trigger words "at" and "tag" are optional. On duplicate names (page.tsx, index.ts) Aqua hands off to the editor's own autocomplete. Source: https://aquavoice.com/llms.txt
- Edit Mode (desktop v0.17.0, 2026-07-20): select text, hold the key, speak the change. Selection cap 6,000 characters. Source: https://aquavoice.com/blog/introducing-edit-mode
- Aqua notes that Claude Code's built-in `/voice` adds project and git-branch names as recognition hints automatically. Source: https://aquavoice.com/blog/voice-dictation-claude-code

### 1.6 API and price

- Avalon API: OpenAI-SDK-compatible `POST /v1/audio/transcriptions` at `https://api.aquavoice.com/v1`, model `avalon-v1.5`. Source: https://aquavoice.com/avalon-api/docs
- Price: $0.39 per audio hour for transcription, $0.49 per audio hour for the dictation endpoint (`POST /v1/dictations`). Billed per second, 10 s minimum. Sources: https://aquavoice.com/avalon-api/docs, https://aquavoice.com/llms.txt
- Batch only: `stream` accepts only `false`. `temperature` only 0. Upload limit 25 MiB, under 1 hour. Source: https://aquavoice.com/avalon-api/docs
- Optional `prompt` field for "Context or vocabulary hints". No length limit is documented. Source: https://aquavoice.com/avalon-api/docs
- What the `/v1/dictations` endpoint adds over plain transcription (LLM formatting, context fields) is not clear from the text I read. Unconfirmed.
- Older page shows base URL `api.aqua.sh/v1` and model `avalon-1`. It is out of date. Source: https://aquavoice.com/avalon-api

### 1.7 Privacy (Aqua)

- Audio is processed in the cloud. Privacy Mode off (default): transcripts may be stored. Privacy Mode on: not stored. Source: https://aquavoice.com/llms.txt
- Deep Context data "is never stored". Source: https://aquavoice.com/llms.txt
- Zero Data Retention on the Business plan. Source: https://aquavoice.com/llms.txt
- No training on user audio unless the user opts in. Source: https://aquavoice.com/blog/introducing-avalon
- The privacy policy does not name LLM or ASR subprocessors. Source: https://aquavoice.com/privacy
- SOC 2 Type II, ISO 27001 (2026-07-14), GDPR and HIPAA programs (2026-09-23). Source: https://aquavoice.com/llms.txt

---

## 2. Wispr Flow

### 2.1 Pipeline

- Two stages: a speech model, then an LLM that formats and interprets the text. Source: https://wisprflow.ai/post/technical-challenges (Sahaj Garg, CTO, Sep 2025)
- ASR: Wispr builds its own ASR. Its current named model is Canto (2026-09-17). Source: https://wisprflow.ai/canto
- LLM stage: fine-tuned Llama models on Baseten dedicated deployments, built with the TensorRT-LLM engine builder, orchestrated with Baseten Chains, in AWS regions near users. Llama version and size are not stated. Source: https://www.baseten.co/resources/customers/wispr-flow/ (undated case study)
- Subprocessors:
  - The public Trust Center lists AWS, Baseten, Vercel, OpenAI and Supabase. Purposes are not shown. Source: https://trust.wispr.ai/
  - A search snippet of a Wispr help article (last updated 2026-03-06) listed "AI/LLM Providers: OpenAI, Anthropic, Cerebras, Baseten, Fireworks AI (for transcription formatting, command mode)". The page now returns 404. Unconfirmed. Old URL: https://docs.wisprflow.ai/articles/5375461355-subprocessors-third-party-security
  - Inference: the formatter is likely a mix of the Baseten Llama fine-tunes and third-party frontier models, possibly with routing by task. Unconfirmed.
- Personalization: per-user ASR conditioning (voice, topics, history). Edits are captured on device. A local RL policy learns style. The LLM has "token level formatting control". Source: https://wisprflow.ai/post/technical-challenges
- Scale in Sep 2025: about 1 billion dictated words per month. Source: https://wisprflow.ai/post/technical-challenges

### 2.2 Latency budget (published)

- Target: full transcription plus LLM formatting within 700 ms of the end of speech. Source: https://wisprflow.ai/post/technical-challenges
- Split: "E2E ASR inference in <200ms, E2E LLM inference in <200ms", network budget up to 200 ms "from anywhere around the world". Source: https://wisprflow.ai/post/technical-challenges
- Baseten case study: under 700 ms end-to-end at p99. The LLM must generate "100+ tokens in under 250 milliseconds". Latency is measured at p90 or p99 per user. Source: https://www.baseten.co/resources/customers/wispr-flow/
- A Wispr job post claims P50 of 500 ms around the globe. Source: https://www.builtinsf.com/job/staff-platform-engineer-infrastructure/10390818 (I saw this only in a search snippet. Unconfirmed.)
- How the budget is met in the API (relevant to a DIY design):
  - Audio streams over WebSocket during speech in 1-second chunks of 16 kHz int16 PCM, then a `commit` message ends it. Source: https://api-docs.wisprflow.ai/websocket_api.md
  - A warm-up endpoint pre-allocates server resources before the user speaks. Source: https://api-docs.wisprflow.ai/warm_up_api.md
  - Client-side auth tokens let the client talk to Wispr directly, without a backend hop. Source: https://api-docs.wisprflow.ai/introduction.md
  - REST is documented as "slower". Source: https://api-docs.wisprflow.ai/introduction.md

### 2.3 Accuracy claims

- Canto: lowest WER on 10 h of real Wispr dictations (2,300+ speakers) against models from Google, OpenAI, AssemblyAI and Deepgram. Source: https://wisprflow.ai/canto
- Challenge set (3 h of noise, whisper, far-field, 1-2-word clips): Canto was second after Gemini 3.1 Pro, and best among real-time models. Source: https://wisprflow.ai/canto
- Public sets: tied for lowest WER on LibriSpeech; competitive but not first on FLEURS and Common Voice. No context prompts were used. Source: https://wisprflow.ai/canto
- The exact WER values are only in chart images. I could not extract them. Unconfirmed.
- Canto training: pretrained base (not named, "millions of hours of speech and text"), then SFT, then RL with GRPO, reward 1-WER. Opt-in user corrections are grafted into references. Source: https://wisprflow.ai/canto
- Context finding that matters for DIY: after RL, the model took a phonetically similar wrong dictionary term "nearly five times as often" as the SFT model. Training with distractors in the context list reduced false adoption. Source: https://wisprflow.ai/canto
- A successor model at more than 10x Canto's scale is in training. Source: https://wisprflow.ai/canto
- Hard English test sets: WER from 3% to 2% had "little practical effect". The CTO argues ASR is a "mixed-modal, context driven problem". Source: https://wisprflow.ai/research/speech-recognition-challenges
- No coding-specific WER or key-term benchmark is published by Wispr. Unconfirmed.

### 2.4 Context sent (app and screen)

API request schema (`context` object). Source: https://api-docs.wisprflow.ai/request_schema.md

- `app.name`, `app.type` (`email`, `ai`, `other`). The `ai` type is for prompting an AI agent.
- `dictionary_context`: list of rare names and words.
- `user_identifier`, `user_first_name`, `user_last_name`.
- `textbox_contents`: `before_text`, `selected_text`, `after_text`. Used for casing, spacing and punctuation.
- `screenshot`, or `content_text` ("a more efficient way of providing context compared to screenshot"), or `content_html`.
- `conversation`: id, participants, recent messages with roles.
- Audio limit: 25 MB or 6 minutes.

Desktop app behavior. Source: https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness

- Context Awareness reads text, not screenshots: "does not take screenshots".
- It reads textbox contents, on-screen text, variable and file names in coding apps, app category, and conversation history.
- On Mac it needs Accessibility permission.
- It skips password fields, banking apps, numeric-only fields and URL bars. It skips context if it "cannot complete quickly".
- Captured text is cleared when the dictation ends.
- With the feature off, Flow still sends app name and domain.

### 2.5 Developer features

Source: https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides

- Variable recognition in Cursor, Windsurf and VS Code. It needs the IDE's "Screen Reader Optimized" mode, so that the accessibility tree exposes editor text.
- Flow uses visible variable, function and class names. Loose match: "user ID" can match `userId`. Off-screen and very large file content can be skipped.
- File tagging (`@file`) only in Cursor and Windsurf chat panels. Say the full name with extension, or "tag"/"at" plus the base name. The name must contain a dot. Any dictionary or snippet substitution turns off tagging for that dictation.
- Terminals: tagging is skipped in terminals. Long dictations to Claude Code and Codex CLI on Mac are pasted in parts.
- Marketing claims camelCase, snake_case and acronym handling, but gives no numbers. Source: https://wisprflow.ai/developers

Other features:

- Personal Dictionary: 60 characters per entry, no stated entry cap. Auto-learn skips file names, paths, URLs, code symbols, keys, hashes and IDs, so you must add code terms by hand. Source: https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary
- Command Mode: hold a shortcut and speak an instruction. It sends "current text box contents and selected text" to an LLM. Off by default (Settings, Experimental). Pro only. The model is not named. Source: https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode

### 2.6 Privacy and data retention (Wispr)

- Dictation Cloud Storage defaults to on. With it on, Wispr stores "dictation transcripts, audio and history". Source: https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow
- "Improve the model for everyone" defaults to on for Free and Pro, and is off for Enterprise. Source: https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq
- Third-party AI providers "may not use your data to train their models". Source: https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq
- Data is processed and stored in the United States. Source: https://docs.wisprflow.ai/articles/3467817258-security-and-compliance-faq
- "Enforce zero data retention" is an Enterprise admin control. Source: https://docs.wisprflow.ai/articles/9609615338-private-cloud-sync-and-data-sharing-preferences-in-wispr-flow
- A ZDR certificate with Anthropic (December 2025) appeared only in a search snippet. Unconfirmed.

---

## 3. Other apps (brief)

| App | Pipeline facts | Latency or accuracy numbers | Source |
|---|---|---|---|
| Superwhisper | Two independent stages: voice model (local or cloud), then optional LLM (local on macOS, or cloud). Super Mode reads app context (input fields, window title), selected text and clipboard via accessibility APIs. Selected text is captured at record start. Clipboard is captured within 3 s before or during recording. App context is captured after ASR and before the LLM step. The docs warn that extra context "can hurt result quality". | None published that I found. | https://ai.superwhisper.com/docs/common-issues/context.md, https://ai.superwhisper.com/docs/modes/super.md, https://superwhisper.com/docs/security |
| VoiceInk | Open source (GPLv3), macOS. Local ASR via whisper.cpp, Parakeet (FluidAudio) and transcribe.cpp GGUF. Optional AI enhancement. "Power Mode" per app. README claims context awareness from screen content. The mechanism (OCR or accessibility) is unconfirmed. | README claims "99% accuracy", with no method. | https://github.com/Beingpax/VoiceInk |
| Willow Voice | Model and providers not disclosed. Claims a context-aware engine and reads open files in Cursor and Windsurf. | Self-reported "~200 ms" (190-230 ms by clip length) from its own Sept 2026 benchmark, with no method disclosed. The same page puts Wispr at 400-900 ms and Aqua at 550-800 ms. | https://willowvoice.com/blog/whisper-ai-vs-willow-fastest-voice-dictation |
| Monologue (Every) | Screen-aware "deep context" for tone. "About Me" field. Models not disclosed. | None found. | https://www.monologue.to/, https://every.to/on-every/introducing-monologue-effortless-voice-dictation |
| MacWhisper | Not researched in depth. No architecture or latency post found in this pass. | Unconfirmed. | - |

---

## 4. Design lessons for a DIY technical-dictation app

1. **Use two stages.** First an ASR with vocabulary biasing, then a small, fast LLM formatter. Both Wispr (ASR plus Llama fine-tunes) and Aqua (Avalon plus LLM post-processing) use this design.
2. **Stream audio while the user speaks.** Wispr streams 1-second PCM chunks over WebSocket and pre-warms the connection. Most ASR work is then done at key-up. A batch-only ASR (for example the Avalon API) puts all upload and inference time after key-up.
3. **Set a latency budget from key-up.** Wispr's public split is ASR <200 ms, LLM <200 ms, network <=200 ms, total <700 ms at p99. For the LLM, the target is 100+ output tokens in <250 ms. Aqua's best case is ~450 ms. Measure p90/p99, not only the mean.
4. **Send text context, not screenshots.**
   - Wispr's own API says `content_text` is more efficient than `screenshot`, and its desktop app sends no screenshots.
   - Send: app type (`ai`/`email`/`other`); text before, after and selected at the cursor; visible identifiers from the accessibility tree (VS Code needs Screen Reader mode); workspace file names for `@` tags; a short dictionary list.
5. **Keep context lists short and relevant.** Canto showed that a context-tuned model can over-trust wrong but similar terms (about 5x). Superwhisper warns that extra context lowers quality. Rank candidate identifiers by relevance (visible on screen, open files, recent git changes). Do not dump the full repository.
6. **Use the context in the ASR stage when you can.** A post-hoc LLM can only fix words the ASR heard well enough. Both Avalon (`prompt`) and Canto (dictionary at runtime) take hints inside the ASR stage.
7. **Detect facts in code; let the LLM write the text.**
   - Code can match spoken file names to real files. Wispr requires a dot. Aqua maps "main ts" to `@main.ts` and hands duplicates to the editor's autocomplete.
   - Pass the matched candidates to the LLM as context. Let the LLM write the final text. Spoken casing cues ("camelCase user ID") are a cheap, explicit signal.
8. **Choose the ASR model for jargon, not for public-benchmark WER.** On AISpeak, Parakeet and Canary scored 50-75% on key terms but do well on public sets. Whisper Large v3 scored 65-85%. Test candidates on your own recorded coding prompts.

---

## Unresolved questions

1. Which Whisper checkpoint is Avalon's base, and what is its size? The model card says only "derived from Whisper".
2. Which LLM does Aqua use for post-processing, and which third-party provider powers Realtime Mode? Both are not public; they may be in the Vanta Trust Center behind a request.
3. Does Aqua's Deep Context use the accessibility tree, OCR or screenshots, and what is sent to the server?
4. What are Canto's exact WER values? They are only in chart images on https://wisprflow.ai/canto.
5. Is the Wispr subprocessor list with Anthropic, Cerebras and Fireworks AI still current? The help article now returns 404.
6. What does Aqua's `/v1/dictations` endpoint ($0.49/h) add over `/v1/audio/transcriptions` ($0.39/h)? Context fields? LLM formatting?
7. The AISpeak dataset is not public, so no one can reproduce the 97.4% number independently.
8. Aqua's speed claim for Avalon 1.5 conflicts: "2x faster than Avalon 1" (llms.txt) versus "2x faster than Scribe v2" (iOS blog). Aqua startup is "<50 ms" in one place and "<200 ms" in another.
9. No independent, same-audio latency benchmark across Wispr, Aqua and Willow exists. All latency numbers are vendor self-reports.
