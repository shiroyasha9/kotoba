# Phase 1 + 2 manual test

Run this list on each new build before daily use. Write the result in the last column: `ok`, or what you saw.

UI text in this list is the text in the code at the phase 2 gate (2026-10-15). If the app shows other words, write them in the Result column.

## Setup (once per machine; repeat step 3 if a new build loses Accessibility)

1. Build: `make build`. Open: `open build/DerivedData/Build/Products/Debug/kotoba.app`.
2. Click **Allow** on the Microphone prompt.
3. System Settings > Privacy & Security > Accessibility: turn **kotoba** on. If it is already on, turn it off and on again.
4. kotoba menu > **Model: …** > **MAI-Transcribe-2 (OpenRouter)**. Then kotoba menu > **Set API Key…**: Settings opens on **Providers**. **API keys** > OpenRouter: paste the key > **Save**.

## Happy paths

| # | Do this | Expect | Result |
|---|---|---|---|
| 1 | In a terminal: tap Ctrl+Opt+Cmd, speak 10-20 s, tap again | Start sound after the tap; indicator "Listening" with mic level; text pasted in about 1 s | |
| 2 | Copy some text, dictate, wait 2 s, press Cmd-V | Your copied text pastes (clipboard restored) | |
| 3 | Hold Ctrl+Opt+Cmd, speak, release | Push-to-talk: text pastes after release | |
| 4 | Dictate in Cursor, Slack and a browser | Text pastes in each app | |
| 5 | Say the first word at the same moment as the tap | The first word is in the text | |
| 6 | Look at the menu while idle | First line: "Ready - tap Ctrl+Opt+Cmd" | |
| 7 | Click in a password field (secure input on), tap Ctrl+Opt+Cmd | Indicator: "Listening - secure input on"; the recording works | |

## Routes and keys

| # | Do this | Expect | Result |
|---|---|---|---|
| 8 | Open the **Model: …** submenu | 4 routes: "MAI-Transcribe-2 (OpenRouter)", "Grok STT (OpenRouter)", "Grok STT (xAI direct)", "MAI-Transcribe-2 (Azure direct)"; the current one is checked | |
| 9 | Look at the notes under the routes | "No zero-data-retention route" under Grok STT (OpenRouter); "Untested live" under both direct routes | |
| 10 | Pick **Grok STT (OpenRouter)**, dictate | Text pastes; the menu shows "Model: Grok STT (OpenRouter)" and the items "Format Numbers (format)" and "Keep Filler Words" | |
| 11 | Grok, **Format Numbers (format)** on: say "twenty five percent" | Text has "25%" | |
| 12 | Grok, **Keep Filler Words** on: say "um, open the file" | Text keeps "um" | |
| 13 | Pick **MAI-Transcribe-2 (OpenRouter)**, dictate | Text pastes; the Grok items are gone from the menu | |
| 14 | Settings > **Providers**: save a wrong OpenRouter key, then dictate | Indicator and menu first line: "Set your OpenRouter key"; nothing pastes | |
| 15 | Settings > **Providers**: save the right OpenRouter key | The dictation from row 14 is sent again and appears under **Recovered (1)**; a click copies it | |
| 16 | Pick **Grok STT (xAI direct)** with no xAI key, dictate | Indicator: "Set your xAI key"; the audio is kept | |
| 17 | Pick **MAI-Transcribe-2 (Azure direct)**, save an Azure key, leave **Azure Speech** > **Endpoint** empty, dictate | Indicator: "Set the Azure endpoint in Settings"; the audio is kept | |
| 18 | Go back to **MAI-Transcribe-2 (OpenRouter)** | The next dictation pastes as normal | |

## Dictionary and find/replace

| # | Do this | Expect | Result |
|---|---|---|---|
| 19 | Settings > **Dictionary** > **Add**: a rare term (for example a project name); dictate a sentence with it | The term is spelled as in the dictionary | |
| 20 | **Add** a word with **Replace it with** set (for example "pie torch" -> "PyTorch"); say the word | The replacement is in the pasted text | |
| 21 | Add a replacement with **Replacement** empty; say the word | The word is removed from the pasted text | |
| 22 | Add the same word twice | "This word is already in the dictionary." | |
| 23 | Add a term longer than 50 characters | The row says "Longer than 50 characters, so it is not sent to the model." | |
| 24 | Look under the list | "Keyterms sent: N of 100." | |
| 25 | Type in **Search words** | The list shows only matching rows | |
| 26 | Select a row, press Delete (or **Delete**) | The row is gone; the next dictation does not use it | |

