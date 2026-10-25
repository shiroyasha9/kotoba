# Copywriting: kotoba's voice

Researched 2026-10-25. Read this before you write or change any user-facing text: the app, the README, the landing site (`kotoba-site`, `src/components/`) or release notes. `CODING_STANDARDS.md` "User-facing text" holds the mechanical rules (case, keys, punctuation, term list). This file holds the voice: what to say, and what to leave out.

## Why this file exists

The owner, 2026-10-25: the copy "explains kotoba as if it's something no one has ever seen before", the onboarding feature list "shouldn't sound like a changelog", and the copy should "make the user have more confidence in this app".

Earlier copy work aimed at "teaching copy" (`<runbooks>/2026-10-24-kotoba-ui-redesign/app-copy-research.md`, `copy-pass.md`; `docs/research/ux-polish.md` 4.1-4.6). Keep from it: plain words, Apple capitalisation, no internal terms, error structure, the term list, every fact check of the copy pass. Drop from it: explain-first, a subtitle on every row, hedges added for accuracy ("usually"), and mechanism told as a feature.

## Sources

Quotes below are verbatim. Competitor heroes were checked against the raw page HTML on 2026-10-25; the other quotes come from fetches by research agents, which checked them against raw text where marked "exact" in their notes.

| Short name | URL |
|---|---|
| Wispr Flow | https://wisprflow.ai, https://wisprflow.ai/privacy |
| Superwhisper | https://superwhisper.com, https://superwhisper.com/docs/get-started/quickstart |
| MacWhisper | https://macwhisper.com |
| Aqua Voice | https://aquavoice.com |
| VoiceInk | https://tryvoiceink.com, https://github.com/Beingpax/VoiceInk |
| Willow | https://willowvoice.com |
| Monologue | https://monologue.to |
| FreeFlow | https://github.com/zachlatta/freeflow |
| Hex | https://github.com/kitlangton/Hex |
| Handy | https://handy.computer |
| Voibe | https://www.getvoibe.com |
| Apple Dictation | https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac |
| Apple Privacy, Apple Intelligence | https://www.apple.com/privacy/, https://www.apple.com/apple-intelligence/ |
| Raycast, Raycast Dictation | https://www.raycast.com, https://manual.raycast.com/ai/dictation.md |
| Things, Linear, Dia, CleanShot, Craft, Bear, iA Writer, Tot | culturedcode.com/things, linear.app, diabrowser.com, cleanshot.com, craft.do, bear.app, ia.net/writer, tot.rocks |
| HIG Writing, Onboarding, Alerts | https://developer.apple.com/design/human-interface-guidelines/writing, …/onboarding, …/alerts |
| Mailchimp | https://styleguide.mailchimp.com/voice-and-tone/, https://styleguide.mailchimp.com/writing-principles/ |
| GOV.UK | https://guidance.publishing.service.gov.uk/writing-to-gov-uk-standards/writing-guidelines/right-tone/ |
| Polaris (archived) | https://github.com/Shopify/polaris-react-archive (`polaris.shopify.com/content/content/fundamentals.mdx`, `error-messages.mdx`) |
| Intuit | https://contentdesign.intuit.com/product-and-ui/actions/ |
| Copyhackers | https://copyhackers.com/2012/06/101-copywriting-dos-and-donts/ |
| Getting Real | https://basecamp.com/gettingreal/09.7-copywriting-is-interface-design |
| NN/g | https://www.nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web/, …/mobile-tutorials/, …/onboarding-tutorials/ |
| Strunk (1918) | https://www.gutenberg.org/files/37134/37134-h/37134-h.htm |
| Microsoft | https://learn.microsoft.com/en-us/style-guide/top-10-tips-style-voice, …/scannable-content/lists |

## What competitors do

