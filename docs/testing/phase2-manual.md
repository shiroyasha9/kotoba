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
| 34 | Settings > **Microphone**: click **+** under **Your Order** | A menu of the connected mics that are not in your order; **+** is dimmed when there are none | |
| 35 | Pick a mic in the **+** menu | It joins the end of **Your Order** | |
| 36 | Drag a mic to the top of **Your Order**, dictate | The row moves while you drag; kotoba records from that mic (“In use” on its row) | |
| 37 | Disconnect the first mic in the order, dictate | kotoba uses the next connected mic in the order; the first one shows "Not connected" | |
| 38 | Connect it again, dictate | kotoba uses it again | |
| 39 | Connect a mic during a recording | The recording keeps its mic; the new mic is used from the next dictation | |
| 40 | Look at a Bluetooth mic in the pane (in the order, or in the **+** menu) | “Bluetooth: call-quality audio” | |
| 41 | Right-click a mic in **Your Order** > **Remove from Order**; then select one and click **−**; then select one and press Delete | Each time it leaves the order (and shows in the **+** menu if it is connected) | |
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
| 107 | Settings > Microphone > **Test Microphone** | The **Input level** bar moves for 5 s and the orange dot shows; then both stop | |
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

### Pill bar and "Show indicator" (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 170 | With a message pill that has a button (for example Wi-Fi off, **Retry**), look at the pill bottom | A thin bar starts full and empties in about 8 s; the pill hides when it is empty | |
| 171 | Hold the pointer on that pill for 20 s, then move it away | The bar stops while the pointer is on the pill; after you leave it runs on from where it stopped, and the pill hides when the bar is empty | |
| 172 | Press Esc during a recording; hold the pointer on the Cancelled pill for 20 s, then click **Undo** | The bar stops and the Undo window stays open; **Undo** resumes the recording | |
| 173 | Press Esc during a recording; hold the pointer on the pill for 2 s, move it away, wait | The bar runs on; the pill hides when the bar is empty (about 5 s in total, not counting the hold) | |
| 174 | Settings > General > **Show indicator**: **Always** | A small round waveform pill shows at the saved position; it shows no level and no motion | |
| 175 | Type in TextEdit, click the round pill, speak, click the pill again | The click starts a dictation like a chord tap; the second click stops it; the text pastes into TextEdit; TextEdit stays the active app and keeps its cursor | |
| 176 | With **Always**, drag the round pill to another position | The pill moves; no dictation starts | |
| 177 | With **Always**, finish a dictation and wait for a message pill to end | The pill goes back to the small round pill, not hidden | |
| 178 | Set **Show indicator** back to **While Dictating** | The round pill goes away at once | |
| 179 | On macOS 27, with **Always**, move the pointer over the round pill and press | The glass shows a response to the pointer and the press (interactive glass) | |
| 264 | With **While Dictating**, start a dictation with the chord, then click the Listening pill | The click stops the dictation like a chord tap; the text pastes into your app | |
| 265 | Look at the pill edges over a light and a dark window | The glass shadow is soft on every side; no straight cut-off edge; clicks just outside the pill reach the app below | |
| 277 | Put the pointer where the pill appears and keep it still; dictate, press Esc (the Cancelled pill appears under the pointer), then move the pointer away | The bar stops while the pointer is on the pill; after you move away the bar runs on and the pill goes in about 5 s; the next dictation works | |