## Wispr Flow import

| # | Do this | Expect | Result |
|---|---|---|---|
| 27 | Dictionary > **Import from Wispr Flow…** | "Import from Wispr Flow?" with "Adds N words and M replacements." and, when Wispr has them, "Includes N learned corrections…", "N entries already in your dictionary." and "Not imported: N snippets." | |
| 28 | Check the counts against Wispr Flow's dictionary | The counts match the words and replacements that are not already in kotoba | |
| 29 | Click **Import** | The words and replacements show in the list | |
| 30 | **Import from Wispr Flow…** again | "Nothing New in Wispr Flow": "Every word in Wispr Flow's dictionary is already here." | |
| 31 | Click **Cancel** on the preview (on a fresh dictionary) | Nothing is added | |

## Microphone

| # | Do this | Expect | Result |
|---|---|---|---|
| 32 | Open the **Microphone: …** submenu | The connected inputs; the one in use is checked; the title shows "Microphone: <name>" | |
| 33 | Pick another mic, dictate | kotoba records from the mic you picked; Settings > **Microphone** shows it at the top of **Your Order** | |
| 34 | Settings > **Microphone**: look at **Other Connected** | Connected mics that are not in your order, each with **Add** | |
| 35 | Click **Add** on a mic in **Other Connected** | It moves to **Your Order** | |
| 36 | Drag a mic to the top of **Your Order**, dictate | kotoba records from that mic (checkmark on it) | |
| 37 | Disconnect the first mic in the order, dictate | kotoba uses the next connected mic in the order; the first one shows "Not connected" | |
| 38 | Connect it again, dictate | kotoba uses it again | |
| 39 | Connect a mic during a recording | The recording keeps its mic; the new mic is used from the next dictation | |
| 40 | Look at a Bluetooth mic in the pane | "Bluetooth - lower quality" | |
| 41 | Right-click a mic in **Your Order** > **Remove from Order** | It leaves the order (and shows under **Other Connected** if it is connected) | |
| 42 | Click **Follow System Default** | "No mics in your order: kotoba follows the system default input."; with AirPods as output, kotoba records from the built-in mic | |

## Indicator position

| # | Do this | Expect | Result |
|---|---|---|---|
| 43 | With no saved position, start a dictation | A horizontal pill at the bottom center of the screen with the focused window, just above the Dock; never under the Dock, the menu bar or the notch | |
| 44 | Look at the "Listening" pill, then a state with longer text | "Listening" is about 170 pt wide; longer text makes the pill wider, up to 360 pt | |
| 45 | While the pill shows, start to drag it | The pill becomes a small round waveform icon; three faint glass shapes show at bottom center, left mid-height and right mid-height; the nearest one is tinted | |
| 46 | Drag it to the left edge and release | It snaps to the left edge with a short animation; "Listening" stands vertical (dot over a level bar) | |
| 47 | Drag it to the right edge and release; stop the dictation | It snaps to the right edge; "Transcribing" stands vertical (dot over a spinner) | |
| 48 | At a side edge, press Esc during a recording | "Cancelled" + **Undo** shows as a horizontal pill at mid-height on that edge | |
| 49 | Drag it back to the bottom and release | It snaps to the bottom center | |
| 50 | Leave it at an edge, quit and open kotoba, dictate | The pill shows at the same edge | |
| 51 | Type in TextEdit, start a dictation, drag the pill, release, then type without a click | TextEdit stays the active app; the text cursor stays; the keys go to TextEdit | |
| 52 | Click the pill without moving it | The pill does not move; kotoba does not become the active app | |
| 53 | Press Esc during a recording, then click **Undo** one time | The recording resumes on the first click; focus stays in your app | |
| 54 | In dark mode, press Esc during a recording | The "Undo" title is easy to read | |
| 55 | With a second display: focus a window on it, start a dictation | The pill shows on that display at the saved position | |
| 56 | While a message pill (for example "Copied - press Cmd-V") shows on display 1, start a dictation on display 2 | The pill moves to display 2 | |
| 57 | While the pill shows, press Option-Cmd-D two times (hide and show the Dock) | The pill moves so it stays inside the visible area | |
| 58 | Menu > **Indicator Position** > **Left**, then **Right**, then **Bottom Center**, while the pill shows | The pill moves to each position; the last choice is checked and kept | |