| App | Hero (verbatim) | What works | What to avoid |
|---|---|---|---|
| Wispr Flow | "Don’t type, just speak." / "The voice-to-text AI that turns speech into clear, polished writing in every app." | Feature = 2-4 word heading + one benefit line: "Speak naturally" / "Ramble, pause, or change your mind mid-sentence." Privacy as ownership: "Your voice stays yours." "Your data is never sold." | Unsourced "4x faster than typing". |
| Superwhisper | "Just speak. Write faster." | The loop in 3 verbs: "Hold, speak, release." Permission reasons in one line each: "Accessibility: to insert your dictation into apps". | A grid of 20+ features buries the main loop. |
| Aqua Voice | "Talk into your apps." / "Aqua transcribes you perfectly and pastes the text where your cursor is." | The only site that names its benchmark: "97.4% key-term accuracy on AISpeak-10, our English technical-speech benchmark". | "perfectly"; 13 calls to action. |
| Willow | "Speak naturally, Willow writes it" | Three steps, two words each: "Click anywhere", "Hold and speak", "Perfect text appears". | "perfect text", "actually works", "as little as 200ms" (a best case dressed as a fact). |
| Monologue | "Builders think out loud." | Examples instead of adjectives: "Code in Cursor, full sentences in Gmail, casual in Slack. Monologue reads the room." | A hero that does not say what the app is. |
| VoiceInk | "Write at the speed of thought" | "Buy once. Own forever." says the business model in 4 words. | "near-perfect accuracy", "99% accuracy" with no source. |
| FreeFlow | "Free and open source alternative to Wispr Flow, Superwhisper, and Monologue." | Privacy as a fact about the system: "There is no FreeFlow server, so FreeFlow does not store or retain your data." | Nothing major. |
| Handy | "speak into any text field" | One-word pillars with one line: "Simple" / "One tool, one job." "Private" / "Your voice stays on your computer." | All lowercase reads as style, not clarity. |
| Apple Dictation | "Dictate messages and documents on Mac" | Dictation in one sentence: "With Dictation, you can speak to enter text anywhere you can type it." Exact numbers, no hedge: "Dictation stops automatically when no speech is detected for 30 seconds." | |
| Raycast Dictation | "Press, speak, and Raycast transcribes your words into clean, formatted text" | Closest model for kotoba. Privacy in one paragraph of flat negations: "Your voice is never used to train AI models, audio isn't retained on Raycast servers, and your transcriptions and statistics are stored locally on your device." Limits as plain numbers, lower down: "20 minutes". | |

Patterns across all of them:

1. **Nobody explains dictation.** Every hero assumes the reader knows the category. The whole loop gets one sentence (Aqua) or three verbs (Superwhisper, Willow, Voibe: "Hold. Speak. Release.").
2. **Heroes are 2-6 words**, an imperative or a promise. No hero names a model, an API or a mechanism.
3. **Features are a short heading and one line** about the result, often with real app names (Slack, Cursor, Gmail). No site lists behaviours or changes.
4. **Speed is a bare claim.** "4x", "5x", "instantly", with no hedge and mostly no source. kotoba can do better: a measured median, stated plainly, with the method one click away.
5. **Privacy is strongest as a fact about the system** ("There is no FreeFlow server") or a short set of negations. Adjectives ("complete privacy", "100% private") are weaker.
6. **Onboarding is verbs:** download, allow, pick a shortcut, dictate once. Each permission gets one "to …" line.
7. **Calls to action are 2-3 words:** "Download for free", "Download for Mac", "Try for free".

## What confident Mac apps do

- **Short promise heroes:** "Your shortcut to everything." (Raycast), "Your tiny text companion" (Tot), "More than a browser. A better workday." (Dia), "Truly helpful. Truly yours." (Apple).
- **Label, then one line of at most about 12 words.** CleanShot: "Capture History" / "Never redo a screenshot or recording." Raycast: "Fast. Think in milliseconds." "Reliable. 99.8% crash-free rate."
- **One proof number, not a table of them,** in the hero area: Raycast's 99.8%, Linear's "over 40,000 product teams". The rest sits one level down.
- **No hedges in headlines.** Apple's one qualifier, "many requests", is in body text, never in a heading.
- **What is left out, on purpose:** "No buttons, no popups, no title bar." / "iA Writer has fewer features, by design."
- **A competent reader.** Nobody explains a hotkey, the menu bar, Esc or "insertion point".
- **"You" everywhere, "we" almost never,** and then only for one human beat or one promise ("we can't see anything", Bear).

