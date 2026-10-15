# UX polish plan

Date: 2026-10-15, 23:22 IST. Author: ux agent (read-only audit). Owner's ask: "tidy up the UI/UX around the product. Make it polished and refined. Suitable for any user to use it."

Inputs: the code at this date, `make snapshots AGENT=ux` (70 PNGs in `build/snapshots-ux/`, light and dark, all read), `docs/spec.md` stories 1-44, `docs/testing/phase2-manual.md`, `docs/research/memory-spike.md`. References: Wispr Flow (installed app's Info.plist, its help center and a public UX reference), Hex (README), Apple HIG (menu bar extras, writing, settings). Superwhisper, MacWhisper, FreeFlow and VoiceInk were not opened in this session; the few points about them come from general product knowledge and are marked so.

Priority: **P0** = a new user gets stuck. **P1** = looks unfinished or uses words a normal user does not know. **P2** = nice to have.

Owners: **scaffold** (pipeline, AppDelegate, menu, StatusText, MicrophonePane), **providers** (KotobaProviders, ProvidersPane), **dictionary** (KotobaStorage, Settings shell, DictionaryPane), **indicator** (IndicatorPanel, IndicatorPillView, Snapshots).

## 1. What a brand-new user sees today

1. They open kotoba.app. No window opens. A `waveform` symbol appears in the menu bar (`App/AppDelegate.swift:212-219`).
2. At the same moment, two system prompts appear with no kotoba text before them: the Microphone prompt (`App/AppDelegate.swift:185-196`, from the launch `Task` at line 66) and the Accessibility prompt (`App/AppDelegate.swift:169-171`). The Accessibility prompt sends the user to System Settings. kotoba checks again every 5 s.
3. If they open the menu, the first line is "Waiting for Accessibility permission" (disabled), or "Ready - tap Ctrl+Opt+Cmd" when Accessibility is on. The menu says "Ready" also when there is no API key and when the microphone is denied (`App/StatusText.swift:33`, `App/AppDelegate.swift:224-225`).
4. Nothing says what OpenRouter is, that a key is necessary, where to get one, or what it costs. The only path is the menu item "Set API Key…".
5. If they tap the chord with no key, kotoba records, then the pill shows "Set your OpenRouter key" for 4 s and hides (`App/IndicatorPanel.swift:94-97`, `:66-68`). The pill has no button. The audio is kept and is sent when a key is saved (good).
6. If they denied the microphone, every dictation shows "Microphone unavailable" for 4 s. Nothing tells them how to turn it on. The denial is only logged (`App/AppDelegate.swift:191-193`).
7. If Accessibility is off, the text goes to the clipboard and the pill says "Copied - press Cmd-V". Nothing tells them why or how to fix it.
8. There is no launch at login (no `SMAppService` in the code), no About item, no version, and no app icon (no asset catalog in `App/` or `project.yml`). System Settings > Accessibility and the TCC prompts show a generic icon next to "kotoba".

Result: a developer who reads the README can set kotoba up. A normal user gets stuck at steps 2, 4 and 6.

## 2. Permissions kotoba really uses

| Permission | Used for | Code | Needed? |
|---|---|---|---|
| Microphone | Recording | `App/AudioCapture.swift`, `App/AppDelegate.swift:185-196`; `NSMicrophoneUsageDescription` in `project.yml` | Yes |
| Accessibility | The active event tap (it swallows Esc while recording) and the synthetic Cmd-V | `App/HotkeyTap.swift:9-10` (`.defaultTap` at line 55), `App/Paste.swift:84,118` | Yes |
| Input Monitoring | A listen-only event tap | Not used: the tap is `.defaultTap`, which Accessibility covers (Apple Developer Forums threads 122492 and 828052: default tap -> Accessibility prompt, listen-only tap -> Input Monitoring prompt) | No |
| Screen Recording | Window titles | Not used: `CGWindowListCopyWindowInfo` reads bounds only (`App/IndicatorPanel.swift:198`) | No |

Spec story 37 names Input Monitoring. Change it to Microphone and Accessibility only, after the owner confirms on a clean macOS user account that no Input Monitoring prompt appears (forum reports differ between macOS versions).

## 3. First-run onboarding design (stories 36 and 37)

A small "Welcome to kotoba" window (SwiftUI, on demand, like Settings). It opens on the first launch and again from the menu while setup is not complete. It is one window with a list of steps on the left and one step on the right, like System Settings' setup flows. Each step shows its state (a green checkmark when done) and is live: kotoba checks the state again when the window becomes key and every 1 s while the window shows, so a grant in System Settings turns the step green without a click.

Launch behaviour change: on first launch, kotoba does not call `requestRecordPermission` or `AXIsProcessTrustedWithOptions(prompt: true)` at launch. The onboarding buttons do. After setup is complete, launch keeps today's silent checks with no prompt.

### Step 1 - Welcome

- Title: "Talk Instead of Type"
- Body: "Tap ⌃⌥⌘ (Control-Option-Command), speak, and tap again. kotoba types what you said where your cursor is, in about a second."
- Privacy line: "No account. Your audio goes only to the speech service you choose, with your own key."
- Button: "Get Started"

### Step 2 - Microphone

- Title: "Allow the Microphone"
- Body: "kotoba listens only while you dictate. The orange dot in the menu bar shows when the mic is on."
- Button: "Allow Microphone" -> `AVAudioApplication.requestRecordPermission()`.
- Denied state: "Microphone access is off." Button: "Open System Settings" -> `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`.
- Done state: "Microphone allowed" with a checkmark.

### Step 3 - Accessibility

- Title: "Allow Accessibility"
- Body: "kotoba needs Accessibility to notice ⌃⌥⌘ in every app and to paste your text. kotoba does not read your screen or your typing."
- Button: "Open Accessibility Settings" -> `AXIsProcessTrustedWithOptions` with the prompt, then the 1 s check above.
- Help line under the button: "Turn on kotoba in the list. If it is on already and this step stays open, turn it off and on again."
- Done state: "Accessibility allowed".

### Step 4 - Speech service key

- Title: "Connect a Speech Service"
- Body: "kotoba sends your audio to OpenRouter, which turns it into text. You pay OpenRouter directly, a few cents per hour of speech."
- Button: "Get a Key at OpenRouter…" -> opens `https://openrouter.ai/settings/keys` (sign-in page, checked 2026-10-15).
- Field: secure field with the prompt "Paste your OpenRouter key", and "Save".
- After save: one free check of the key (OpenRouter's key-info endpoint; confirm the path in OpenRouter's API docs before code). Results: "Key works" / "OpenRouter did not accept this key" / "This key has no credit. Add credit at OpenRouter." / "Could not reach OpenRouter. The key is saved; kotoba checks it at your first dictation."
- Small link: "Use xAI or Azure instead…" -> opens Settings on the speech pane.

### Step 5 - Try it

- Title: "Try It"
- A key-cap row "⌃ ⌥ ⌘". Each cap lights while its key is down (from `HotkeyTap` events), so the user sees that kotoba hears the chord.
- A text field with focus: "Tap ⌃⌥⌘, say "Hello from kotoba", then tap ⌃⌥⌘ again." Hint: "Or hold ⌃⌥⌘ while you speak, and let go."
- When text arrives in the field: "It works." with a checkmark. When a pill error comes, show the same text under the field with its fix button.

### Step 6 - Done

- Toggle: "Open kotoba when you log in" (on by default; see Unresolved questions). Uses `SMAppService.mainApp.register()`. If the status is `.requiresApproval`: "Allow kotoba in System Settings > General > Login Items." with a button.
- Toggle: "Play a sound when recording starts and stops".
- Body: "kotoba lives in the menu bar. Click the waveform icon to change your microphone or open Settings."
- Button: "Done"

### Cost

- SwiftUI window: Settings measured +19-21 MB that stays after close (`docs/research/memory-spike.md`, "Settings window"). The SwiftUI runtime loads once per process, and a first-run user opens Settings almost always, so the expected extra over Settings is small (estimate under 2 MB; measure with `make memory` after an owner go). The idle gate is measured from a launch with no window opened, so a later launch is not affected.
- `ServiceManagement`: touched only in the Done step and the General pane, never at launch. Expected cost under 0.5 MB; measure.
- No hot-path work. The key check is one request at save time, off the dictation path.

## 4. Findings and changes per surface

### 4.1 Menu bar menu (`App/AppDelegate.swift:211-360`, `App/StatusText.swift`, `App/MenuChoices.swift`)

Today (idle, Grok route):

```
Ready - tap Ctrl+Opt+Cmd
Retry Failed Dictations (0)          (always present, dimmed at 0)
Recovered (N) ▸                      (when any)
---
Microphone: MacBook Pro Microphone ▸
Model: Grok STT (OpenRouter) ▸       (subtitle "No zero-data-retention route")
  Format Numbers (format)
  Keep Filler Words
Cleanup Chord: Ctrl+Opt+Cmd+Shift ▸
---
Set API Key…
Settings…                ⌘,
Sound Cues
Indicator Position ▸
---
Quit kotoba              ⌘Q
```

Proposed (ready):

```
Tap ⌃⌥⌘ to dictate                   (disabled status line)
Retry 2 Saved Dictations             (only when count > 0)
Recovered Dictations ▸               (only when any; each item subtitle "Click to copy")
---
Microphone ▸                         (subtitle: the mic in use)
Speech Model ▸                       (subtitle: the model; Grok options inside the submenu)
---
Settings…                ⌘,
About kotoba
---
Quit kotoba              ⌘Q
```

Proposed (setup not complete): the status line becomes an enabled item "Finish Setting Up kotoba…" with a subtitle that names the first missing thing ("Allow the microphone", "Allow Accessibility", "Add your OpenRouter key", "Add your Azure endpoint"). It opens the onboarding window on that step.

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| M1 | P0 | scaffold | The status line says "Ready" when the key, the mic or Accessibility is missing (`App/StatusText.swift:33`). | Compute readiness from `AXIsProcessTrusted()`, `AVAudioApplication.shared.recordPermission` and `routeSettings.missingSetup`. Not ready -> "Finish Setting Up kotoba…" as above. |
| M2 | P0 | scaffold | "Waiting for Accessibility permission" is a disabled line; it gives no way to act. | Covered by M1: an enabled item that opens the step. |
| M3 | P1 | scaffold | "Set API Key…" sits next to "Settings…" and stays when a key is saved. | Remove it. M1 covers a missing key; Settings covers a change. |
| M4 | P1 | scaffold | "Retry Failed Dictations (0)" shows dimmed when nothing failed. | Show only when the count is above 0: "Retry 1 Saved Dictation" / "Retry 2 Saved Dictations" (inflect, as `DictionaryPane.counted` does). |
| M5 | P1 | scaffold | "Recovered (N)" does not say what the items are or what a click does. | "Recovered Dictations" with each item's subtitle "Click to copy". |
| M6 | P1 | scaffold | "Model: Grok STT (OpenRouter)" and "Microphone: …" put the value in the title. | Title "Speech Model" / "Microphone", value in `subtitle` (the code already sets subtitles in `MenuChoices.swift:28,32`). |
| M7 | P1 | scaffold + providers | "Format Numbers (format)" shows an API parameter name. "No zero-data-retention route" and "Untested live" are internal notes. | "Format Numbers and Units" and "Keep Filler Words", inside the Speech Model submenu under a separator. Notes: Grok via OpenRouter -> "Provider may keep audio"; direct routes -> no note in the menu (see S3). |
| M8 | P1 | scaffold | Cleanup Chord, Sound Cues and Indicator Position are settings that live only in the menu. A user who opens Settings does not find them. | Move them to a new General pane (G1). See Unresolved questions 1. |
| M9 | P1 | scaffold | No About item, no version. | "About kotoba" -> `NSApp.orderFrontStandardAboutPanel` (version from the bundle). Needs `NSApp.activate()` first. |
| M10 | P1 | scaffold | The menu bar icon never changes. The user cannot see "not set up" or "recording" without opening the menu. | Idle: `waveform`. Setup not complete or a failed dictation waiting: `waveform.badge.exclamationmark`. Recording: `waveform` with a variable-color symbol effect, or a filled variant. Keep it a template image (HIG: understated, no flashing). |
| M11 | P2 | scaffold | Chords are written "Ctrl+Opt+Cmd" (`App/StatusText.swift:33`, `App/CleanupChord.swift:26-32`). macOS menus write modifier symbols. | Use "⌃⌥⌘", "⌃⌥⌘⇧" and "⌃⌥⌘fn" in menus, pills and Settings. Prose in onboarding spells them once: "⌃⌥⌘ (Control-Option-Command)". |
| M12 | P2 | scaffold | No help entry. | "kotoba Help" -> the GitHub README (opens a browser; no runtime cost). |

### 4.2 Indicator pill (`App/IndicatorPanel.swift:76-99`, `App/IndicatorPillView.swift`, `App/StatusText.swift:8-19`)

Snapshots look clean: good padding, dot colors clear in both modes, the vertical pill at the edges is tidy. The issues are the words and the missing actions.

Copy deck (the pill and the menu status line read from the same map, as today):

| State | Today | New | Button on the pill |
|---|---|---|---|
| recording | Listening (menu: "Recording") | Listening (menu too) | - |
| recording, long | Listening - over 10 min | Still listening · 10 min | - |
| recording, secure input | Listening - secure input on | Listening · Secure Input on | - (tooltip: "Another app turned on Secure Input. kotoba still records.") |
| transcribing | Transcribing | Transcribing | - |
| undoable | Cancelled (menu: "Cancelled - Undo available") | Cancelled | Undo |
| failed (offline, server, rate limit) | Failed - retry from the menu | Couldn't reach OpenRouter. Saved. | Retry |
| needsSetup .key | Set your OpenRouter key | Add your OpenRouter key | Add Key… |
| needsSetup .endpoint | Set the Azure endpoint in Settings | Add your Azure endpoint | Settings… |
| rejected, no credit (402) | Refused - check the key or credits | OpenRouter is out of credit | Add Credit… (opens the provider's credits page) |
| rejected, other 4xx | Refused - check the key or credits | OpenRouter refused the audio. Saved. | - |
| rejected, empty transcript | Refused - check the key or credits | No speech heard | - |
| cleanupFailed | Cleanup failed - pasted the raw text | Pasted without cleanup | - |
| recovered | Recovered - see the menu | Saved dictation recovered | Copy |
| copied (no Accessibility) | Copied - press Cmd-V | Copied. Press ⌘V to paste. | Allow Pasting… (opens the Accessibility step) |
| copied (paste refused for another cause) | Copied - press Cmd-V | Copied. Press ⌘V to paste. | - |
| captureFailed, mic denied | Microphone unavailable | Microphone access is off | Open Settings… |
| captureFailed, no input | Microphone unavailable | No microphone found | - |

The provider name in each row is the current route's provider, as today.

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| I1 | P0 | indicator + scaffold | Error pills have no action and hide after 4 s (`App/IndicatorPanel.swift:66-68`). A user who looks away misses them. | Add one action button next to the text, built like the Undo button (`FirstClickButton`, `App/IndicatorPillView.swift:244-261`). The content gets `action: (title: String, id: PillAction)?`; AppDelegate maps `PillAction` to the handler. Pills with a button hide after 8 s; hover pauses the timer. |
| I2 | P0 | scaffold | "Microphone unavailable" has one text for "denied" and "no device". | `captureFailed` stays one core state; the App picks the text from `AVAudioApplication.shared.recordPermission` at render time. No KotobaCore change. |
| I3 | P1 | scaffold (+ providers for the reason) | "Refused - check the key or credits" shows for an empty transcript too (progress.md follow-up 0a), and for any 4xx. | Carry the reason to the state: `rejected(DictationID, RejectReason)` with `.noCredit`, `.emptyTranscript`, `.other`. 402 maps to `.noCredit` in the providers. |
| I4 | P1 | scaffold | The menu says "Recording" and the pill says "Listening" for the same state (`App/StatusText.swift:34` vs `App/IndicatorPanel.swift:83`). | One word: "Listening". |
| I5 | P1 | indicator | Snapshots cover 8 of 13 states. `rejected`, `cleanupFailed`, `copied`, `recovered` and `captureFailed` have no PNG, so their text width is never checked. | Build the row list from an exhaustive `switch` over `DictationState` so a new case fails to compile until it has a row. |
| I6 | P1 | indicator | Undo in the dark Cancelled pill renders black on dark offscreen (manual test row 54 already lists it). | Check on screen. If real, set the button's `contentTintColor` to `.labelColor`. |
| I7 | P2 | indicator | Long texts truncate silently at 360 pt. | In the snapshot run, fail when the label's fitting width is above the pill's text width (same idea as `windowSnapshot`). |
| I8 | P2 | scaffold | Recording in a password field is described as "secure input", an internal macOS term. | See the copy deck; a tooltip explains it. |

### 4.3 Settings window (`App/Settings/SettingsWindow.swift`, `App/SettingsController.swift`)

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| W1 | P1 | dictionary (shell) + scaffold (content) | No General pane. Launch at login, the shortcut, the cleanup chord, sound cues and indicator position have no home in Settings. | Add a General pane, first in the sidebar (G1). |
| W2 | P1 | dictionary | Pane order is Dictionary, Microphone, Providers. The pane a new user needs (the key) is last. | Order: General, Speech, Dictionary, Microphone. |
| W3 | P1 | providers + dictionary | "Providers" uses the `waveform` symbol, the same as the menu bar icon. "Providers" is a developer word. | Rename to "Speech" with symbol `text.bubble` (or `key` if the pane stays key-centric). |
| W4 | P2 | dictionary | Window title "kotoba Settings" while the toolbar shows the pane title. | Window title = pane title, as System Settings does (the `navigationTitle` already sets it; drop the fixed title or confirm on screen). |
| W5 | P2 | dictionary | The selected sidebar row renders as a black block offscreen. Known offscreen limit, not a bug. | No change; keep the note in `SettingsWindow.swift:106-110`. |

#### G1 - General pane (new; owner scaffold, registered by dictionary)

```
Shortcut
  Dictate            ⌃⌥⌘     "Tap to start and stop, or hold while you speak."
  Clean up           [⌃⌥⌘⇧ ▾]   (⌃⌥⌘⇧ / ⌃⌥⌘fn / Off)
                     "Removes filler words and fixes punctuation. Takes a moment longer."
  Cleanup model      [Gemini 3.5 Flash-Lite ▾]   (moved from Providers)
Startup
  Open kotoba when you log in        [toggle]
Feedback
  Play sounds                        [toggle]
  Indicator position                 [Bottom Center ▾]
```

### 4.4 Providers pane -> "Speech" (`App/Settings/ProvidersPane.swift`)

The snapshot shows a full grouped form: the route picker, both Grok toggles, three key rows, the Azure endpoint and the cleanup model, all at once, whatever the route.

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| S1 | P0 | providers | No help to get a key; no hint of cost. | Under the key row of the current provider: a "Get a Key…" link button (OpenRouter `https://openrouter.ai/settings/keys`; xAI console; Azure portal) and the line "You pay OpenRouter directly, a few cents per hour of speech." |
| S2 | P1 | providers | "Route" is jargon; titles like "MAI-Transcribe-2 (Azure direct)" mean nothing to a normal user. | Label "Speech model". Items: "MAI-Transcribe-2 via OpenRouter (Recommended)", "Grok via OpenRouter", and under an "Advanced" section: "Grok via xAI", "MAI-Transcribe-2 via Azure". Keep the raw values. |
| S3 | P1 | providers | Notes "No zero-data-retention route" and "Untested live" are internal. | Grok via OpenRouter -> footer "OpenRouter may keep this audio. MAI-Transcribe-2 keeps none." Remove "Untested live" from the UI; if the direct routes stay untested, keep them under Advanced (Unresolved questions 2). |
| S4 | P1 | providers | All three key rows and the Azure section show for every route. | Show the key row of the selected route's provider, and the Azure endpoint only for the Azure route. Other saved keys go in a collapsed "Other keys" section. |
| S5 | P1 | providers | After save the field shows only the dim prompt "Saved". There is no proof the key works. | Saved state: a green checkmark and "Saved". Run the key check of onboarding step 4 on save, and show its result line under the row. |
| S6 | P1 | providers | Azure footer "A Speech resource in Central India had the lowest latency from India." is owner-specific. | "Use a Speech resource in the region nearest to you." |
| S7 | P1 | providers | The Cleanup model sits here, but the cleanup chord is in the menu. | Move to G1 next to the chord. |
| S8 | P2 | providers | The Keychain error shows the raw error: "The Keychain refused the change (…)". | "Could not save the key in your keychain. Try again." Log the raw error. |
| S9 | P2 | providers | Endpoint example renders as bright as typed text offscreen (manual test row 74). | Check on screen; no change if it is an offscreen limit. |

### 4.5 Dictionary pane (`App/Settings/DictionaryPane.swift`)

Good: the empty state ("No Words Yet" with a clear description), the import banner, the inline long-term warning, plurals. Issues:

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| D1 | P1 | dictionary | Footer "6 words, 2 replacements. Keyterms sent: 6 of 100." - "keyterms" is jargon. | "6 words, 2 replacements. The speech model gets up to 100 words as hints." When the cap is hit: "Only the first 100 words are sent as hints." |
| D2 | P1 | dictionary | The editor sheet has no title, so "Add" and "Edit" look the same. | Title "Add Word" / "Edit Word" at the top of the form. |
| D3 | P1 | dictionary | The row "um -> (removed)" is unclear. | "um -> (deleted from text)". |
| D4 | P2 | dictionary | "Wispr Flow Not Found" shows a Library path. | Body: "Wispr Flow is not on this Mac, or it has no dictionary yet." Show the import button only when Wispr Flow's folder exists (a file-exists check when the pane opens). |
| D5 | P2 | dictionary | The empty state does not say what a replacement is. | Description: "Add names and terms the speech model should know, or fix a word it always gets wrong. You can also import from Wispr Flow." |

### 4.6 Microphone pane (`App/Settings/MicrophonePane.swift`)

Clean layout. "Not connected" and the Bluetooth note read well.

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| MP1 | P1 | scaffold | The footer text wraps to two lines next to the button. | Put the help text as the list's footer, and the button alone at the bottom right. Text: "kotoba uses the first connected mic in this list. Drag to change the order." |
| MP2 | P2 | scaffold | No way to check the mic before a dictation (Wispr Flow has a mic test with a level meter and a device picker). | A "Test" button that starts the engine for 5 s and shows a level bar next to the mic in use. The orange mic dot shows during the test, which is expected after a click. |
| MP3 | P2 | scaffold | "Bluetooth - lower quality". | "Bluetooth: lower quality while recording". |

### 4.7 App identity

| # | P | Owner | Finding | Change |
|---|---|---|---|---|
| A1 | P1 | scaffold (`project.yml`) | No app icon. TCC prompts, the Accessibility list, the About panel and Login Items show a generic icon. A user who looks for "kotoba" in the Accessibility list has no picture to find. | Add `App/Assets.xcassets` with an AppIcon (macOS 26 style). Design is the owner's taste (Unresolved questions 4). No runtime cost until shown. |
| A2 | P2 | scaffold | The menu bar glyph is the stock `waveform` symbol. | A custom template glyph later; keep the SF symbol until the icon exists so both match. |

### 4.8 Follow-ups found during the audit (not UX copy; report only)

- Spec story 22 says queued failed dictations are retried when the network returns. No network monitor exists: retries run only at launch, on a setup change and from the menu (`KotobaCore/Sources/KotobaCore/DictationPipeline.swift:91-106`, `App/AppDelegate.swift:69,104,111,329-335`). The new "Couldn't reach OpenRouter. Saved." text assumes kotoba retries alone; until then it must add "Retry from the menu". Owner: scaffold.
- An accidental double tap (empty recording) shows an error and queues a retry (manual test rows 93-94). A normal user reads this as a fault. Proposal: below a minimum length (Wispr Flow discards under about 0.5 s), discard silently like the shortcut-press case. Owner: scaffold (pipeline decision, test-first).

## 5. Copy and UX style guide

Proposed home: a new "User-facing text" section in `CODING_STANDARDS.md` (agents already read it before code). The copy deck in this file stays the reference for current texts.

1. **Brand.** Always "kotoba", lowercase, also at the start of a sentence.
2. **Capitalisation (Apple HIG).** Title case: menu items, buttons, window and pane titles, section headers, submenu titles. Sentence case: toggle and field labels, footers, help text, pill messages, status lines.
3. **Ellipsis.** "…" (one character) on a menu item or button that opens a window or needs more input before it acts ("Settings…", "Add Key…"). Never on an item that acts at once. Never "...".
4. **Keys.** Modifier symbols in UI: ⌃ ⌥ ⌘ ⇧ fn, ⌘V. Spell the names once in onboarding prose.
5. **Plain words.** No internal terms in UI text: route, keyterm, ZDR, zero-data-retention, endpoint (except the Azure field label, where the Azure portal uses it), needsSetup, provider slugs, API parameter names, "untested", owner-specific measurements, file paths (except where the user must act on a path).
6. **Errors say what happened and what to do next.** Name the service that failed ("Couldn't reach OpenRouter"). Say that the audio is saved when it is. Give the fix as a button on the pill or the row, not as an instruction to look elsewhere. Never blame the user.
7. **Short.** A pill message fits in 34 characters (the 360 pt pill). Menu status lines use the same text as the pill.
8. **Separators.** No " - " between two phrases. Use two short sentences, a colon, or "·" for a value after a state ("Still listening · 10 min").
9. **One word per concept.** Listening (not Recording) for the live state; dictation; speech model; key; dictionary word; replacement.
10. **Counts.** Inflected plurals through `AttributedString(localized: "^[…](inflect: true)")`, as `DictionaryPane.counted` does. Hide an item with a count of 0 instead of showing "(0)".
11. **Colors.** Status colors come from system colors (`.systemRed`, `.systemOrange`, `.systemGreen`, `.secondaryLabelColor`) and SwiftUI semantic styles; no literal RGB.
12. **Every new window and every new state gets a snapshot** (both appearances), and every text field gets a manual Cmd-V/Cmd-A row (already a rule).

What a tool can enforce:

| Rule | How | Where |
|---|---|---|
| 3 (no "...") and 8 (no " - ") in UI strings | SwiftLint custom rules with `match_kinds: [string]`, scoped to `App/`, matched only on lines that build UI (`Text(`, `Button(`, `Toggle(`, `Section(`, `Label(`, `Picker(`, `NSMenuItem(title:`, `.action(`, `.toggle(`, `.choices(`) so log strings do not trip them | `.swiftlint.yml` |
| 5 (internal terms) | Same mechanism, a word list: keyterm, ZDR, zero-data, route, needsSetup, Untested | `.swiftlint.yml` |
| 9 and 7 (one map, short text) | Keep every pill and menu status string in `App/StatusText.swift`; the snapshot run fails when a pill label is truncated (I7) | `App/StatusText.swift`, `App/IndicatorPillView.swift` |
| 12 (every state rendered) | Indicator rows from an exhaustive `switch` over `DictationState` (I5); register every window (onboarding steps, each Settings pane) | `App/Snapshots.swift` |
| Menu text review | The snapshot run writes `menu-<state>.txt` (the item titles and subtitles of the menu for idle-ready, idle-not-set-up, recording, failed) so an agent reads the menu without a screen | `App/Snapshots.swift` + a menu builder that takes its inputs as values |

The menu dump needs `menuNeedsUpdate` split into a pure builder (`MenuModel` in, `NSMenu` out). That is a small refactor in `App/AppDelegate.swift` (scaffold).

## 6. All items by priority

| ID | P | Owner | Item |
|---|---|---|---|
| O1 | P0 | new window (suggest scaffold) | Onboarding window, steps 1-6 (section 3) |
| O2 | P0 | scaffold | No permission prompts at first launch; onboarding asks |
| M1 | P0 | scaffold | Readiness-aware status line, "Finish Setting Up kotoba…" |
| M2 | P0 | scaffold | Accessibility wait becomes an action (with M1) |
| I1 | P0 | indicator + scaffold | Action button on error pills, 8 s hide, hover pauses |
| I2 | P0 | scaffold | Mic denied vs no mic, with Open Settings… |
| S1 | P0 | providers | "Get a Key…" link and cost line |
| O3 | P1 | scaffold | Launch at login (`SMAppService`), onboarding step 6 and General pane |
| M3-M10 | P1 | scaffold (M7 with providers) | Menu restructure and copy (8 items) |
| I3 | P1 | scaffold + providers | Rejected reason (no credit, empty, other) |
| I4 | P1 | scaffold | "Listening" in menu and pill |
| I5 | P1 | indicator | Snapshot every DictationState |
| I6 | P1 | indicator | Undo contrast in dark (check on screen) |
| W1 / G1 | P1 | dictionary + scaffold | General pane |
| W2 | P1 | dictionary | Pane order |
| W3 | P1 | providers + dictionary | Rename Providers to Speech, new symbol |
| S2-S7 | P1 | providers | Speech pane restructure and copy (6 items) |
| D1-D3 | P1 | dictionary | Dictionary copy (3 items) |
| MP1 | P1 | scaffold | Microphone pane footer layout and copy |
| A1 | P1 | scaffold | App icon |
| SG | P1 | lead | Style guide section in `CODING_STANDARDS.md` + lint rules |
| M11, M12 | P2 | scaffold | Key symbols, Help item |
| I7, I8 | P2 | indicator, scaffold | Truncation check, secure input wording |
| W4, W5 | P2 | dictionary | Window title; offscreen sidebar note |
| S8, S9 | P2 | providers | Keychain error text; endpoint prompt check |
| D4, D5 | P2 | dictionary | Wispr not-found text and button; empty-state text |
| MP2, MP3 | P2 | scaffold | Mic test; Bluetooth note |
| A2 | P2 | scaffold | Custom menu bar glyph |
| Menu dump | P2 | scaffold + indicator | Menu text snapshots |

Counts: P0 7, P1 28 (M3-M10 count as 8, S2-S7 as 6, D1-D3 as 3), P2 14. Total 49.

## 7. Memory and latency cost of each proposal that adds a window, framework or launch work

| Proposal | Memory | Latency | Notes |
|---|---|---|---|
| Onboarding window (O1) | SwiftUI runtime: +19-21 MB that stays after close (Settings measurement). Extra over Settings: estimate under 2 MB. First run only | None on the hot path | Idle gate unaffected (measured from a launch with no window opened). Measure with `make memory` after an owner go |
| Launch at login (O3) | ServiceManagement, loaded on first use only; estimate under 0.5 MB | None | Never touched at launch |
| General pane (G1) | Inside the existing Settings window; no new framework | None | - |
| Readiness check in the menu (M1) | None | 1-5 ms per menu open (Keychain read in `hasKey`), not on the dictation path | Or cache `hasKey` in `KeyVault`, updated by `saves` |
| Menu bar icon state (M10) | A few cached `NSImage` symbols, under 0.1 MB | About 0.1 ms on the main actor per state change; `render` plays the start cue before any icon work today, keep that order | Add a signpost if in doubt |
| Pill action button (I1) | One more `NSButton` in a panel built on first show; under 0.1 MB | None (built with the pill) | - |
| Key check on save (S5, step 4) | None | One HTTP request at save time on the provider's existing `URLSession` | Free endpoint; no money |
| Mic test (MP2) | None | Starts the engine only on click | Orange dot shows during the test |
| App icon (A1) | None at idle | None | Loaded only when shown |
| Snapshot and lint additions | None (build time only) | None | - |

## Unresolved questions

1. **Menu scope.** Move Cleanup Chord, Sound Cues and Indicator Position from the menu to Settings > General? Recommendation: yes, all three; the menu keeps the status, Microphone and Speech Model. The owner uses the menu often, so this is a taste call.
2. **Direct routes.** Hide "Grok via xAI" and "MAI-Transcribe-2 via Azure" under "Advanced" until they are tested live, or remove them from the UI for the first public release? Recommendation: keep them under Advanced, no "Untested" label.
3. **Launch at login default.** On or off in onboarding step 6? Recommendation: on, as a visible toggle the user can turn off (story 36: "dictation is always available").
4. **App icon.** Who designs it and in what style? Recommendation: a simple macOS 26 icon that matches the waveform glyph; the owner picks.
5. **Chord choice in onboarding.** The spec fixes ⌃⌥⌘ and puts Fn out of scope. Show a chord picker for other users? Recommendation: keep ⌃⌥⌘ fixed for v1 and show it; add a picker only after the first public release.
6. **Spec story 37.** Drop Input Monitoring from the story? Recommendation: yes, after one clean-account test by the owner shows no Input Monitoring prompt.
7. **Price in onboarding.** Show a number ("about $0.10 per hour") or only "a few cents per hour"? The $0.10/h MAI price is a promotion until 2026-12-31. Recommendation: "a few cents per hour" plus the provider's pricing link.
8. **Onboarding as its own window or as a first pane in Settings.** Recommendation: its own window; the memory cost is about the same and a first-run user expects a welcome window.