### Learning from edits (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 180 | In TextEdit, dictate "deploy it to versel today"; change "versel" to "Vercel"; click another app | Within about 1 s the pill shows a sparkle, "Added Vercel" and **Undo**, with the bar | |
| 181 | Open Settings > Dictionary | "Vercel" and the replacement versel -> Vercel are there | |
| 182 | Repeat 180, then click **Undo** on the pill | The word and the replacement are gone from the dictionary; the same fix later adds nothing and shows no pill | |
| 183 | Dictate a sentence, change "add it" to "audit", click another app | No pill; after the same fix a second time, "audit" shows in Dictionary > Suggestions | |
| 184 | In Slack, dictate a message with a name spelled wrong, fix the name, press Return | The pill shows "Added <name>" after the message is sent (the first paste into Slack after launch may learn nothing) | |
| 185 | In Safari or Chrome, dictate into a text field, fix a name, click elsewhere on the page | The pill shows "Added <name>" | |
| 186 | In a terminal prompt, dictate, fix a word | Nothing is learned or the word is learned; menu > **Fix Last Dictation…** still teaches it | |
| 187 | Dictate into a password field (for example a login page), then type in it | The field is never read: Instruments shows no "readback read" interval, and nothing is learned | |
| 188 | Dictate, fix a word, and within 1 s start the next dictation | The recording pill shows (no learned-word pill); the fixed word shows in Suggestions | |
| 189 | Dictate, change nothing for 60 s | No pill; nothing is learned | |
| 190 | Dictate, then rewrite the whole sentence | Nothing is learned | |
| 191 | Instruments > Points of Interest (subsystem tech.teensy.kotoba) during 180 | "readback open" once per paste and "readback read" once after each typing pause; no readback interval between dictations | |
| 192 | Settings > Dictionary: turn **Learn from my edits** off; repeat 180 | No pill; nothing is learned; Instruments shows no "readback open" interval | |

### User-set chords (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 200 | Settings > General > click the **Dictate** shortcut, press and release ⌃⌥⌘ | The button shows "Press keys", then the held keys, then ⌃⌥⌘; no dictation starts while you record | |
| 201 | Record fn (press and release fn alone) as **Dictate**; tap fn in TextEdit, speak, tap fn | A dictation, as with ⌃⌥⌘; the hint about the fn key setting shows under the button; ⌃⌥⌘ does nothing now | |
| 202 | Record right ⌥ (right Option alone) as **Dictate**; tap left ⌥, then right ⌥ | Left ⌥ does nothing; right ⌥ starts a dictation. The menu says "Tap right ⌥ to dictate" | |
| 203 | Record ⌃⌥Space as **Dictate**; in TextEdit hold ⌃⌥Space while you speak, let go | Push-to-talk works; no space and no other character is typed into TextEdit, also while the key repeats | |
| 204 | With ⌃⌥Space as **Dictate**, press ⌃⌥⇧Space and ⌃Space | Neither starts a dictation; they reach the app or macOS as before | |
| 205 | With each chord of 201-203, press the chord plus another key (for example ⌃⌥Space then K) before the start sound | No sound, no recording; the other key reaches the app | |
| 206 | With each chord of 201-203, press Esc during a recording | The recording is cancelled with Undo, as with ⌃⌥⌘ | |
| 207 | Record ⌘Space, then ⌥ alone, then K alone, then Esc with ⌥, as **Dictate** | Each is refused with its reason (macOS uses it; part of many shortcuts; add a modifier; Esc cancels a dictation); the old chord stays and still works | |
| 208 | Record the cleanup chord (⌃⌥⇧⌘) as **Dictate** | Refused: "This is the cleanup shortcut." | |
| 209 | Set **Dictate** to fn, then record ⌃⌥⌘ as **Clean up**, then dictate with ⌃⌥⌘ | A cleanup dictation; fn makes a plain dictation | |
| 210 | Click the cleanup shortcut's ⊗ button | The shortcut shows "Off", the cleanup model is greyed out, and the cleanup chord does nothing | |
| 211 | Click the ↺ button next to a changed shortcut | It goes back to ⌃⌥⌘ (or ⌃⌥⇧⌘ for cleanup) at once | |
| 212 | Click a shortcut button, then press Esc, or click it again, or switch to another app | Recording stops; the shortcut does not change; ⌃⌥⌘ dictates again at once | |
| 213 | Change **Dictate**, quit kotoba, open it again | The new chord works and shows in the menu and in Settings | |
| 214 | First launch (onboarding Welcome): record fn as the shortcut | The text above changes to "Tap fn"; the Try It step and the menu say fn | |