## Cleanup chord

| # | Do this | Expect | Result |
|---|---|---|---|
| 59 | Open the menu | "Cleanup Chord: Ctrl+Opt+Cmd+Shift"; the submenu has "Ctrl+Opt+Cmd+Shift", "Ctrl+Opt+Cmd+Fn" and "Off" | |
| 60 | Tap Ctrl+Opt+Cmd+Shift, say "um so open the auth dot ts file", tap again | The cleaned text pastes: "Open the auth.ts file." (no fillers, symbols written) | |
| 61 | Same, with a question or an order to the model (for example "what is two plus two") | The question is pasted as text; the model does not answer it | |
| 62 | With a Caps Lock "Hyper" key (all four modifiers), tap it, speak, tap again | A cleanup dictation, as in row 60 | |
| 63 | Tap plain Ctrl+Opt+Cmd after a cleanup dictation | A normal dictation: raw text, no cleanup | |
| 64 | Make a cleanup dictation and turn Wi-Fi off while "Transcribing" shows, right after the text arrives (hard to time; the pipeline tests cover it, so skip the row if you cannot cause it) | The raw text pastes; indicator: "Cleanup failed - pasted the raw text" | |
| 65 | Turn Wi-Fi off, make a cleanup dictation, turn Wi-Fi on, **Retry Failed Dictations** | The item under **Recovered** holds the cleaned text | |
| 66 | Menu > **Cleanup Chord** > **Ctrl+Opt+Cmd+Fn**; tap it, speak, tap again | A cleanup dictation; Ctrl+Opt+Cmd+Shift now makes a normal dictation | |
| 67 | Menu > **Cleanup Chord** > **Off** | No chord makes a cleanup dictation | |

## Settings window

| # | Do this | Expect | Result |
|---|---|---|---|
| 68 | Menu > **Settings…** (or Cmd-, while the menu is open) | Window "kotoba Settings" with the panes Dictionary, Microphone and Providers in the sidebar | |
| 69 | Menu > **Set API Key…** | Settings opens on **Providers** | |
| 70 | **Providers** > **Route** picker | The 4 routes, with the same notes as the Model menu | |
| 71 | Pick a Grok route in the pane | "Format numbers and units" and "Keep filler words" show | |
| 72 | **API keys**: type a key for OpenRouter, press **Save** | The field clears and shows "Saved"; **Remove** is enabled | |
| 73 | **API keys** for xAI and Azure | Each shows "Not set"; **Remove** is dimmed until you save a key | |
| 74 | **Route**: pick an Azure route; leave **Azure Speech** > **Endpoint** empty | The example URL in the field is dimmer than typed text | |
| 75 | **Azure Speech** > **Endpoint**: type `http://example.com` | Red text: "Use the https endpoint from the Azure portal (Keys and Endpoint)." | |
| 76 | After row 17: type a valid https endpoint | The dictation from row 17 is sent again (it fails or recovers; the route is untested live) | |
| 77 | **Cleanup** > **Model** | "Gemini 3.5 Flash-Lite" (default), "Qwen 3.8 27B (Cerebras)", "Claude Haiku 5.5" | |
| 78 | With Settings open, change the route in the menu | The pane's **Route** shows the new route at once | |
| 79 | Change the route in the pane, then open the menu | The menu shows the same route (checked) | |
| 80 | Copy your OpenRouter key; click the OpenRouter key field; press Cmd-V | The key pastes (dots show); no beep | |
| 81 | Dictionary: type in **Search words**, press Cmd-A, then Cmd-C; paste in another app | The search text pastes there; no beep | |
| 82 | Dictionary > **Add**: press Cmd-V in the word field and in **Replacement** | The clipboard text pastes in each field; no beep | |
| 83 | Providers > **Azure Speech** > **Endpoint**: press Cmd-V | The clipboard text pastes; no beep | |
| 84 | Close the Settings window | It closes; kotoba stays in the menu bar | |

## Cancel and undo

