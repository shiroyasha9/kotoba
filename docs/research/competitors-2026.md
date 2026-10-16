# Competitors in 2026: Mac dictation apps

Status: research, 2026-10-17. Agent `competitors`. Read-only on the kotoba code. No sign-up, no payment, no API key was used.

Access date: every URL in this file was read on 2026-10-17, unless the line names an earlier kotoba research file.

Scope: Wispr Flow (pricing and complaints only), Willow Voice, Aqua Voice, Superwhisper, Typeless, MacWhisper, VoiceInk, Spokenly, Voibe, Monologue, the free open-source group (Handy, FluidVoice, OpenWhispr, FreeFlow, Ghost Pepper), and Apple's built-in Dictation.

Earlier work that this file does not repeat:
- `dictation-apps.md`: Aqua and Wispr pipelines, Avalon model card, Wispr latency budget and API context schema.
- `landscape-macos.md`: open-source apps, licences, stacks, macOS hotkey and paste facts.
- `beyond-wispr.md`: the Wispr 2026 changelog, accuracy methods, interaction details.
- `stt-vendors.md`: speech APIs and prices.
- The ranked gap list against Wispr Flow is in `<runbooks>/2026-10-17-wispr-flow-survey/kotoba-plan.md` ("plan item N" below).

Marks:
- **UNCONFIRMED**: one secondary source only, or a source that I could not open.
- **COMPETITOR**: the source is a rival dictation vendor. Its numbers for other apps are biased.
- Latency and accuracy numbers are vendor self-reports, unless the line says otherwise. No independent same-audio latency test across these apps exists.

Reddit blocked automated access, and web search returned no Reddit threads. User quotes come from Hacker News, GitHub issues, feedback boards and App Store reviews.

## Summary

- The category splits in two. Group 1 is cloud subscriptions at $8-15 a month (Wispr, Willow, Aqua, Typeless, Monologue). Group 2 is local-first apps with one-time or no price (Superwhisper lifetime, MacWhisper, VoiceInk, Spokenly, Handy, FluidVoice). kotoba is in neither group: cloud quality, own key, no subscription, about $0.10 per hour of audio.
- Free tiers got smaller in 2026. Typeless cut its free tier from 8,000 to 2,000 words a week. Aqua gives 1,000 words in total. Wispr gives 2,000 words a week on desktop.
- Every subscription app added scope in 2026: meetings (Wispr Notetaker, Superwhisper 3.0, Monologue, OpenWhispr), a rewrite product (Willow Scribe, Wispr Transforms), even a pet (Aqua). Users praise speed, accuracy on jargon and one-time prices. They complain about price, AI that changes their words, privacy defaults, RAM and unstable releases.
- Apple's Dictation on macOS 27 has no time limit and a new on-device model, but only on M3 or newer Macs with 12 GB or more. It has no custom vocabulary. A developer API (SpeechAnalyzer) beat Whisper Small in one vendor-run test.

## 1. Comparison table

"Cloud" means that audio leaves the Mac by default. "BYOK" means that the user can use their own API key.