### Submit after paste and Last Dictation (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 230 | In cmux (Claude Code prompt), dictate "list the files in this repo. Press enter." | The prompt gets "list the files in this repo." without the phrase, and Claude Code starts on it (Return sent) | |
| 231 | In cmux (Codex prompt), dictate "explain the last commit, press return" | "explain the last commit" pastes and is submitted | |
| 232 | In Slack, dictate "Running five minutes late. Press enter." | The message "Running five minutes late." is sent, whole; no text stays in the box | |
| 233 | In Slack, dictate a long message (about 60 words) that ends with "press enter" | The whole message is sent as one message; no part of it stays in the box | |
| 234 | In Chrome, in a search field, dictate "kotoba dictation. Press return." | The search runs for "kotoba dictation." | |
| 235 | In TextEdit, dictate "Looks good, send it." and "Press enter to continue." | Both paste as spoken; no Return ("send it" is not a submit phrase; the other phrase is not at the end) | |
| 236 | In TextEdit, dictate only "Press enter." | "Press enter." pastes; no Return | |
| 237 | Settings > General > turn off **Press Return when you say “press enter”**; dictate "hello. Press enter." | "hello. Press enter." pastes; no Return. Turn it on again | |
| 238 | With the cleanup chord, dictate "um so fix the the bug. Press enter." | The cleaned text pastes without "Press enter", then Return | |
| 239 | Turn Wi-Fi off, dictate "test. Press enter.", turn Wi-Fi on, copy it from **Recovered Dictations** | The recovered text is "test." and no Return was sent at any time | |
| 240 | Instruments > Points of Interest during 230 | A "returnSent" point follows "pasteSent" by less than 5 ms | |
| 241 | Dictate into TextEdit, click into another TextEdit window, menu > **Paste Last Dictation** | The same text pastes into the second window; the clipboard holds what it held before (check with ⌘V after 2 s) | |
| 242 | Menu > **Copy Last Dictation**, then ⌘V in TextEdit | The last dictation pastes; it stays on the clipboard | |
| 243 | With the cleanup chord, dictate "um so the the plan"; menu > **Paste Last Without Cleanup** | The raw words "um so the the plan" paste. After a plain dictation the item is not in the menu | |
| 244 | Turn off Accessibility for kotoba; menu > **Paste Last Dictation** | The pill shows the copied message; the text is on the clipboard. Turn Accessibility on again | |
| 245 | In cmux (Claude Code prompt), tap the chord, speak "list the files", press Return | The recording stops at Return; "list the files" pastes, then Claude Code starts on it. No extra Return or new line before the paste | |
| 246 | Tap the chord, speak, hold Return for 2 s, release | One Return only, after the paste; no repeated Returns reach the app | |
| 247 | Tap the chord, speak, press ⇧Return | The recording goes on; the app gets ⇧Return as usual | |
| 248 | Press Return with no dictation running, and press Esc during a recording | Return reaches the app as usual; Esc still cancels with Undo | |
| 249 | Turn Wi-Fi off, tap the chord, speak, press Return; turn Wi-Fi on and retry | The dictation goes to **Recovered Dictations**; no Return is sent | |
| 288 | In Slack, tap the chord, say "hello. Press enter.", tap the chord, and click TextEdit within 1 s | "hello." pastes into TextEdit; no Return; the pill shows "Didn’t press Return: app changed" | |
| 289 | Tap the chord to stop, and press Return at once (within about 0.1 s) | One Return, after the paste; the Return is not lost | |
| 290 | Start a long dictation, stop it, and during "Transcribing" choose menu > **Paste Last Dictation** | Nothing pastes from the menu; the new dictation pastes once | |