## Principles from the craft sources

1. **One voice, tone by moment.** "You have the same voice all the time, but your tone changes." (Mailchimp). Calm in errors, light in success.
2. **Make definite assertions.** "Avoid tame, colorless, hesitating, non-committal language." (Strunk). A claim that is not always true gets a different claim, not a hedge.
3. **Objective beats promotional.** Promotional text scored 27% lower in measured usability; concise, scannable and objective together scored 124% higher (NN/g). "Avoid dramatic storytelling and grandiose claims. Focus on our real strengths." (Mailchimp).
4. **Every word earns its place.** "Approach content like Jenga. What’s the most you can take away before things fall apart?" and "not every situation calls for subcopy, even if the component has been designed to include it" (Polaris). "Check each word to be sure it needs to be there." (HIG Writing).
5. **Benefit first.** "Every feature has a benefit (at least, it’d better!)" (Copyhackers). On a page a buyer reads, lead with the result; in Settings, the feature name can lead.
6. **Numbers as digits, specific.** "Prefer the specific to the general" (Strunk); "using 1, 3, 5 … not their written counterparts" (Copyhackers).
7. **Parallel lists.** "expressions of similar content and function should be outwardly similar" (Strunk). "each item should be a noun or a phrase that starts with a verb" (Microsoft).
8. **No internal lingo.** "Don’t sound like an engineer talking to another engineer. Keep it short and sweet. Say what you need to and no more." (Getting Real).
9. **Onboarding: do, do not tell.** "Tutorials interrupt users, don’t necessarily improve task performance, and are quickly forgotten." (NN/g). In NN/g's test, users who skipped the tutorial rated the tasks easier (5.49 against 4.92 on a 1-7 scale; a real difference, not chance). "design a flow that’s fast, fun, and optional" (HIG Onboarding).
10. **Experts want plain words too.** "the more educated the person and the more specialist their knowledge, the greater their preference for plain English" (GOV.UK). Short is not talking down.
11. **Buttons say what happens.** "just saying “Send” often works better than “Let’s do it!”" (HIG Writing). "In CTAs, the words do all the work." (Intuit).
12. **Settings describe the on state.** "Describe what it does when turned on, and people can infer the opposite." (HIG Writing).

## What goes wrong in kotoba's copy today

Read at `ui-polish` 4795c77 and `kotoba-site` b5c5612.

| Pattern | Example (file) |
|---|---|
| Hedges on the main claim | "Your words usually appear about a second after you stop." (`App/Onboarding/OnboardingSteps.swift:20`); "About one second later" (`README.md:12`) |
| A to-do where a benefit belongs | "Add names and terms to your dictionary, and kotoba spells them your way." (`OnboardingSteps.swift:23`) |
| Mechanism told as the pitch | "kotoba sends your audio to \(provider), which turns it into text. Get a key there and paste it here." (`OnboardingSteps.swift:214`) |
| Defensive detail up front | "No account. Audio goes only to the speech service you choose, with your key." (`OnboardingSteps.swift:26`); the Learn from edits paragraph on the permissions step (`:179`) |
| Explaining the Mac | "with an orange dot in the menu bar" (`:196`); "Open kotoba from the menu bar or the Dock to change your microphone or settings." (`:360`) |
| Edge cases as features (changelog tone) | "Your clipboard comes back once that app has read the paste. If you switch apps before the text arrives, kotoba copies it instead…" (`README.md` Features); "a short clip of silence or noise when you start wakes the service" (site `Privacy.astro`) |
| Adjective stacks | "It is fast, light, private, and free to download." (site `Hero.astro`) |
| Old names and verbs outside the app | "Tap" (README, site `Features.astro`), "Polish" (site `Features.astro`, `Privacy.astro`) |
| Two audiences | README: "built for developers who dictate prompts for coding agents". Site: "emails, messages, documents, notes and prompts". |