| App | Platforms | Stack | Speech | Cleanup and per-app style | Context | Dictionary and learning | Edit mode | Price (USD unless noted) | BYOK |
|---|---|---|---|---|---|---|---|---|---|
| Wispr Flow | Mac, Win, iOS, Android | Electron | Cloud (own Canto model) | Auto Cleanup, 4 levels; styles per app category | AX text, no screenshots (`dictation-apps.md` 2.4) | Yes; auto-add skips code symbols | Command Mode, Transforms | Free 2,000 words/week desktop; Pro $15/mo or $12/mo yearly | No |
| Willow Voice | Mac, Win, iPhone | Not stated | Cloud; "offline mode" claimed | Smart formatting; tone per app; Scribe rewrite | Optional, text near cursor | Auto-learn, made "less aggressive" | Scribe | Free (word limit not stated, 20 Scribe/week); Pro $15/mo or $12/mo yearly | No |
| Aqua Voice | Mac, Win, iOS, Android | Not stated | Cloud (own Avalon model) | Custom Instructions | Deep Context, off by default | Up to 800 entries (Pro) | Edit Mode | Free 1,000 words total; Pro $10/mo or $8/mo yearly; Max $30/mo or $24/mo yearly | No |
| Typeless | Mac, Win, Linux, iOS, Android | Not stated | Cloud | Fillers, self-corrections, auto lists; tone per app | App name and nearby text | Auto and manual | Speak to edit | Free 2,000 words/week (since 2026-09-22); Pro $30/mo or $12/mo yearly | No |
| Superwhisper | Mac, Win, iOS, Android | Not stated | Local or cloud | Modes with LLM; S1-mini local cleanup | Super Mode: app text, selection, clipboard | Vocabulary + replacements; no edit learning found | Modes on selection | Free (local Whisper, 2 modes); Pro $8.49/mo, $84.99/yr, $249.99 lifetime | Pro only |
| MacWhisper | Mac, iPhone, iPad | Not stated | Local or cloud | AI cleanup with own key; prompt per app | Not found | Not found | Not found | Free; Pro EUR 64-65 one time | Yes (Pro) |
| VoiceInk | Mac (Apple Silicon), iOS | Native Swift, GPL-3.0 | Local or cloud | Modes per app, URL, trigger word | Selection, clipboard, screen OCR, per mode | Auto Learn, on by default | Not found | $25 / $39 / $49 one time (1 / 2 / 3 Macs) | Yes |
| Spokenly | Mac, Win, Linux, iOS, Android | Not stated | Local or cloud | Modes per app, website, trigger word; local cleanup model | Clipboard, app, text around cursor, URL | Words + regex replacements | Not found | Free (local + BYOK); Local+ $29 one time; Pro $9.99/mo or $99.99/yr | Yes, free |
| Voibe | Mac, Win | Not stated | Local (Mac) or cloud | Filler removal, optional AI | Developer Mode for Cursor and VS Code | Custom vocabulary | No | Dictation $9.90/mo, $99/yr, $199 lifetime | No |
| Monologue | Mac, iPhone, iPad, Watch | Not stated | Local or cloud | Modes per app (Chat, Email, Notes, Coding) | Screen, with permission | Builds as you use it | Not found | Free 1,000 words total; Pro $15/mo or $144/yr | No |
| Handy | Mac, Win, Linux | Tauri, MIT | Local only | Optional post-process hotkey | No | Dictionary | No | Free | n/a |
| FluidVoice | Mac | Native Swift, GPL-3.0 | Local only | Optional AI cleanup | Not found | Not found | Write Mode, Command Mode | Free | For cleanup |
| Apple Dictation | Mac (all), new model on M3+ with 12 GB+ | System | On device or Apple servers | Auto punctuation | No | No custom vocabulary announced | Voice Control only | Free | n/a |
| kotoba | Mac (macOS 26+) | Native Swift | Cloud, own key (OpenRouter) | Raw text first; cleanup on its own chord; modes per app | No (parked) | Phrase hints, replacements, learning from edits | No | Free, open source; about $0.10/h audio | Yes, required |

Sources for each cell are in section 2. kotoba facts come from `README.md`.

## 2. Per-app notes

### 2.1 Wispr Flow (pricing and complaints)