### Live no-sound warning (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 266 | Choose the built-in mic. In System Settings > Sound > Input, set the input volume to 0; tap the chord and say nothing | About 2 s after the start the pill and the menu status show “No sound from the mic” with **Microphone…**; the pill’s help tag names the mic; recording goes on | |
| 267 | With the warning up, set the input volume back and speak | The warning goes away at your first word; the pill says “Listening” again | |
| 268 | Input volume normal, in a quiet room, tap the chord and say nothing for 15 s | No warning at any time | |
| 269 | Hold the chord with the input volume at 0 for about 1 s, then release | No warning; the dictation ends as usual | |
| 270 | Choose AirPods as the mic; tap the chord, wait 1 s, then speak; later stay silent for 10 s | No warning while the AirPods start; note if a warning shows in the silence (AirPods noise suppression) | |
| 271 | During a recording with a USB mic, unplug it | Within about 2 s the pill shows the warning (or recording moves to another mic and shows its level) | |
| 272 | Click **Microphone…** on the warning | Settings opens on the Microphone pane; recording goes on until you stop it | |

### Native components (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 252 | Settings > Microphone with AirPods connected and not in the order: click **+** | AirPods Pro in the menu with “Bluetooth: call-quality audio” under its name | |
| 253 | Settings > Microphone: drag the second mic above the first | A drop line shows while you drag; the order changes and stays after you close and open Settings | |
| 254 | Settings > Microphone: no mic selected | **−** is dimmed; with every connected mic in the order, **+** is dimmed | |
| 255 | Settings > Dictionary > **Import from Wispr Flow…**, then press Esc; again, then press Return | An alert (not a panel in the pane): Esc cancels and adds nothing; Return imports | |
| 256 | Settings > Dictionary: select a word, click **−**; click **+** | The word is deleted; **+** opens the Add Word sheet | |
| 257 | Fix Last Dictation…: click into the text, press ⌘A then type | The whole text is replaced; the box has no separate border inside the grouped box | |
| 258 | Onboarding Done step: click each switch | Each switch changes; the two switches sit in one grouped box | |
| 259 | Settings window toolbar | No sidebar toggle button; the sidebar cannot be hidden | |
| 260 | Choose AirPods as the mic (menu), then open Settings > Microphone | “Bluetooth mic: call-quality audio” with its detail at the top of **Your Order**; the AirPods row says only “In use” | |
| 261 | Settings > Microphone open: plug in a USB mic, then unplug it | It shows in the **+** menu (or as connected in **Your Order**) at once, and goes away again; no reopen needed | |
| 262 | Settings > Microphone open: pick another mic in the menu bar **Microphone** submenu | “In use” moves to that mic in the pane at once; with AirPods, the Bluetooth warning appears | |
| 273 | AirPods as output, choose **AirPods Pro** in **Microphone** | At the foot of the submenu: a dimmed warning “Bluetooth mic: call-quality audio” with “Playback drops to call quality. Start and stop are slower, and the first word can be lost.” | |
| 274 | AirPods as output, the built-in mic or a USB mic in use; play a video, then dictate | No warning in the menu; the video audio does not drop to call quality; System Settings > Sound > Input keeps its default | |
| 275 | AirPods as the system default input, no mic in your order; play a video, then dictate | kotoba records from the built-in mic; the video audio does not drop to call quality | |
| 276 | Unplug or turn off the mic in use during a recording | The recording goes on with the next mic (your order, then the system default); no crash | |