## kotoba's voice: 8 rules

The voice: a calm expert who has made the tool well and does not need to oversell it. Short, definite, specific.

1. **Lead with what the user gets.** Not the mechanism, not a to-do.
   - Do: "Learns your names and technical terms."
   - Don't: "Add names and terms to your dictionary, and kotoba spells them your way."
   - A condition the user must meet stays only when the claim is false without it.
2. **Make definite statements.** No "usually", "about", "typically", "just", "simply", "only" in a claim. When a claim is not always true, change the claim. A number in a heading is the measured median from `docs/benchmarks.md`; the p90 and the method live there, one link away.
   - Do: "Pastes your words a second after you stop."
   - Don't: "Your words usually appear about a second after you stop."
3. **Assume the reader knows dictation and the Mac.** Do not explain dictation, the menu bar, the Dock, the orange mic dot or System Settings.
   - Do: "To hear you while you dictate."
   - Don't: "Used only while you dictate, with an orange dot in the menu bar."
4. **Privacy is facts about the system.** Flat negations and one plain fact, no adjectives, no qualifiers.
   - Do: "Needs no kotoba account and sends no analytics." / "Your audio goes straight to OpenRouter, with your own key."
   - Say "no kotoba account": the user still makes an account at the speech service.
   - Don't: "No account. Audio goes only to the speech service you choose, with your key."
5. **One point per line, and a list shares one shape.** Same grammar and about the same length in every row of a list. A row may have no subtitle: add one only when the title is not enough.
   - Do: "Press to start. Press again to stop and paste." / "Hold while you speak. Let go to paste."
   - Don't: a list that mixes an adjective title with an instruction, a fact and a warning.