- Free: 2,000 words a week on desktop and 1,000 on mobile, with "Limited Notetaker access". Pro: $15 a month, or $12 a month yearly. Growth: $23 a month, or $18 a month yearly (the page also shows $33 and $26 with no label). https://wisprflow.ai/pricing
- Some new accounts get no trial. They get a one-time bonus of 8,000 words when they first reach the cap. https://docs.wisprflow.ai/articles/4760791189
- Notetaker came to Mac on 2026-08-05 and to Windows on 2026-09-15. It is in all plans. It records mic and system audio, with no bot in the call. https://wisprflow.ai/whats-new
- "Notetaker transcripts and summaries are stored in Wispr's cloud with no setting to opt out." The training switch also covers Notetaker, and it is on by default for Free and Pro. https://docs.wisprflow.ai/articles/3842996553-privacy-mode-private-cloud-sync
- Uploaded meeting audio is deleted after 7 days. Transcripts stay until the user deletes the meeting. https://docs.wisprflow.ai/articles/4497184932-notetaker-privacy-and-security-overview
- Computerworld names consent of other call members as the main concern. https://www.computerworld.com/?p=4206765
- 2026 changes: Auto Cleanup with 4 levels (Apr 24), local transcript storage with delete after 24 h (Apr 24), outages and a rolled-back cleanup setting (Jun 4-10), "30% lower latency" (Jul 9), 14 days of audio playback (Aug 5), double-tap to lock hands-free (Aug 21), Canto ASR (Sep 17). https://wisprflow.ai/whats-new
- Trust: TechCrunch reported that Wispr's earlier SOC 2 vendor, Delve, was accused of fake compliance reports. https://techcrunch.com/2026/03/22/delve-accused-of-misleading-customers-with-fake-compliance/ . The link to Wispr comes from a COMPETITOR page: https://www.getvoibe.com/resources/is-wispr-flow-safe/
- The wisprflow.ai Trustpilot profile was "removed from Trustpilot for violating its guidelines". https://www.trustpilot.com/review/wisprflow.ai
- iOS reviews: "Too expensive!", "super buggy", "everything i said was just eaten". https://itunes.apple.com/us/rss/customerreviews/id=6497229487/sortby=mostrecent/json
- Earlier facts (RAM 748 MB idle, telemetry, Auto Cleanup as "the main driver of recent accuracy issues"): see `beyond-wispr.md` section 1.2.

### 2.2 Willow Voice

- Mac, Windows and iPhone. Android is "Coming soon". https://willowvoice.com/pricing
- Default hotkey Fn. Up to 4 hotkeys. Double-tap starts "No Hands Mode". https://help.willowvoice.com/en/articles/10876257-hotkey-settings
- Learns writing style from edits; tone per app; auto-dictionary made "less aggressive". https://willowvoice.featurebase.app/changelog . The public changelog has no entry after 2025-10-07.
- Scribe turns rough speech into polished text. Free gets 20 Scribe uses a week. https://willowvoice.com/pricing
- Context Awareness is optional and reads text near the cursor; the data "is not stored". The default is not stated. History and audio stay on the device. Private Mode is on by default. Training is opt-in and uses text only. Zero data retention only on Business and Enterprise. https://help.willowvoice.com/en/articles/12854269-how-willow-protects-your-data-and-privacy
- Price: Pro $15 a month or $12 yearly; Business $35 or $28. The free tier has a "Word limit" row with no number. https://willowvoice.com/pricing . Earlier sources say 2,000 words a week (UNCONFIRMED, COMPETITOR): https://www.getvoibe.com/resources/willow-voice-review/
- Latency: self-reported 190-230 ms; Willow's numbers for rivals change from post to post. https://willowvoice.com/blog/dictation-accuracy-zero-edit-rate-benchmark
- Praise: "almost instantaneous" https://news.ycombinator.com/item?id=44432703 ; "great UI or UX" https://news.ycombinator.com/item?id=44943652
- Hate: "$144/year" for work that can run locally https://news.ycombinator.com/item?id=45923353

### 2.3 Aqua Voice

- Mac, Windows, iOS, and Android 0.1.0 (2026-10-06). Liquid Glass bar in 0.20.0 (2026-09-22). Windows mic start 298 ms to 122 ms (2026-09-14). "Aqua Pet" (2026-10-13). https://aquavoice.com/changelog
- Price: Free 1,000 words in total. Pro $10 a month or $8 yearly. Max $30 or $24, with Realtime Mode and "Send it". Business $24 or $19 per seat with zero data retention. Students 70% off. No BYOK, no lifetime. https://aquavoice.com/pricing
- With Privacy Mode off, Aqua "may securely store transcript data... to improve the product". The policy does not give the default. https://aquavoice.com/privacy
- Praise: "jargon, capitalization, everything" https://news.ycombinator.com/item?id=46889253 ; "in another league" for accuracy https://news.ycombinator.com/item?id=43640084
- Hate: voice edit commands "took a lot longer than making an edit myself" https://news.ycombinator.com/item?id=43641515 ; users ask for privacy guarantees https://news.ycombinator.com/item?id=43641065
- Pipeline, Deep Context, Edit Mode and latency: see `dictation-apps.md` section 1.