| # | Do this | Expect | Result |
|---|---|---|---|
| 85 | Start a dictation, press Esc | "Cancelled" + **Undo** for 5 s; menu first line "Cancelled - Undo available"; orange mic dot goes off; nothing pastes | |
| 86 | Esc, then click **Undo** within 5 s, speak more, tap to stop | One text with everything said before and after; focus stays in your app | |
| 87 | Esc, then tap Ctrl+Opt+Cmd within 5 s, speak, tap to stop | Same as 86 | |
| 88 | Esc, wait more than 5 s | Cancel is final; nothing pastes | |
| 89 | Press a Ctrl+Opt+Cmd+key shortcut (any key) | No sound, no indicator, no recording; the shortcut works in the app | |

## Failure and recovery

| # | Do this | Expect | Result |
|---|---|---|---|
| 90 | Turn Wi-Fi off, dictate, turn Wi-Fi on | Indicator "Failed - retry from the menu"; no text lost; **Retry Failed Dictations (1)** sends it; it appears under **Recovered (1)**; a click copies it; the clipboard was not changed automatically | |
| 91 | Quit kotoba during an upload, open it again | The dictation appears under **Recovered** | |
| 92 | Quit kotoba (**Quit kotoba** or Cmd-Q) during a recording, open it again | Nothing is lost: the dictation is transcribed at launch and appears under **Recovered** | |
| 93 | Tap twice fast (empty recording) | No paste; "Failed - retry from the menu" | |
| 94 | **Retry Failed Dictations** for that empty recording | It is tried one more time; empty again, it shows "Refused - check the key or credits" and is not retried after that | |
| 95 | Use a key with no credits (or a refused request) | "Refused - check the key or credits"; the audio is kept; it is not retried | |

## Audio devices

| # | Do this | Expect | Result |
|---|---|---|---|
| 96 | Connect AirPods, dictate (no mic in your order) | Text pastes; recorded from the built-in mic (check: speak away from the AirPods) | |
| 97 | Connect or remove AirPods during a recording | Recording continues or stops cleanly; the orange dot goes off after stop | |

## Clipboard edge cases

| # | Do this | Expect | Result |
|---|---|---|---|
| 98 | Start a dictation, copy something during recording, stop | Transcript pastes; after 1 s your new copy is on the clipboard | |
| 99 | Stop a dictation, copy something before the text pastes | Your new copy is on the clipboard after the restore | |
| 100 | Dictate twice quickly | Both paste; your original clipboard comes back | |

## Phase 2.5

Rows from each agent's phase 2.5 work. The numbers continue the list above.

### Menu, readiness and recovery

| # | Do this | Expect | Result |
|---|---|---|---|
| 101 | First launch on a clean user (or `defaults delete tech.teensy.kotoba onboarding.completed` with permissions reset) | No Microphone or Accessibility prompt at launch; the onboarding window opens | |
| 102 | Open the menu while setup is not complete | First line "Finish Setting Up kotoba…" with a subtitle that names the first missing thing; the menu bar icon shows the waveform with "!" | |
| 103 | Click "Finish Setting Up kotoba…" | Onboarding opens on that step | |
| 104 | Allow Accessibility in onboarding, then tap ⌃⌥⌘ at once | The hotkey works at once, not after 5 s | |
| 105 | Turn Wi-Fi off and dictate | Pill: "Couldn't reach OpenRouter. Saved." | |
| 106 | Turn Wi-Fi on | Within seconds the pill says "Saved dictation recovered" with **Copy**; the menu lists it under Recovered Dictations; nothing is pasted | |
| 107 | Settings > Microphone > **Test Microphone** | The level bar moves on the mic in use for 5 s and the orange dot shows; then both stop | |
| 108 | Start a dictation during the microphone test | The dictation works normally | |
| 109 | Cause each pill with a button: offline, no key, no credit, recovered, paste not allowed, mic access off | **Retry** retries; **Add Key…** opens Settings on Speech; **Add Credit…** opens the OpenRouter credits page; **Copy** copies the recovered text; **Allow Pasting…** opens onboarding at Accessibility; **Open Settings…** opens Privacy & Security > Microphone | |
| 110 | Menu > **About kotoba** | The standard About panel opens with the version | |

### Onboarding