### History window (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 291 | Menu > **History…** with no dictations yet | The History window opens with “No Dictations Yet” and your chord | |
| 292 | Dictate in Notes, then in Terminal, with History open | Each dictation appears at the top under **Today** at once, with the app’s icon and name, its length and word count | |
| 293 | Type a word from one dictation in the search field; then a word from none | Only matching rows show; then “No Results for …” | |
| 294 | In the search field: type text, press ⌘A, then ⌘C, then paste in another app | ⌘A selects the search text, ⌘C copies it (not the selected row) | |
| 295 | Select a row, press ⌘C, then paste in another app | The row’s text pastes (the cleaned text for a cleanup dictation) | |
| 296 | Right-click a cleanup dictation > **Copy Without Cleanup**; hover over the row | The raw transcript is on the clipboard; the help tag shows “Before cleanup: …” | |
| 297 | Click into a text field in another app, open History, select a row, click **Paste Again** (toolbar) | The app you were in comes to the front and the text pastes there; History and any other kotoba window stay open behind it; your clipboard comes back after about 1 s | |
| 298 | Start a dictation, then look at **Paste Again** in History while it records and transcribes | **Paste Again** is dimmed until the dictation ends | |
| 299 | Turn Wi-Fi off, dictate, turn Wi-Fi on before the network retry, then in History select the “Not transcribed” row > **Retry** | The pill shows “Saved dictation recovered”; the row changes to “Recovered” with its text | |
| 300 | Press Esc during a dictation and let Undo run out; in History select the “Cancelled” row > **Retry** | The audio is sent; the row changes to “Recovered” with its text | |
| 301 | Select two rows, press Delete; click **Delete** in the dialog | “Delete 2 Dictations?”; the rows are gone, and their audio files are gone from `~/Library/Application Support/kotoba/audio` | |
| 302 | Scroll History with more than 200 dictations | Older rows load as you reach the end; no pause | |
| 303 | Close History, then open it again | It opens at the same size and place, with the search cleared | |
| 304 | With no OpenRouter credit, dictate (“Refused” row); add credit, then select the row > **Retry** | The row changes to “Recovered” with its text | |
| 305 | Turn Wi-Fi off, dictate, select the “Not transcribed” row > **Retry**, then **Delete** it before Wi-Fi returns; turn Wi-Fi on | The row stays deleted; no “Saved dictation recovered” pill | |
| 306 | Open History while Settings is open; Paste Again a row | Settings stays open; the indicator shows at the next dictation | |
| 307 | Right-click the empty part of the History list | No menu | |
| 308 | Scroll History to the last loaded row, select it if it is “Not transcribed”, click **Retry** | The row stays in place and changes to “Recovered” | |
| 309 | Open Settings, press ⌘W; open History, press ⌘W; open **Fix Last Dictation…**, press ⌘W | Each window closes; no beep | |
| 310 | In History, click a row, press ⌘F, type a word | The search field gets the focus and the list filters | |
| 311 | Move and resize Settings and History, close each, reopen it at once (within 2 s) | Each opens at the size and place you left it | |
| 312 | Open History from the menu while a text field in another app has the focus, quit that app, then **Paste Again** a row | Nothing pastes into History; “Couldn’t Paste” says the text is on the clipboard; ⌘V in another app pastes it | |
| 313 | Start two dictations back to back so both are sent at once; watch their rows in History | Each row says “Transcribing” only until its own text arrives, then Delete works on it | |