### 2.4 Typeless

- Mac, Windows, Linux, iOS and Android. https://www.typeless.com/
- Hold Fn to dictate; Fn+Space for hands-free; Fn+Left Shift for translation (v2.0.0, July 2026). https://www.typeless.com/help/quickstart/first-dictation , https://www.typeless.com/help/release-notes/macos/translation-mode
- Removes fillers and repeats, keeps the last version of a self-correction, turns spoken lists into bullets, changes tone per app. "Speak to edit" works on selected text. https://www.typeless.com/
- Sends "voice audio along with limited contextual information", including the app name and related text. Audio and text can go to "Microsoft and Google" AI providers; data is processed in the US. History stays on the device by default. https://www.typeless.com/privacy
- A reverse-engineering report on v0.9.3 found a plaintext local database with transcripts and URLs, and audio that was not fully deleted (UNCONFIRMED, relayed by one article). https://en.kocpc.com.tw/?p=5421
- Price: Pro $12 a month yearly ($144), or $30 monthly. No BYOK, no lifetime. https://www.typeless.com/pricing
- Free tier cut from 8,000 to 2,000 words a week on 2026-09-22, by an in-app notice. https://note.com/takuma_hayakawa/n/nc22e87f9ecc0?hl=en
- Hate (iOS reviews): "2000 words is never enough", "PARAPHRASES WHAT YOU WANT TO SAY", "Quality is degrading", upgrade pop-ups that lose text. https://itunes.apple.com/us/rss/customerreviews/id=6749257650/sortby=mostrecent/json
- Hate: the cleanup added a `.bash_profile` note that the user did not say. https://note.com/jaga_farm/n/n47cd9ee4d3a2?hl=en ; "stripping away my thought process" https://en.astrian.lol/think-dont-speak/
- Users built open-source replacements. https://news.ycombinator.com/item?id=49862800

### 2.5 Superwhisper

- macOS 14+, Windows, iOS keyboard, Android bubble. https://superwhisper.com/docs/llms.txt
- Toggle ⌥Space by default; separate push-to-talk shortcut; Esc cancels (a recording over 30 s asks first). https://superwhisper.com/docs/get-started/essential-settings.md , https://superwhisper.com/docs/get-started/interface-rec-window.md
- 2026: own S1 models with on-device S1-mini cleanup (Aug); all local Whisper models free on macOS (2.18.2); silence removal and clipboard restore on by default (2.18.3); paste 300 ms faster (2.16.2); Meetings with speaker labels (3.0.0, 2026-10-15). https://superwhisper.com/changelog
- Modes switch per app. History keeps audio, raw text and AI result, and can reprocess a recording with another mode. "Keep recordings for" defaults to Forever. https://superwhisper.com/docs/billing/plans.md , https://superwhisper.com/docs/get-started/history.md
- Docs: "too much vocabulary can hurt transcription". https://superwhisper.com/docs/get-started/interface-vocabulary.md
- Transcripts and audio stay on the device; cloud providers under zero retention terms. https://superwhisper.com/docs/security/account-deletion.md , https://superwhisper.com/docs/security/sensitive-data.md
- Vendor benchmark: S1 Voice 6.6% WER at 26x real time, Wispr (raw) 8.7% at 5.1x. https://superwhisper.com/benchmarks
- Price: Pro $8.49 a month, $84.99 a year, $249.99 lifetime; BYOK only in Pro. https://superwhisper.com/docs/billing/plans.md
- Hate: a 2-5 s delay before the waveform responds "more than half the time", so first words are lost. https://superwhisper.userjot.com/board/p/reduce-1-sec-latency-between-toggle-key-press-and-recording-start ; "superwhisper too clever" https://news.ycombinator.com/item?id=47042753 ; "not cheap" https://news.ycombinator.com/item?id=47669046
- Praise: "Are there any better than Superwhisper? Because I haven't found any." https://news.ycombinator.com/item?id=47669052