| # | Do this | Expect | Result |
|---|---|---|---|
| 111 | Fresh setup: run `defaults delete tech.teensy.kotoba onboarding.completed`, remove kotoba's Microphone and Accessibility grants, open kotoba | "Welcome to kotoba" opens, centred, on Welcome; no Microphone or Accessibility prompt shows before its step | |
| 112 | Microphone step: click **Allow Microphone**, then **Allow** in the prompt | "Microphone allowed" with a checkmark; the window moves to Accessibility by itself in about 1 s | |
| 113 | Microphone step, deny instead | "Microphone access is off."; **Open System Settings** opens Privacy & Security > Microphone | |
| 114 | Turn kotoba on there | The step turns green and moves on without a click | |
| 115 | Accessibility step: click **Open Accessibility Settings** | The system prompt shows (kotoba joins the list) | |
| 116 | Click it again | Privacy & Security > Accessibility opens | |
| 117 | Turn kotoba on there | The step turns green within 1 s and moves on | |
| 118 | Key step: press ⌘V in the key field, then ⌘A | The key pastes, then all of it is selected; no beep | |
| 119 | Press Return | Same as **Save**: the field clears; the result line shows the key check ("Key works" for a good key) | |
| 120 | Click **Get a Key at OpenRouter…** | openrouter.ai/settings/keys opens | |
| 121 | Key step: click **See Pricing…** | The pricing page of the current speech model's provider opens (OpenRouter: openrouter.ai/microsoft/mai-transcribe-2) | |
| 122 | Key step: save a key with no credit | "This key has no credit. Add credit at OpenRouter." with **Add Credit…** | |
| 123 | Click **Add Credit…** | openrouter.ai/settings/credits opens | |
| 124 | Click **Use xAI or Azure Instead…** | Settings opens on Speech | |
| 125 | Try It step | The text field has focus | |
| 126 | Tap ⌃⌥⌘, speak, tap again | The text lands in the field; "It works." shows | |
| 127 | Hold ⌃⌥⌘ while you speak, let go | Same as the tap | |
| 128 | In the Try It field, press ⌘A, then ⌘V | Select all and paste work; no beep | |
| 129 | Done step | "Open kotoba when you log in" is on | |
| 130 | Click **Done** | kotoba is in System Settings > General > Login Items; if macOS asks for approval, the note and **Open Login Items Settings** show | |
| 131 | Close the window on the key step; menu > **Finish Setting Up kotoba…** | The window opens again on the key step | |
| 132 | Use **Back** and **Continue** on each step | Each moves one step | |
| 133 | Press Return on Welcome, Microphone, Accessibility and Done | Return clicks **Get Started**, **Continue** or **Done**; on the key and Try It steps Return belongs to the field | |

### Speech pane