### Usage pane (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 314 | With no dictations this month, open Settings > **Usage** | “No Dictations This Month”; **Last 30 Days** shows the same state when it is empty too | |
| 315 | Dictate three times in Notes and once in Terminal, one of them with the cleanup chord, then open Settings > **Usage** | Dictations 4; Words equal the sum of the History window’s word counts (the cleaned text for the cleanup dictation); Notes is above Terminal under **Top Apps** with its icon | |
| 316 | Look at **Spend** and **Spend by Model** after the dictations of row 315 (MAI-Transcribe-2 via OpenRouter) | Up to four decimals (for example $0.0021); one row “MAI-Transcribe-2 via OpenRouter” · Speech model, with no “Estimated”; the model rows add up to **Spend** | |
| 317 | Dictate once with the cleanup chord, then reopen **Usage** | A “Gemini 3.5 Flash-Lite” row (or the chosen cleanup model) with “Cleanup model” under it | |
| 318 | Compare **Spend** for this month with the Activity page on openrouter.ai for the same days | The two agree to the cent (kotoba keeps the cost OpenRouter reports for each dictation) | |
| 319 | Turn Wi-Fi off, dictate, turn it on so the dictation is recovered; reopen **Usage** | Dictations and Spend count it once; Audio counts it once | |
| 320 | Switch between **This Month** and **Last 30 Days** | The numbers change at once, with no pause | |
| 321 | Keep Settings open on **Usage** and dictate | The numbers change when the dictation is pasted, without leaving the pane | |
| 322 | Note **Spend** and **Audio**; in History select all of today’s dictations and delete them; look at **Usage** again | Spend, Audio, Words and Dictations do not change | |
| 323 | Say nothing for 3 s as a dictation (“No speech heard”), then look at **Usage** | Audio and Spend go up (the empty answer is billed); Dictations and Words do not | |

### Audio retention (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 324 | Open Settings > **General** on a fresh install | **History** section: **Keep audio** is “7 Days”; **Saved audio** shows “Zero KB” and **Delete Audio Now…** is dimmed | |
| 325 | Keep Settings on **General** and dictate | **Saved audio** grows when the dictation is pasted, without leaving the pane | |
| 326 | Have dictations from more than one day ago (pasted, one “Not transcribed”, one “Cancelled”); set **Keep audio** to “1 Day” | “Delete Audio Older Than 1 Day?” asks first and says how much it deletes. **Cancel** keeps the old period and deletes nothing. **Delete Audio**: the pasted rows older than a day show “audio deleted” in History and **Saved audio** gets smaller; the “Not transcribed” and “Cancelled” rows still say “audio saved” and **Retry** works on them | |
| 327 | Select a row that shows “audio deleted” | Copy and Paste Again work; there is no Retry; the text is the same as before | |
| 328 | Note **Spend** in **Usage**; set **Keep audio** to “1 Day” as in row 326; look at **Usage** again | Spend, Audio, Words and Dictations do not change | |
| 329 | Click **Delete Audio Now…**, then **Cancel**; click it again, then **Delete Audio** | The dialog says how much it deletes. Cancel deletes nothing. **Delete Audio** deletes the audio of every transcribed dictation, today’s too: **Saved audio** goes to “Zero KB” and the button dims; failed, cancelled and refused rows keep theirs; every row stays in History | |
| 330 | Set **Keep audio** to “Forever”, quit kotoba, reopen it | The setting is still “Forever” and no question is asked (a longer period applies at once); no audio is deleted at launch | |
| 331 | Set **Keep audio** to “7 Days”, leave kotoba closed for more than 7 days after a dictation, then open it | Once dictation works, that dictation shows “audio deleted” in History, with no dictation needed | |
| 332 | With Wi-Fi off, dictate once (“Not transcribed”); look at the **History** section | Under the section: “… of audio for Retry is kept until sent” with a size; it goes away once Retry sends the dictation | |
| 333 | Update from a build without audio retention (dictations older than 7 days in History), open kotoba, then Settings > **General** | **Keep audio** is “Forever”; no audio was deleted; History shows no “audio deleted” | |
| 334 | With only today’s dictations, set **Keep audio** from “30 Days” to “1 Day” | No question: nothing is old enough to delete, so the period applies at once | |
| 335 | Set **Keep audio** to “1 Day” (confirm if asked) and keep kotoba running. Today, dictate once with Wi-Fi on and once with Wi-Fi off (“Not transcribed”). Tomorrow, without dictating or quitting, turn Wi-Fi on and **Retry** that row | Once Retry recovers it, retention runs: yesterday’s pasted dictation shows “audio deleted” (a recovered dictation is delivered too) | |

Follow-ups (audio retention):