### 2.6 MacWhisper

- A file transcriber first. Dictation is one feature in a long list. https://goodsnooze.gumroad.com/l/macwhisper
- The Mac App Store edition has no dictation because of App Store rules. https://macwhisper.helpscoutdocs.com/article/14-how-to-use-the-dictation-feature
- Cleanup needs the user's own AI key; a prompt per app. https://macwhisper.helpscoutdocs.com/article/31-app-specific-dictation-prompts
- Privacy policy: "No data (audio, text or other) leaves your device" (last updated Feb 2024, before the cloud options). https://www.macwhisper.com/legal/privacy-policy
- Price: Pro EUR 64 on the site, EUR 65 on Gumroad, one time. https://www.macwhisper.com/
- Hate: "slow development and lack of focus and dictation" https://news.ycombinator.com/item?id=49081002 ; "overkill" https://news.ycombinator.com/item?id=47042753

### 2.7 VoiceInk

- Native Swift, Apple Silicon, macOS 14.4+. Version 2.21 on 2026-09-28. https://github.com/Beingpax/VoiceInk/releases
- Shortcut styles: Toggle, Push to Talk, Hybrid, Double Tap (new in 2.21). Paste last (raw or enhanced) and retry last. https://tryvoiceink.com/docs/shortcuts
- Modes switch by app, URL, spoken trigger word or shortcut. https://tryvoiceink.com/docs/mode-triggers
- Context per mode: selection, clipboard, screen OCR (needs Screen Recording). It takes a snapshot of all of them at each start; the switches only decide what it sends. https://tryvoiceink.com/docs/context-awareness
- Auto Learn is on by default: it diffs a user correction and asks an LLM if the change is a term. https://tryvoiceink.com/docs/auto-learn-dictionary
- History auto-delete: transcripts from immediate to 7 days, audio 1-30 days. https://tryvoiceink.com/docs/transcription-history
- Price: $25 / $39 / $49 one time for 1 / 2 / 3 Macs. https://tryvoiceink.com/
- Hate (GitHub): #700 "every release breaks something different"; #735 shortcut fails on macOS 26; #634 100% CPU at idle; #827 modes lost on 2.0 upgrade; #989 "2.21 broke auto send"; #760 updater leaks GBs of memory. https://github.com/Beingpax/VoiceInk/issues
- Praise: "one-time licence... this is the future of AI pricing" https://news.ycombinator.com/item?id=47050558

### 2.8 Spokenly

- Mac (direct download; the App Store edition is "no longer being updated"), Windows, Linux, iOS, Android. Not open source. https://spokenly.app/changelog
- Per mode: trigger style, model, AI provider with fallback, output action (insert, paste and Enter, clipboard). Modes switch by app, website, trigger word, shortcut. Pre and post bash scripts. https://spokenly.app/llms-full.txt
- Capsule indicator with live text (2.30.8, 2026-10-05), paid. https://spokenly.app/releases/macos
- Local cleanup model (2.31.0, 2026-10-11): off by default, 768 MB download, about 600 MB memory while active, about 0.2 s for 1-2 sentences, 5-15 s for several hundred words. https://spokenly.app/llms-full.txt
- Privacy: BYOK requests go direct to the provider; built-in cloud goes through Spokenly's backend, which "does not store" audio. In-house analytics of clicks and views. https://spokenly.app/privacy
- Price: Free (local + BYOK); Local+ $29 one time; Pro $9.99 a month or $99.99 a year. https://spokenly.app/pricing
- Praise: free local Parakeet, "Very happy with it" https://news.ycombinator.com/item?id=46741885 ; a user left VoiceInk for Spokenly because it was "more stable overall" https://news.ycombinator.com/item?id=47048515

### 2.9 Voibe