6. **Name the outcome, not the edge case.** Behaviours that protect the user (clipboard restore, wrong-app guard, retries) are felt, not sold. On a sales surface they become one outcome line; the details go to the docs. An edge case that changes what the user sees is said once, where it happens (the pill's "Copied. Press ⌘V to paste."), never hidden.
   - Do: "Pastes what you said, then puts your clipboard back." / "Offline? It finishes when you’re back."
   - Don't: "Your clipboard comes back once that app has read the paste."
7. **Calm and specific, never cute or hyped.** No "perfect", "magic", "seamless", "powerful", "oops". Use digits and a source. Errors keep `CODING_STANDARDS.md` rule 6: what happened, then what kotoba does next ("Will retry.") or what the user must do (a button).
   - Do: "84.6% of technical terms exactly right, against 50.0% for Wispr Flow."
   - Don't: "near-perfect accuracy" (VoiceInk), "perfect text" (Willow).
8. **Let the UI teach.** One heading line per screen at most; the controls, keycaps and buttons carry the rest. Contractions are fine ("it’s", "can’t"), as Apple writes.
   - Do: "Dictate in any app. kotoba stays in the menu bar."
   - Don't: "Open kotoba from the menu bar or the Dock to change your microphone or settings."

## Claims kotoba can make

Each line is safe as written; the source holds the fine print. Check the numbers in `docs/benchmarks.md` before each release.

| Topic | Headline wording | Fine print (where it lives) |
|---|---|---|
| Speed | "a second after you stop" | p50 987 ms, p90 2,047 ms, 11 dictations, 0.4.6 (`docs/benchmarks.md`). The site already gates the claim on a measured p50 at or under 1.0 s (`kotoba-site/src/data/facts.ts`, `fastClaim`). |
| Accuracy | "Gets your technical words right." / "84.6% of technical terms exactly right, against 50.0% for Wispr Flow" | 62 dictations, one developer (`docs/benchmarks.md`). Name the test next to a number. |
| Privacy | "No kotoba account. No analytics. No kotoba server." | A daily update check (site `Privacy.astro`). Do not write "nothing leaves your Mac" or "never stored": audio goes to the speech service, and xAI keeps it 30 days. |
| Price | "No subscription." | Never a per-hour number in the app: $0.10 per hour is a promotion until 2026-12-31 (`copy-pass.md` decision 2). README and site may show it with that note. |
| Size | "A native Mac app." / "15.9 MB at idle" | About 75 MB after a day (`docs/benchmarks.md`). |
| Openness | "Free and open source." | Apache-2.0. |

## Worked rewrites

Every "after" keeps `CODING_STANDARDS.md` rules 1-15. Code locations are at `ui-polish` 4795c77; Welcome moves to `App/Onboarding/WelcomeStep.swift` in the `qa2-welcome` work.

### Welcome (`OnboardingSteps.swift:14-38`)

| Slot | Now | After |
|---|---|---|
| Title | Welcome to kotoba | Welcome to kotoba |
| Subtitle | Speak in any app, and kotoba types your words where your cursor is. | Speak anywhere you can type. |
| Row 1 | Fast / Your words usually appear about a second after you stop. | Fast / Pastes your words a second after you stop. |
| Row 2 | Accurate / Add names and terms to your dictionary, and kotoba spells them your way. | Accurate / Learns your names and technical terms. |
| Row 3 | Private / No account. Audio goes only to the speech service you choose, with your key. | Private / Needs no kotoba account and sends no analytics. |
| Row 4, Wispr Flow installed (`WisprFlowPoint.swift:72-77`) | From Wispr Flow / Use the shortcuts you know from Wispr Flow. Wispr Flow uses these keys too. Quit it, or both apps start dictating. | From Wispr Flow / Imports your shortcuts and dictionary. Clash line, only while kotoba uses Wispr Flow's keys: "Quit Wispr Flow, or both apps will dictate." |
| Shortcut rows | Press to start. Press again to stop and paste. / Hold while you speak. Let go to paste. | No change: the best lines on the screen. |

Why: each row is a verb-first line of 4-8 words with kotoba as the unspoken subject (rule 5); the claims are the measured ones (rule 2); the subtitle uses Apple's own phrase for dictation instead of describing it (rule 3).

### Onboarding steps

| Step | Now | After |
|---|---|---|
| Allow Access, subtitle (`:174`) | kotoba needs the microphone to hear you, and Accessibility for your shortcut and to type your words. | kotoba needs both to work in every app. |
| Microphone row (`:196`) | Used only while you dictate, with an orange dot in the menu bar. | To hear you while you dictate. |
| Accessibility row (`:158`) | So your shortcut works in every app, and kotoba can paste. | For your shortcut and the paste, in any app. |
| Footer (`:179`) | To learn your corrections, kotoba reads only the text field it pasted into, and only while “Learn from edits” is on in Dictionary. It never reads your screen. | Move to the subtitle of “Learn from edits” on Dictionary, where the user turns it on. The step needs no footer. |
| Footer, Accessibility not yet allowed (`:184`) | If kotoba is on in the Accessibility list already and this step stays open, turn it off and on again. | Still waiting? Turn kotoba off and on again in the Accessibility list. |
| Key, title (`:212`) | Connect a Speech Service | Connect \(provider) |
| Key, subtitle (`:214`) | kotoba sends your audio to \(provider), which turns it into text. Get a key there and paste it here. | Your audio goes straight to \(provider), with your own key. |
| Key, other services row (`:222`) | xAI or Azure / Use another speech service, with your own key. | xAI or Azure / Use another speech service. |
| Try It, subtitle (`:283`) | Say “Hello from kotoba” with either way to dictate. | Say “Hello from kotoba.” |
| Done, title and subtitle (`:359-360`) | You’re Ready / Almost Ready; Open kotoba from the menu bar or the Dock to change your microphone or settings. | You’re Ready: "Dictate in any app. kotoba stays in the menu bar." Almost Ready: "One step left." (the problem row and its button follow). |
| Done, sound switch (`:323`) | Play sounds when a dictation starts and stops | Start and stop sounds |
| Done, Wispr Flow row (`:366-368`) | Add your words and replacements from Wispr Flow, so kotoba spells them right from the start. / Your dictionary already has every word from Wispr Flow. | Bring your words and replacements. / Every word is already in your dictionary. |

### Home empty state (`App/Home/HomePage.swift:54-61`)

- Now: "No Dictations Yet" / "Your last dictation appears here." / Try It…
- After: "No Dictations Yet" / "Dictate in any app, and your words show up here." / Try It…
- Why: Apple's Podcasts pattern (what goes here, how it gets here, one button). The shortcut rows above already show the keys.

### README first screen (`README.md:10-52`)

```
Dictation for Mac that gets your technical words right.
Press a shortcut, speak, press it again. Your words are in your app a second later.

Download for macOS · Free and open source · macOS 26 or later

A native, open-source alternative to Wispr Flow, made for people who dictate to coding
agents: file names, flags and identifiers, in terminals, editors and browsers.

## Why kotoba
- A second from stop to paste: median 987 ms in daily use.
- 84.6% of technical terms exactly right on 62 real dictations, against 50.0% for Wispr Flow.
- No kotoba account or server, and no analytics. Your audio goes to the speech service you choose, with your own key.
- No subscription: $0.10 per hour of audio, paid to OpenRouter.
- 15.9 MB at idle. A native Mac app, not a browser in a window.
```

Then the comparison table as now. In "Features", each bullet states one outcome; the clipboard, wrong-app and retry details move to a short "How it behaves" section near the end or to `docs/`. Fix "Tap" and "Double-tap" to "Press" (readme-0.5.0 proposal, same runbooks folder).

### Landing site (`kotoba-site/src/components/`)

| Place | Now | After |
|---|---|---|
| Hero h1 (`Hero.astro`) | Speak. Your words appear a second later. | No change: short, definite, gated on a measured median. |
| Hero sub | kotoba turns your voice into text in any app on your Mac: emails, messages, documents, notes and prompts. It is fast, light, private, and free to download. | Dictation for every app on your Mac, from Mail to your terminal. Native, open source and free. |
| Chips | No account · Open source · Native Mac app | No change. |
| Why, stat line (`Why.astro`) | Typical time from the moment you stop talking to your words on screen. | Median time from when you stop talking to your words on screen. |
| Features h2 (`Features.astro`) | Wherever you type, just talk. | Talk anywhere you type. (The old line echoes Wispr Flow's "Don’t type, just speak.") |
| Feature points | Tap to start and stop, or hold. Any key you like. / Polish makes it shorter and clearer, with 5 seconds to undo. | Press to start and stop, or hold. Any shortcut you like. / Rewrite makes it shorter and clearer, with 5 seconds to undo. |
| Feature points | Pastes what you said, and your clipboard comes back. | Pastes what you said, then puts your clipboard back. |
| Hero chips | No account | No kotoba account (the user signs up at the speech service) |
| Privacy detail (`Privacy.astro`) | With your own key. On OpenRouter, only endpoints that keep no data. Grok has none, and kotoba tells you. | With your own key. On OpenRouter, only servers that keep none of your audio. xAI keeps audio for 30 days, and kotoba says so. |
| Privacy detail | On the recommended route, a short clip of silence or noise when you start wakes the service. None of your audio, each billed as 1 second. | When you start, a short clip of silence wakes the service. It holds none of your audio and bills as 1 second. |
| Privacy "what" | The cleanup or Polish model | The cleanup or Rewrite model |
| Not-list h2 and intro (`NotList.astro`) | What kotoba does not do. / In 2026 other dictation apps added meeting recorders, rewrites and smaller word limits. kotoba left them out. | Left out, on purpose. / One job: your voice, typed. (The rows already say the rest; the intro need not talk about other apps.) |
| Not-list row | Rewrite your words by default | Rewrite your words unless you ask (Rewrite now exists, opt-in.) |
| Download (`Download.astro`) | It is free, notarized by Apple, and keeps itself up to date. | It’s free, notarized by Apple and keeps itself up to date. |

Keep as they are: "Exactly what leaves your Mac." (the strongest privacy heading of any app in this survey), "Say something.", "Light, private, and a fraction of the price.", "Names and terms, spelled right", "Your words, unless you ask", "Offline? It finishes when you are back."

## Changes `CODING_STANDARDS.md` "User-facing text" needs

Not edited here; the owner or lead decides.

1. **Reference line (line 74).** Point to this file for voice. Mark `ux-polish.md` 4.1-4.6 and `app-copy-research.md` as superseded where they ask to explain first or to fill every subtitle.
2. **New rule: definite claims.** No "usually", "typically", "just", "simply", or "about" before a number in a claim. A heading number is the median in `docs/benchmarks.md`. Lint candidate: `ui_text_hedges`, `\b(usually|typically|basically|simply|just)\b` and `\babout (a|an|one|\d)` on UI-builder lines (the menu's "About kotoba" does not match).
3. **New rule: outcome first.** A line says what the user gets; mechanism and edge cases go to an Advanced sheet, the README's later sections or `docs/`.
4. **New rule: assume Mac literacy.** Do not explain dictation, the menu bar, the Dock, the mic indicator or System Settings.
5. **New rule: parallel lists and optional subtitles.** Rows of one section share a grammatical shape; a subtitle appears only when the title is not enough (today every row gets one).
6. **Rule 9 (term list).** Add "speech service" (not "provider"), "key" (not "API key"), "shortcut" in UI ("chord" stays a code word).
7. **Rule 14 (voice).** Add: contractions are fine; no "perfect", "magic", "seamless", "powerful".
8. **Scope.** Rules 4, 9, 14 and 15 apply to the README and the site by review: today both still say "Tap", and the site says "Polish".

## Second opinion (Codex, gpt-6-astra high, 2026-10-25)

A blind review of the voice rules and the Welcome rewrite. Ledger:

| Finding | Verdict |
|---|---|
| "a second after you stop" turns a median into a promise; the p90 is about 2 s. "Removing uncertainty words does not remove uncertainty." | Kept the line, raised as question 1: the owner asked for confidence, and the site's `fastClaim` gate already makes this call. |
| "Spells names and technical terms your way" guarantees an outcome; dictionary entries are hints and the measured rate is 84.6%. | Accepted: now "Learns your names and technical terms." (the dictionary and learning from edits). |
| "Your clipboard stays as it was" is false when kotoba copies instead of pasting. | Accepted: now "Pastes what you said, then puts your clipboard back."; rule 6 says a visible edge case is said where it happens. |
| "Needs no account" hides the speech service's account. | Accepted: "no kotoba account" everywhere. |
| Rules 5, 7 and 8 clash with their own examples. | Accepted: "one point per line", "one heading line per screen", errors say what kotoba does next or what the user must do. |
| "Brings your shortcuts and dictionary along" suggests an automatic move. | Accepted: "Imports your shortcuts and dictionary." (both are one button). |
| Its own rows: "Your Dictionary", "Your Key", "No Account". | Rejected: they lead with mechanism (a key, a dictionary), the tone the owner asked to drop. |

## Unresolved questions

1. Speed claim: is the median enough to drop "about" and "usually" from "a second after you stop"? The p90 is 2,047 ms. This file says yes, with the p90 on the benchmarks page, as the site's `fastClaim` gate already does. Codex disagrees (see above).
2. Audience: the README speaks to developers who dictate to coding agents; the site speaks to everyone. Which one leads, on both?
3. Welcome titles: keep the adjectives (Fast, Accurate, Private), or use claim titles such as "A second to paste"?
4. May the Learn from edits privacy line leave onboarding for the Dictionary page?
5. Should the new rules (2-5 above) get lint, or stay review-only?