- Audio files with no row (a crash or force quit during a recording, a failed save at the stop, a failed delete) are never counted, kept by retention or removed by **Delete Audio Now…**. They are unsaved dictations, so the fix is crash recovery (adopt them as queued dictations), not deletion.

### Per-app modes (phase 3)

The Writing prompt waits for its benchmark (docs/research/per-app-modes.md, question 3); rows 340-341 check the wiring, not its quality.

| # | Do this | Expect | Result |
|---|---|---|---|
| 336 | Open Settings > **Modes** on a fresh install | **Clean Up Every Dictation**: both toggles off. **Apps** lists the installed apps of the standard lists with their icons (for example Terminal in Code, Mail, Messages and Notes in Writing); **Other apps** is Code | |
| 337 | Click **+** | **Recent Apps** lists apps you dictated into in the last 30 days that are not in the list (never kotoba), then **Choose App…** | |
| 338 | **+** > **Choose App…**, pick an app in /Applications (for example TextEdit) | It joins the list as Writing (other apps are Code); quit and reopen kotoba: it is still there | |
| 339 | Select a row, click **−** (also try right-click > **Remove from List** and the Delete key) | The row goes; that app now uses **Other apps** | |
| 340 | Dictate in Terminal with the cleanup chord, then in Notes with the cleanup chord | Terminal gets a clean prompt with paths and flags kept; Notes gets prose. History shows the cleaned text for both | |
| 341 | Turn on **Writing apps**; tap the plain chord in Notes and dictate | The recording pill shows the wand symbol in place of the dot (help tag: “kotoba cleans up this dictation before it pastes.”); after the stop the pill says “Transcribing”, then “Cleaning up” with the wand, then the cleaned text pastes | |
| 342 | With **Writing apps** on, tap the chord in Terminal, click into Notes, speak, tap to stop | The pill shows no wand while recording (Terminal is Code), but the text pasted in Notes is cleaned: the app in front at the stop decides | |
| 343 | With **Writing apps** on, tap the chord in Notes, click into Terminal, speak, tap to stop | The raw transcript pastes in Terminal, with no “Cleaning up” | |
| 344 | With **Writing apps** on, turn Wi-Fi off, dictate in Notes; switch to Terminal; turn Wi-Fi on so the dictation is recovered | The recovered text is cleaned as prose (the mode of the stop, not of the app in front now) | |
| 345 | Turn **Writing apps** off; dictate in Notes with a plain tap | Raw transcript, about as fast as before; no wand, no “Cleaning up” | |
| 346 | Set **Other apps** to Writing; dictate with the cleanup chord in Ghostty or Terminal | Still a Code cleanup (terminals stay in Code); in an app not in the list (for example TextEdit removed in row 339) the cleanup is prose | |
| 347 | Change a mode in Settings and at once dictate | The next dictation uses the new setting | |

## Known offscreen-only doubts

The offscreen snapshots (`make snapshots`) show two things that may not happen in the real app. Check them on screen:
- Row 54: the "Undo" title on the dark Cancelled pill renders black on dark offscreen.
- Row 74: the empty Azure endpoint's example URL renders as bright as typed text offscreen.
- History window (`history-window`): the search field's “Search” placeholder renders as dark as typed text, and the selected row grey. On screen the placeholder must be grey and the selection blue.
- Dark mode: the Settings sidebar labels and the pill's glass button titles (Undo, Retry) render near black offscreen (text on glass, docs/research/native-ui.md). On screen they must be light.

## Gates (after a day of use; each needs the owner's go because it reads the app database)

- `make latency RUN=1`: p50 <= 1.0 s and p90 <= 1.5 s from stop to Cmd-V, for 10-20 s dictations, per model. Cleanup-chord dictations are left out.
- `make memory`: idle footprint, compared with the floor in `docs/research/memory-spike.md`. Measure once with the Settings window never opened, and once after it was opened and closed.