- Mac and Windows. Local Whisper on the Neural Engine, or cloud through Groq and Cerebras. Live Dictation shows an editable draft. Price: $9.90 a month, $99 a year, $199 lifetime. https://www.getvoibe.com/ , https://www.getvoibe.com/pricing/
- Lifetime deals sold for $40-80. https://boingboing.net/2026/05/22/mac-people-who-think-faster-than-they-type-the-voibe-dictation-tool-is-now-40-for-lifetime-access.html
- Traction is weak: no HN posts found; most search hits are Voibe's own comparison pages.

### 2.10 Monologue (Every)

- Hold right Option; double press for hands-free. https://docs.monologue.to/getting-started/mac
- Modes per app; screen context "with permission"; notes and meeting recording; MCP, API and CLI. https://www.monologue.to/
- Price: Free 1,000 words in total; Pro $15 a month or $144 a year. https://www.monologue.to/pricing.md

### 2.11 Free open-source group

- Handy: Tauri, MIT, local only, 33,969 stars. Silero VAD removes silence before the model runs. https://github.com/cjpais/Handy . Praise: "Just canceled my WisprFlow subscription" https://news.ycombinator.com/item?id=49334327 . Open bug: Handy sometimes pastes the old clipboard, not the transcript; the reporter suspects high CPU load. https://github.com/cjpais/Handy/issues/502
- FluidVoice: native Swift, GPL-3.0, local only, 12,232 stars; Write Mode and Command Mode. https://github.com/altic-dev/FluidVoice
- OpenWhispr: Electron, MIT; free 2,000 cloud words a week, Pro $80 a user a year. https://openwhispr.com/pricing
- FreeFlow and Ghost Pepper: see `landscape-macos.md`. Ghost Pepper's local cleanup takes "~1-2s" by its own README. https://github.com/matthartman/ghost-pepper

### 2.12 Apple Dictation

- "You can dictate text of any length without a timeout." It stops after 30 s with no speech. Auto punctuation can be turned off. Uncertain words get a blue underline. Full voice editing needs Voice Control, which turns normal Dictation off. Audio retention for "improve Siri and Dictation" is opt-in. https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac
- macOS 27 has a new on-device dictation model only on "an M3 or newer Mac with at least 12GB of memory". The reviewer saw errors with fast or quiet speech on an M1 Max and exact text on an M4 Max. https://www.macstories.net/stories/macos-27-the-macstories-review/8/
- iOS 27 has an "Advanced Dictation Preview" with an on-device LLM. https://9to5mac.com/2026/06/12/ai-advanced-dictation-preview-ios-27-beta/ . macOS 27 did not get its text-editing commands (UNCONFIRMED). https://mjtsai.com/blog/?p=53474
- SpeechAnalyzer (macOS 26) is open to developers, with system-managed models. https://developer.apple.com/videos/play/wwdc2025/277/ . A vendor-run test on LibriSpeech (M2 Pro): WER 2.12% clean and 4.56% noisy, against 3.74% and 7.95% for Whisper Small, about 3x faster. Whisper Large and Parakeet were not tested. https://get-inscribe.com/blog/apple-speech-api-benchmark.html
- HN users ask if the built-in API makes paid apps unnecessary: "if MacOS 26 does it right - all of this is no longer necessary". https://news.ycombinator.com/item?id=50042333

## 3. Features worth taking

Ranked for a fast, no-BS app: value for prompts to coding agents, divided by cost in stop-path latency, idle memory and effort. "In plan" means the item is already in `kotoba-plan.md`.