| # | Do this | Expect | Result |
|---|---|---|---|
| 134 | Open Settings | The sidebar shows "Speech" with a speech-bubble symbol (not "Providers") | |
| 135 | Speech > **Speech model** | "MAI-Transcribe-2 via OpenRouter (Recommended)" and "Grok via OpenRouter"; under "Advanced": "Grok via xAI" and "MAI-Transcribe-2 via Azure"; no "Untested" text | |
| 136 | Pick **Grok via OpenRouter** | Footer: "OpenRouter may keep this audio. MAI-Transcribe-2 keeps none."; the toggles "Format numbers and units" and "Keep filler words" show; no "a few cents per hour" line | |
| 137 | Pick **MAI-Transcribe-2 via OpenRouter (Recommended)** | Only the "OpenRouter Key" section shows, with "You pay OpenRouter directly, a few cents per hour of speech."; no Azure section; no toggles | |
| 138 | Look under the key row | **Get a Key…** and **See Pricing…** | |
| 139 | Click **Get a Key…**, then **See Pricing…** | The browser opens OpenRouter's keys page, then the MAI-Transcribe-2 price page | |
| 140 | Pick each speech model in turn and click **Get a Key…** and **See Pricing…** | OpenRouter, the xAI console and the Azure portal (keys), and each provider's price page open (sign in if asked) | |
| 141 | Paste a valid key, press **Save** | "Checking the key…", then a green "Key works" | |
| 142 | Paste a wrong key (for example "sk-or-wrong"), press **Save** | "OpenRouter did not accept this key" in red | |
| 143 | Save a key with no credit | "This key has no credit." with **Add Credit…**, which opens OpenRouter's credits page | |
| 144 | Turn Wi-Fi off, save a key | "Couldn’t reach OpenRouter. The key is saved; kotoba checks it at your first dictation." | |
| 145 | Save a key, then save another one at once | Only the second key's result shows | |
| 146 | Close and open Settings with a saved key | The key row shows a green "Saved"; the field is empty (the key is never shown) | |
| 147 | Click in the key field, press ⌘V, then ⌘A | The key pastes (dots), then all of it is selected; no beep | |
| 148 | Pick **MAI-Transcribe-2 via Azure** | The "Azure Key" section and the "Azure Speech" endpoint section show; footer "Use a Speech resource in the region nearest to you." | |
| 149 | Endpoint field: press ⌘V, then ⌘A | The text pastes, then all of it is selected; no beep | |
| 150 | With dictations waiting for the endpoint, type a valid endpoint slowly, then press Return | Nothing is sent while you type; the waiting dictations are sent only after Return | |
| 151 | Type `https://example.com` in the endpoint field, press Return | Red text: "Use the https endpoint from the Azure portal (Keys and Endpoint)."; the stored endpoint does not change | |
| 152 | Type a valid endpoint, then click another field (no Return) | The endpoint is saved when the field loses focus | |
| 153 | Save an Azure key with the endpoint empty | "Key saved. Add your Azure endpoint to check it." | |
| 154 | With keys for two providers saved, look below the key section | A closed "Other Keys" group; it opens to the other provider's key row | |
| 155 | Change the speech model in the menu while Settings is open | The pane shows the new model at once | |
| 156 | Look for the cleanup model in the Speech pane | It is not there; it is in the General pane next to the cleanup chord | |

### Fix Last Dictation

| # | Do this | Expect | Result |
|---|---|---|---|
| 157 | Dictate "deploy it to versel today", then menu > **Fix Last Dictation…** | The field shows that dictation's text; **Learn** is dimmed until you change the text | |
| 158 | In the field, press ⌘A, ⌘C, ⌘X, ⌘V and ⌘Z | Each works; no beep | |
| 159 | Change "versel" to "Vercel", click **Learn** | "versel -> Vercel" shows, checked | |
| 160 | Change a known word pair (for example "add it" to "audit"), click **Learn** | The pair shows unchecked | |
| 161 | Edit the text again after **Learn** | The list goes away; **Learn** shows again | |
| 162 | Click **Add and Copy** | The window closes; nothing pastes by itself; ⌘V in any app pastes the fixed text | |
| 163 | Open Settings > Dictionary | "Vercel" and the replacement versel -> Vercel are there; the pair does not come back as a suggestion | |
| 164 | After **Learn**, uncheck every word | The button reads **Copy**; it copies the text and adds nothing | |
| 165 | With no dictation since install, open **Fix Last Dictation…** | "No dictation to fix yet" and **Close** | |

### Pill action buttons

| # | Do this | Expect | Result |
|---|---|---|---|
| 166 | Turn Wi-Fi off and dictate | The pill shows its message with one button (**Retry**) and stays about 8 s; a message pill without a button stays about 4 s | |
| 167 | Hold the pointer over a message pill | It does not hide while the pointer is on it; it hides a few seconds after the pointer leaves | |
| 168 | While you type in another app, click the pill's button | The action runs on the first click (for example **Retry** starts the retry); the pill hides; focus stays in the app you type in | |
| 169 | Press Esc during a recording, wait | **Undo** keeps the pill until the Undo window ends | |

## Known offscreen-only doubts

The offscreen snapshots (`make snapshots`) show two things that may not happen in the real app. Check them on screen:
- Row 54: the "Undo" title on the dark Cancelled pill renders black on dark offscreen.
- Row 74: the empty Azure endpoint's example URL renders as bright as typed text offscreen.

## Gates (after a day of use; each needs the owner's go because it reads the app database)

- `make latency RUN=1`: p50 <= 1.0 s and p90 <= 1.5 s from stop to Cmd-V, for 10-20 s dictations, per model. Cleanup-chord dictations are left out.
- `make memory`: idle footprint, compared with the floor in `docs/research/memory-spike.md`. Measure once with the Settings window never opened, and once after it was opened and closed.