| Rank | Feature | Who has it (evidence) | Why it fits kotoba | Status |
|---|---|---|---|---|
| 1 | Re-transcribe a saved dictation with another model, and play its audio | Superwhisper reprocess with another mode (2.5); VoiceInk "retry last" (2.7); Wispr 14-day playback (2.1) | Fixes a bad transcript with no re-dictation. Zero hot-path cost. | In plan (items 4, 5) |
| 2 | Trim silence before upload | Superwhisper silence removal on by default, 2.18.3 (2.5); Handy Silero VAD (2.11) | Fewer bytes to upload and fewer billed seconds. Can lower stop-to-paste time. Must not clip speech: measure on bench clips first. | New |
| 3 | Double-tap push-to-talk locks hands-free | Wispr (2.1), VoiceInk 2.21 (2.7), Willow (2.2), Monologue (2.10), Typeless Fn+Space (2.4) | Now the common pattern; new users from Wispr expect it. | In plan (item 8) |
| 4 | Copy Last shortcut | Wispr (`beyond-wispr.md` 1.1); VoiceInk paste last, raw or enhanced (2.7) | One chord, no new UI. | In plan (item 2) |
| 5 | Rewrite on demand, never on the main path, with a diff to the raw text | Willow Scribe (2.2), Wispr Transforms (2.1), Typeless Speak to edit (2.4), Aqua Edit Mode, FluidVoice Write Mode (2.11) | Users want it, but hate it when it runs by default (section 4). A separate chord and a diff keep trust. | In plan (items 1, 6) |
| 6 | Choice of submit key per app (Return, ⌘Return, ⌃Return) | Aqua "Send it" with submit-key choice (2.3); Spokenly "paste and Enter" per mode (2.8) | kotoba already sends Return; some chat apps need ⌘Return. | New (refines plan item 34) |
| 7 | Retention controls for transcripts and audio | VoiceInk transcripts immediate to 7 days, audio 1-30 days (2.7); Wispr delete after 24 h (2.1); Superwhisper 1 day to Forever (2.5) | A clear privacy promise in one setting. | Spec (audio retention, phase 3) |
| 8 | Show what was sent with each History row (model, hint terms, mode) | Superwhisper History shows all that was sent to the AI (`beyond-wispr.md` section 2) | Makes accuracy tuning possible; proves the privacy claim. | New (idea 9 in `beyond-wispr.md`, not in plan) |
| 9 | CLI or MCP access to the last dictation and the history | Spokenly MCP voice input (2.8), Superwhisper CLI/MCP (2.5), Monologue MCP and CLI (2.10), Wispr Notetaker MCP (2.1) | Fits users who work in Claude Code. No idle cost if it reads the store on demand. | New (low) |
| 10 | Regex replacement rules | Spokenly (2.8) | Cheap power for paths and flags. | New (low) |
| - | Live text while speaking | Aqua Realtime (Max), Spokenly Capsule, Voibe Live Dictation, FluidVoice | Costs stop-path latency (Aqua: about 850 ms streaming vs 450 ms instant, `beyond-wispr.md` section 2). | Out of scope (spec) |
| - | Meetings and notes | Wispr, Superwhisper 3.0, Monologue, OpenWhispr | Large scope; see anti-pattern 1. | In plan (items 25-29, ask the owner) |

## 4. Anti-patterns to avoid

| # | Anti-pattern | Evidence |
|---|---|---|
| 1 | A second product bolted on and pushed to all users, with weaker privacy than the core | Wispr Notetaker is in every plan; its transcripts are stored in the cloud "with no setting to opt out", and training is on by default (2.1). Computerworld names call consent as the main concern (2.1). Superwhisper (3.0), Monologue and OpenWhispr also added meetings. MacWhisper users complain about "lack of focus and dictation" (2.6). |
| 2 | An LLM that rewrites the user's words by default | Wispr's own changelog: Auto Cleanup was "the main driver of recent accuracy issues" (`beyond-wispr.md` 1.2). Typeless: "PARAPHRASES WHAT YOU WANT TO SAY", "Quality is degrading", an invented `.bash_profile` note (2.4). Superwhisper "too clever" (2.5). HN: "If you don't want this AI-based rewriting, just don't use it." https://news.ycombinator.com/item?id=50053546 |
| 3 | Privacy and training switches that default to "on" | Wispr training on for Free and Pro (2.1). Aqua may store transcripts when Privacy Mode is off, default not stated (2.3). HN: "many of these dictations app opt you into Context awareness, which means your entire page contents get streamed to their server" https://news.ycombinator.com/item?id=48531184 |
| 4 | Heavy runtime and work at idle | Wispr 748 MB idle (`beyond-wispr.md` 1.2). Spokenly local cleanup about 600 MB while active (2.8). VoiceInk 100% CPU at idle and an updater memory leak (2.7). HN: "Electron or Tauri... a lot more memory and CPU" https://news.ycombinator.com/item?id=50077458 |
| 5 | Metered words and free tiers that shrink | Typeless 8,000 to 2,000 words a week (2.4); Aqua 1,000 words in total (2.3); Wispr experiments with trials and bonuses (2.1). HN: "Why do voice transcription apps charge monthly when Whisper runs locally?" https://news.ycombinator.com/item?id=45923353 |
| 6 | Slow start that loses the first words | Superwhisper 2-5 s before the waveform responds; an earlier cause was waiting for the start sound to finish (2.5). |
| 7 | Releases that break core paths | VoiceInk #700, #735, #989 (2.7). Wispr outages from "scaling changes" (2.1). |
| 8 | Upsell that interrupts dictation | Typeless upgrade pop-ups that lose the user's text (2.4). |
| 9 | Compliance claims that users cannot check | Wispr's SOC 2 vendor Delve was accused of fake reports (2.1). Typeless claims "Zero cloud data retention", but one report found audio not fully deleted on the device (2.4, UNCONFIRMED). |

## 5. Differentiation angles for kotoba

1. **The only cloud-quality app with no subscription and no word meter.** Every cloud app in section 1 charges $8-30 a month or caps words. kotoba costs about $0.10 per hour of audio with the user's own key. Spokenly and VoiceInk allow BYOK, but they are local-first, and their cloud paths are not tuned for jargon.
2. **Raw words by default.** kotoba pastes the transcript. Cleanup runs only on its own chord. This is a direct answer to anti-pattern 2, with Wispr's own changelog as proof.
3. **Measured, published numbers.** kotoba publishes p50/p90 latency, idle memory and term accuracy with a method (`docs/benchmarks.md`). No competitor publishes p90 latency; Willow's and Aqua's rival numbers have no method. Keep each claim reproducible.
4. **Small and quiet.** 15.9 MB idle, a 5.7 MB download, no telemetry, no account (`README.md`). Most competitors do not state their stack; Wispr and OpenWhispr are Electron.
5. **Built for prompts to coding agents.** Term hints, learning that keeps identifiers (Wispr's auto-add skips them), "Fix Last Dictation" for terminals, and Return to submit. Aqua is the closest rival here, but it is subscription-only.
6. **One job.** No meetings, no pet, no upsell. A focused product is now rare in this category (anti-pattern 1). If meetings come, make them a separate opt-in with local files only.
7. **Open source under a permissive licence.** kotoba is Apache-2.0 (`LICENSE`). VoiceInk and FluidVoice are GPL, and VoiceInk does not accept PRs. kotoba can be the native open app that takes contributions.

Follow-up risk (not fixed): kotoba restores the clipboard after a fixed `restoreDelay` of 1 s (`KotobaCore/Sources/KotobaCore/PipelineInterface.swift:182`), guarded by the pasteboard change count. Handy issue #502 reports a paste of the old clipboard under high CPU load (2.11). Check that a slow target app cannot read the pasteboard after the restore.

## Unresolved questions

1. Willow's free tier: the pricing page shows a "Word limit" with no number. Is it 2,000 words a week, or unlimited on a lighter model?
2. Are Willow, Aqua, Typeless, Superwhisper, Spokenly and Monologue native or Electron on the Mac? No primary source states it.
3. What are the defaults for Aqua Privacy Mode and Willow Context Awareness?
4. Does silence trimming (feature rank 2) lower kotoba's stop-to-paste time without clipping speech? It needs a bench pass on the owner's clips.
5. Does macOS 27 Dictation get the iOS 27 voice-edit commands, and how does SpeechAnalyzer on macOS 27 compare to MAI on technical terms? No source tested it.
6. What do Reddit users say in 2026? Reddit blocked automated access; a manual read is needed.
7. Did Typeless fix the plaintext database and audio-deletion findings from v0.9.3? No company response was found.
