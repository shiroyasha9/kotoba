# Phase 1 + 2 manual test

Run this list on each new build before daily use. Write the result in the last column: `ok`, or what you saw.

UI text in this list is the text in the code at the phase 2 gate (2026-10-15). If the app shows other words, write them in the Result column.

## Setup (once per machine; repeat step 3 if a new build loses Accessibility)

1. Build: `make build`. Open: `open build/DerivedData/Build/Products/Debug/kotoba.app`. This is **kotoba Dev**, a separate install with its own settings, history (`~/Library/Application Support/kotoba-dev/`) and API keys. While the release kotoba runs, kotoba Dev leaves the chord to it (rows 360-364): quit the release kotoba to test.
2. Click **Allow** on the Microphone prompt.
3. System Settings > Privacy & Security > Accessibility: turn **kotoba Dev** on. If it is already on, turn it off and on again.
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
| 23 | Add a term longer than 50 characters | The row says "Longer than 50 characters, so kotoba does not send it to the speech model." | |
| 24 | Look under the list | "Keyterms sent: N of 100." | |
| 25 | Type in **Search words** | The list shows only matching rows | |
| 26 | Select a row, press Delete (or **Delete**) | The row is gone; the next dictation does not use it | |

## Wispr Flow import

| # | Do this | Expect | Result |
|---|---|---|---|
| 27 | Dictionary > **Import from Wispr Flow…** | "Import from Wispr Flow?" with "Adds N words and M replacements." (with ", including N corrections Wispr learned from your edits" when Wispr has them), "Already in your dictionary: N entries." and "Skips N snippets." | |
| 28 | Check the counts against Wispr Flow's dictionary | The counts match the words and replacements that are not already in kotoba | |
| 29 | Click **Import** | The words and replacements show in the list | |
| 30 | **Import from Wispr Flow…** again | "Nothing New in Wispr Flow": "Every word in Wispr Flow's dictionary is already in kotoba." | |
| 31 | Click **Cancel** on the preview (on a fresh dictionary) | Nothing is added | |

## Microphone

| # | Do this | Expect | Result |
|---|---|---|---|
| 32 | Open the **Microphone: …** submenu | The connected inputs; the one in use is checked; the title shows "Microphone: <name>" | |
| 33 | Pick another mic, dictate | kotoba records from the mic you picked; Settings > **Microphone** shows it at the top of **Microphone Order** | |
| 34 | Settings > **Microphone**: click **+** under **Microphone Order** | A menu of the connected mics that are not in your order; **+** is dimmed when there are none | |
| 35 | Pick a mic in the **+** menu | It joins the end of **Microphone Order** | |
| 36 | Drag a mic to the top of **Microphone Order**, dictate | The row moves while you drag; kotoba records from that mic (“In use” on its row) | |
| 37 | Disconnect the first mic in the order, dictate | kotoba uses the next connected mic in the order; the first one shows "Not connected" | |
| 38 | Connect it again, dictate | kotoba uses it again | |
| 39 | Connect a mic during a recording | The recording keeps its mic; the new mic is used from the next dictation | |
| 40 | Look at a Bluetooth mic in the pane (in the order, or in the **+** menu) | “Bluetooth: call-quality audio” | |
| 41 | Right-click a mic in **Microphone Order** > **Remove from Order**; then select one and click **−**; then select one and press Delete | Each time it leaves the order (and shows in the **+** menu if it is connected) | |
| 42 | Click **Follow System Default** | "No mics in your order: kotoba follows the system default input."; with AirPods as output, kotoba records from the built-in mic | |

## Indicator position

| # | Do this | Expect | Result |
|---|---|---|---|
| 43 | With no saved position, start a dictation | A horizontal pill at the bottom center of the screen with the focused window, just above the Dock; never under the Dock, the menu bar or the notch | |
| 44 | Look at the "Listening" pill, then a state with longer text | "Listening" is about 170 pt wide; longer text makes the pill wider, up to 360 pt | |
| 45 | While the pill shows, start to drag it | The pill becomes a small round waveform icon; three faint glass shapes show at bottom center, left mid-height and right mid-height; the nearest one is tinted | |
| 46 | Drag it to the left edge and release | It snaps to the left edge with a short animation; "Listening" stands vertical (dot over a level bar) | |
| 47 | Drag it to the right edge and release; stop the dictation | It snaps to the right edge; "Transcribing" stands vertical (dot over a spinner) | |
| 48 | At a side edge, press Esc during a recording | "Canceled" + **Undo** shows as a horizontal pill at mid-height on that edge | |
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
| 85 | Start a dictation, press Esc | "Canceled" + **Undo** for 5 s; menu first line "Canceled - Undo available"; orange mic dot goes off; nothing pastes | |
| 86 | Esc, then click **Undo** within 5 s, speak more, tap to stop | One text with everything said before and after; focus stays in your app | |
| 87 | Esc, then tap Ctrl+Opt+Cmd within 5 s, speak, tap to stop | Same as 86 | |
| 88 | Esc, wait more than 5 s | Cancel is final; nothing pastes | |
| 89 | Press a Ctrl+Opt+Cmd+key shortcut (any key) | No sound, no indicator, no recording; the shortcut works in the app | |

## Failure and recovery

| # | Do this | Expect | Result |
|---|---|---|---|
| 90 | Turn Wi-Fi off, dictate, turn Wi-Fi on | The pill says “Couldn’t reach OpenRouter. Saved.” with **Retry**; no text lost; **Retry Failed Dictations (1)** sends it; it appears under **Recovered (1)**; a click copies it; the clipboard was not changed automatically | |
| 91 | Quit kotoba during an upload, open it again | The dictation appears under **Recovered** | |
| 92 | Quit kotoba Dev (**Quit kotoba Dev** or Cmd-Q) during a recording, open it again | Nothing is lost: the dictation is transcribed at launch and appears under **Recovered** | |
| 93 | Tap the chord twice fast (under half a second of audio) | No paste, no error pill: the pill goes away; no new row in **History**, no Dock badge | |
| 94 | Tap the chord, say nothing for 2 s, tap again; then retry that dictation in **History** | No paste; the pill says “No speech heard”, not “Couldn’t reach OpenRouter”; no Dock badge. The retry sends it once more; empty again, it stays “No speech heard” and is not retried by itself | |
| 95 | Use a key with no credits, then send a request the route refuses | No credit: “OpenRouter is out of credit. Saved.” with **Add Credit…**; the dictation waits for credit. Refused: “OpenRouter refused the audio. Saved.”; it is not retried. The audio is kept in both | |

## Audio devices

| # | Do this | Expect | Result |
|---|---|---|---|
| 96 | Connect AirPods, dictate (no mic in your order) | Text pastes; recorded from the built-in mic (check: speak away from the AirPods) | |
| 97 | Connect or remove AirPods during a recording | Recording continues or stops cleanly; the orange dot goes off after stop | |

## Clipboard edge cases

| # | Do this | Expect | Result |
|---|---|---|---|
| 98 | Start a dictation, copy something during recording, stop | Transcript pastes; right after it pasted, your new copy is on the clipboard | |
| 99 | Stop a dictation, copy something before the text pastes | Your new copy is on the clipboard after the restore | |
| 100 | Dictate twice quickly | Both paste; your original clipboard comes back | |

## Phase 2.5

Rows from each agent's phase 2.5 work. The numbers continue the list above.

### Menu, readiness and recovery

| # | Do this | Expect | Result |
|---|---|---|---|
| 101 | First launch on a clean user (or `defaults delete tech.teensy.kotoba.dev onboarding.completed` with permissions reset) | No Microphone or Accessibility prompt at launch; the onboarding window opens | |
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
| 111 | Fresh setup: run `defaults delete tech.teensy.kotoba.dev onboarding.completed`, remove kotoba Dev's Microphone and Accessibility grants, open kotoba Dev | "Welcome to kotoba" opens, centred, on Welcome; no Microphone or Accessibility prompt shows before its step | |
| 112 | Microphone step: click **Allow Microphone**, then **Allow** in the prompt | "Microphone allowed" with a checkmark; the window stays on the step; **Continue** turns on and Return presses it | |
| 113 | Microphone step, deny instead | "Microphone access is off."; **Open System Settings** opens Privacy & Security > Microphone | |
| 114 | Turn kotoba Dev on there | The step turns green within 1 s and stays until you click **Continue** | |
| 115 | Accessibility step: click **Open System Settings…** | The system prompt shows (kotoba joins the list) | |
| 116 | Click it again | Privacy & Security > Accessibility opens | |
| 117 | Turn kotoba Dev on there | The step turns green within 1 s and stays until you click **Continue** | |
| 118 | Key step: press ⌘V in the key field, then ⌘A | The key pastes, then all of it is selected; no beep | |
| 119 | Press Return | Same as **Save**: the field goes; "sk-or-v1-…" and the last four characters of the key show with **Change…** and **Remove**; the result line shows the key check ("Key works" for a good key) | |
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
| 130 | Click **Done** | kotoba Dev is in System Settings > General > Login Items; if macOS asks for approval, the note and **Open Login Items Settings** show | |
| 131 | Close the window on the key step; menu > **Finish Setting Up kotoba…** | The window opens again on the key step | |
| 132 | Use **Back** and **Continue** on each step | Each moves one step | |
| 133 | Press Return on Welcome, Microphone, Accessibility and Done | Return clicks **Get Started**, **Continue** or **Done**; on the key and Try It steps Return belongs to the field | |

### Speech pane

| # | Do this | Expect | Result |
|---|---|---|---|
| 134 | Open Settings | The sidebar shows "Speech" with a speech-bubble symbol (not "Providers") | |
| 135 | Speech > **Speech model** | "MAI-Transcribe-2 via OpenRouter (Recommended)" and "Grok via OpenRouter"; under "Advanced": "Grok via xAI" and "MAI-Transcribe-2 via Azure"; no "Untested" text | |
| 136 | Pick **Grok via OpenRouter** | Footer: "OpenRouter may keep this audio. With MAI-Transcribe-2 it keeps none."; the toggles "Format numbers and units" and "Keep filler words" show; no "a few cents per hour" line | |
| 137 | Pick **MAI-Transcribe-2 via OpenRouter (Recommended)** | Only the "OpenRouter Key" section shows, with "You pay OpenRouter directly, a few cents per hour of speech."; no Azure section; no toggles | |
| 138 | Look under the key row | **Get a Key…** and **See Pricing…** | |
| 139 | Click **Get a Key…**, then **See Pricing…** | The browser opens OpenRouter's keys page, then the MAI-Transcribe-2 price page | |
| 140 | Pick each speech model in turn and click **Get a Key…** and **See Pricing…** | OpenRouter, the xAI console and the Azure portal (keys), and each provider's price page open (sign in if asked) | |
| 141 | Paste a valid key, press **Save** | "Checking the key…", then a green "Key works" | |
| 142 | Paste a wrong key (for example "sk-or-wrong"), press **Save** | "OpenRouter didn’t accept this key." in red, under "Key" | |
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
| 172 | Press Esc during a recording; hold the pointer on the Canceled pill for 20 s, then click **Undo** | The bar stops and the Undo window stays open; **Undo** resumes the recording | |
| 173 | Press Esc during a recording; hold the pointer on the pill for 2 s, move it away, wait | The bar runs on; the pill hides when the bar is empty (about 5 s in total, not counting the hold) | |
| 174 | Settings > General > **Show indicator**: **Always** | A small round waveform pill shows at the saved position; it shows no level and no motion | |
| 175 | Type in TextEdit, click the round pill, speak, click the pill again | The click starts a dictation like a chord tap; the second click stops it; the text pastes into TextEdit; TextEdit stays the active app and keeps its cursor | |
| 176 | With **Always**, drag the round pill to another position | The pill moves; no dictation starts | |
| 177 | With **Always**, finish a dictation and wait for a message pill to end | The pill goes back to the small round pill, not hidden | |
| 178 | Set **Show indicator** back to **While Dictating** | The round pill goes away at once | |
| 179 | On macOS 27, with **Always**, move the pointer over the round pill and press | The glass shows a response to the pointer and the press (interactive glass) | |
| 264 | With **While Dictating**, start a dictation with the chord, then click the Listening pill | The click stops the dictation like a chord tap; the text pastes into your app | |
| 265 | Look at the pill edges over a light and a dark window | The glass shadow is soft on every side; no straight cut-off edge; clicks just outside the pill reach the app below | |
| 277 | Put the pointer where the pill appears and keep it still; dictate, press Esc (the Canceled pill appears under the pointer), then move the pointer away | The bar stops while the pointer is on the pill; after you move away the bar runs on and the pill goes in about 5 s; the next dictation works | |

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
| 191 | Instruments > Points of Interest (subsystem tech.teensy.kotoba.dev) during 180 | "readback open" once per paste and "readback read" once after each typing pause; no readback interval between dictations | |
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
| 214 | First launch (onboarding Welcome): record fn as the shortcut | The lines under the shortcut change to "Tap fn, speak…" and "Or hold fn…"; the Try It step and the menu say fn | |

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
| 288 | In Slack, tap the chord, say "hello. Press enter.", tap the chord, and click TextEdit within 1 s | Nothing pastes into TextEdit and no Return; the pill shows “Copied. Press ⌘V to paste.”; ⌘V pastes "hello." | |
| 289 | Tap the chord to stop, and press Return at once (within about 0.1 s) | One Return, after the paste; the Return is not lost | |
| 290 | Start a long dictation, stop it, and during "Transcribing" choose menu > **Paste Last Dictation** | Nothing pastes from the menu; the new dictation pastes once | |

### Live no-sound warning (phase 2.6)

| # | Do this | Expect | Result |
|---|---|---|---|
| 266 | Choose the built-in mic. In System Settings > Sound > Input, set the input volume to 0; tap the chord and say nothing | About 2 s after the start the pill and the menu status show “No sound from the mic” with **Choose Mic…**; the pill’s help tag names the mic; recording goes on | |
| 267 | With the warning up, set the input volume back and speak | The warning goes away at your first word; the pill says “Listening” again | |
| 268 | Input volume normal, in a quiet room, tap the chord and say nothing for 15 s | No warning at any time | |
| 269 | Hold the chord with the input volume at 0 for about 1 s, then release | No warning; the dictation ends as usual | |
| 270 | Choose AirPods as the mic; tap the chord, wait 1 s, then speak; later stay silent for 10 s | No warning while the AirPods start; note if a warning shows in the silence (AirPods noise suppression) | |
| 271 | During a recording with a USB mic, unplug it | Within about 2 s the pill shows the warning (or recording moves to another mic and shows its level) | |
| 272 | Click **Choose Mic…** on the warning | Settings opens on the Microphone pane; recording goes on until you stop it | |

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
| 260 | Choose AirPods as the mic (menu), then open Settings > Microphone | “Bluetooth mic: call-quality audio” with its detail at the top of **Microphone Order**; the AirPods row says only “In use” | |
| 261 | Settings > Microphone open: plug in a USB mic, then unplug it | It shows in the **+** menu (or as connected in **Microphone Order**) at once, and goes away again; no reopen needed | |
| 262 | Settings > Microphone open: pick another mic in the menu bar **Microphone** submenu | “In use” moves to that mic in the pane at once; with AirPods, the Bluetooth warning appears | |
| 273 | AirPods as output, choose **AirPods Pro** in **Microphone** | At the foot of the submenu: a dimmed warning “Bluetooth mic: call-quality audio” with “Playback drops to call quality. Start and stop are slower, and kotoba can miss the first word.” | |
| 274 | AirPods as output, the built-in mic or a USB mic in use; play a video, then dictate | No warning in the menu; the video audio does not drop to call quality; System Settings > Sound > Input keeps its default | |
| 275 | AirPods as the system default input, no mic in your order; play a video, then dictate | kotoba records from the built-in mic; the video audio does not drop to call quality | |
| 276 | Unplug or turn off the mic in use during a recording | The recording goes on with the next mic (your order, then the system default); no crash | |

### History (phase 3; a pane of the main window since 0.3.0)

| # | Do this | Expect | Result |
|---|---|---|---|
| 291 | Menu > **History…** with no dictations yet | The main window opens at **History** with “No Dictations Yet” and your chord | |
| 292 | Dictate in Notes, then in Terminal, with History open | Each dictation appears at the top under **Today** at once, with the app’s icon and name, its length and word count | |
| 293 | Type a word from one dictation in the search field; then a word from none | Only matching rows show; then “No Results for …” | |
| 294 | In the search field: type text, press ⌘A, then ⌘C, then paste in another app | ⌘A selects the search text, ⌘C copies it (not the selected row) | |
| 295 | Select a row, press ⌘C, then paste in another app | The row’s text pastes (the cleaned text for a cleanup dictation) | |
| 296 | Right-click a cleanup dictation > **Copy Without Cleanup**; hover over the row | The raw transcript is on the clipboard; the help tag shows “Before cleanup: …” | |
| 297 | Click into a text field in another app, open History, select a row, click **Paste Again** (toolbar) | The app you were in comes to the front and the text pastes there; History and any other kotoba window stay open behind it; your clipboard comes back after about 1 s | |
| 298 | Start a dictation, then look at **Paste Again** in History while it records and transcribes | **Paste Again** is dimmed until the dictation ends | |
| 299 | Turn Wi-Fi off, dictate, turn Wi-Fi on before the network retry, then in History select the “Not transcribed” row > **Retry** | The pill shows “Saved dictation recovered”; the row changes to “Recovered” with its text | |
| 300 | Press Esc during a dictation and let Undo run out; in History select the “Canceled” row > **Retry** | The audio is sent; the row changes to “Recovered” with its text | |
| 301 | Select two rows, press Delete; click **Delete** in the dialog | “Delete 2 Dictations?”; the rows are gone, and their audio files are gone from `~/Library/Application Support/kotoba-dev/audio` | |
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
| 720 | History: select a row with text from today; click **Play** in the toolbar (or press Space) | The audio plays from your speakers; a speaker symbol shows next to the time; the button reads **Stop**; at the end both go back | |
| 721 | Play a row, then select another row and press Space; then start a dictation with the chord | The first audio stops and the second plays; the chord stops it a moment after capture starts (the first few milliseconds of the dictation can hold the audio’s end) | |
| 722 | Right-click a row with audio > **Show Audio in Finder** | A Finder window opens with the row’s .flac file selected. Rows that read “audio deleted” have no Play and no Show Audio in Finder | |
| 723 | Play a row, then close the main window | The audio stops | |
| 724 | History: right-click a pasted row > **Transcribe Again** | The row reads “Transcribing”, then shows the new text; nothing pastes and the clipboard keeps what it held. Settings > Usage counts one more request | |
| 725 | With keys for two speech models saved, right-click a pasted row > **Transcribe Again With** > the other model | The submenu lists only models other than the current one whose key is saved; the row gets that model’s text; the menu bar’s Speech Model does not change | |
| 726 | Turn Wi-Fi off; right-click a pasted row > **Transcribe Again** | “Couldn’t Transcribe Again” with **OK** says the text stays and the audio stays saved; the row keeps its text and shows no error status. Hover **Retry** on a pasted row: the tooltip says the new text replaces the old and the audio stays | |
| 727 | Select one pasted row; the toolbar button reads **Transcribe Again**; click it. Then select two pasted rows | The row is transcribed again, and it cannot be deleted until the answer comes. With two rows with text, the button reads **Retry** and is off, and the menu has no **Transcribe Again**, so one click never sends many paid requests | |
| 728 | Start **Transcribe Again** on a row, close the main window at once and open it again | The row still reads “Transcribing” until the answer, and its **Transcribe Again** and **Delete** are off | |
| 729 | Type a paragraph quickly in TextEdit with kotoba Dev running, then with it quit | Typing feels the same both ways (each key-up now goes through kotoba’s tap, as key-downs always did) | |
| 730 | Settings > General: record right ⌘ for Hands-free | It is saved. “Copy last dictation” shows **Off** with “⌃⌘C includes right ⌘, the hands-free shortcut, so Copy Last is off.” Record ⌃⌥⌘ again: Copy Last shows ⌃⌘C again | |

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
| 326 | Have dictations from more than one day ago (pasted, one “Not transcribed”, one “Canceled”); set **Keep audio** to “1 Day” | “Delete Audio Older Than 1 Day?” asks first and says how much it deletes. **Cancel** keeps the old period and deletes nothing. **Delete Audio**: the pasted rows older than a day show “audio deleted” in History and **Saved audio** gets smaller; the “Not transcribed” and “Canceled” rows still say “audio saved” and **Retry** works on them | |
| 327 | Select a row that shows “audio deleted” | Copy and Paste Again work; there is no Retry; the text is the same as before | |
| 328 | Note **Spend** in **Usage**; set **Keep audio** to “1 Day” as in row 326; look at **Usage** again | Spend, Audio, Words and Dictations do not change | |
| 329 | Click **Delete Audio Now…**, then **Cancel**; click it again, then **Delete Audio** | The dialog says how much it deletes. Cancel deletes nothing. **Delete Audio** deletes the audio of every transcribed dictation, today’s too: **Saved audio** goes to “Zero KB” and the button dims; failed, cancelled and refused rows keep theirs; every row stays in History | |
| 330 | Set **Keep audio** to “Forever”, quit kotoba, reopen it | The setting is still “Forever” and no question is asked (a longer period applies at once); no audio is deleted at launch | |
| 331 | Set **Keep audio** to “7 Days”, leave kotoba closed for more than 7 days after a dictation, then open it | Once dictation works, that dictation shows “audio deleted” in History, with no dictation needed | |
| 332 | With Wi-Fi off, dictate once (“Not transcribed”); look at the **History** section | Under the section: “Audio not yet transcribed (…) stays until you retry or delete it.” with a size; that sentence goes away once Retry sends the dictation | |
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
| 348 | With **Writing apps** on, slow the network (Network Link Conditioner, “Very Bad Network”) and dictate in Notes | After about 5 s of “Cleaning up” the raw text pastes and the pill says “Pasted without cleanup: too slow”; **Usage** later counts the cleanup’s cost | |
| 349 | Use a direct route (xAI or Azure) with no OpenRouter key; open Settings > **Modes** | “Cleanup needs your OpenRouter key” with **Add Key…**, which opens **Speech**; after you save the key and come back, the note is gone | |
| 350 | Dictate with the cleanup chord in Notes, press Esc, click into Terminal within 5 s; then History > **Retry** that row | The row names Notes, and the retried text is cleaned as prose (the Esc’s app and mode) | |

### Insights pane (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 351 | On a fresh install, open Settings > **Insights** | “No Insights Yet”; the sidebar shows **Insights** above **Usage** | |
| 352 | Dictate twice today, then open **Insights** | **Streak** “1 day”, “Including today”; **This week**, **This month** and **All time** equal the sum of the History window’s word counts; today’s bar is the last one in the chart | |
| 353 | Dictate on two days in a row; on the third day, open **Insights** before you dictate | **Streak** “2 days”, “Dictate today to keep it”; after one dictation: “3 days”, “Including today” | |
| 354 | Read a 60-word paragraph aloud at your normal pace in one dictation; look at **Words per minute** on a new install | About 60 divided by the recording’s length in minutes (a pause in the middle lowers it) | |
| 355 | Keep Settings open on **Insights** and dictate | The numbers and today’s bar change when the dictation is pasted, without leaving the pane | |
| 356 | Keep Settings open on **Insights**. Correct a pasted word in TextEdit so kotoba learns it (sparkle pill), and add one word with **Fix Last Dictation…** | **Words learned** goes up by 2 without leaving the pane: “1 from your edits · 1 from Fix Last Dictation” (or more if you had some) | |
| 357 | Delete a learned word in **Dictionary**, then reopen **Insights** | **Words learned** goes down by 1 | |
| 358 | Note the figures; in History delete all of today’s dictations; reopen **Insights** | No figure changes (Insights counts from the usage record, which deleting history keeps) | |
| 359 | Say nothing for 3 s as a dictation (“No speech heard”), then reopen **Insights** | No figure changes: a dictation with no words counts for no streak, word or speed | |

### Dictionary search (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 400 | In Settings > **Dictionary**, click a word in the list, press ⌘F, type a word | The cursor goes to **Search words** and the list filters | |
| 401 | Click in **Search words**, type a word, press ⌘F | The cursor stays in the field and the text does not change | |
| 402 | Click a toolbar item or the window title, then press ⌘F | The cursor goes to **Search words** | |
| 403 | Click **+**; in the Add sheet click **Replace it with**, press ⌘F; click **Cancel** | Nothing happens while the sheet is open; after Cancel the cursor is not in **Search words** | |
| 404 | Open **General**, press ⌘F; do the same in each other pane; then click **Dictionary** | Nothing happens in the other panes; **Dictionary** opens with the cursor not in **Search words** | |
| 405 | Press ⌘F in **Dictionary**, close Settings with ⌘W, reopen it on **Dictionary**, press ⌘F | The cursor goes to **Search words** each time | |

### Audio with no History row (phase 3)

Force quit with Activity Monitor (**Force Quit**) or `kill -9 <pid>` of kotoba Dev, never by name.

| # | Do this | Expect | Result |
|---|---|---|---|
| 420 | In kotoba Dev, tap the chord, speak for about 10 s, and force quit kotoba Dev while it records; open kotoba Dev again | Within seconds the pill says “Saved dictation recovered”; the menu lists it under **Recovered Dictations** with your words up to about the last half second; nothing is pasted | |
| 421 | Open **History** after row 420 | The dictation is there at the time you started it, with its length, its text and “Recovered”; no app name | |
| 422 | Quit kotoba Dev with ⌘Q and open it again after row 420 | Nothing new is recovered, and History has the dictation once | |
| 423 | Tap the chord and force quit kotoba Dev in the first half second of the recording; open it again | History shows a “Canceled” row with “No text”; **Delete** removes it | |
| 424 | Run `chmod 555 ~/Library/Application\ Support/kotoba-dev/audio`; in History, delete a dictation; then run `chmod 755` on the same folder | The alert “Couldn’t Delete” shows and the row stays; after `chmod 755`, **Delete** removes the row; quit and open kotoba Dev: it does not come back | |

### Discarded and empty recordings (0.2.1)

Rows 450-452 deny file removal in the audio folder of kotoba Dev with an ACL; row 452 takes it away again. Use the chord's modifiers in a shortcut of another app (hold them and press a letter key) to make kotoba Dev discard the press.

| # | Do this | Expect | Result |
|---|---|---|---|
| 450 | Run `chmod +a "everyone deny delete_child" ~/Library/Application\ Support/kotoba-dev/audio` and count its files (`ls … \| wc -l`); in TextEdit, use the chord's modifiers in a shortcut; count again | One file more (its removal failed); no pill and no History row | |
| 451 | After row 450, with the ACL still on, quit kotoba Dev with ⌘Q and open it again | No “Saved dictation recovered” pill; no new History row; the Usage pane counts no new dictation; the file is still there | |
| 452 | Run `chmod -a "everyone deny delete_child" ~/Library/Application\ Support/kotoba-dev/audio`; quit and open kotoba Dev | The file from row 450 is gone; History has no new row | |
| 453 | Select the “Canceled” row with “No text” and 0:00 from row 423 in History; open its context menu | The row says “No text”, not “No text · audio saved”; **Retry** is dimmed in the toolbar and the menu; **Delete** removes the row | |

### Windows open in front (kotoba Dev, branch fix-window-front)

Start each row with another app in front (a terminal you type in) and no kotoba window open, unless the row says otherwise. Each window must open in front of every other window and take the keys: type at once and the text goes into the kotoba window. It must not stay on top: a click in the terminal puts the terminal in front of it again.

macOS can refuse kotoba's request to become the active app. kotoba then still shows the window in front, but the keys stay in the other app until you click the window. If you see that, write the time (IST, to the second) in the Result column, so the logs can show why macOS refused.

| # | Do this | Expect | Result |
|---|---|---|---|
| 460 | Choose menu > **Settings…**; close it, click into the terminal and type; repeat 10 times | The main window opens in front all 10 times, never behind the terminal, and takes the keys | |
| 461 | Choose menu > **History…**, 5 times as in row 460 | The main window opens at History in front each time and takes the keys | |
| 462 | Dictate once, then choose menu > **Fix Last Dictation…**, 5 times as in row 460 | “Fix Last Dictation” opens in front with the last dictation each time | |
| 463 | In History, right-click a row > **Fix Dictation…** | “Fix Dictation” opens in front of History | |
| 464 | With the pill showing a button that opens a settings pane (for example **Add Key…** with no key saved), click the button | The main window opens on that pane in front. Before the click, the pill never took the keys: the text cursor stayed in the other app | |
| 465 | While setup is not complete, choose menu > **Finish Setting Up kotoba…** | The setup window opens in front | |
| 466 | Choose menu > **About kotoba Dev** | The About panel opens. It does not use the new code: write if it opens behind | |
| 467 | Open a settings pane, click into the terminal so the main window is behind it, then choose menu > **Settings…** again | The same window comes to the front on the pane you left | |
| 468 | With no kotoba window open, open kotoba Dev from Spotlight (⌘Space, type “kotoba Dev”, Return) | The main window opens in front, at the pane it showed last (Home the first time), and takes the keys | |
| 469 | As row 468, from Raycast | The main window opens in front and takes the keys | |
| 470 | With the main window open behind the terminal, open kotoba Dev from Spotlight | The main window comes in front of the terminal on the pane it showed | |
| 471 | Open the main window from the menu, then click into the terminal | The terminal comes in front of the main window; the window does not float above it | |

### Rank and cap dictionary words (phase 3)

| # | Do this | Expect | Result |
|---|---|---|---|
| 430 | In kotoba Dev, open Settings > **Dictionary** and click the star of a word | The star fills; it stays after you close and reopen Settings, and after a relaunch | |
| 431 | Edit a starred word only in case (“mastra” to “Mastra”), then edit it to another word | The case change keeps the star; the new word has none | |
| 432 | With 100 words or fewer, dictate, then look at the list | No row says “Not sent”; the footer says “The speech model gets up to 100 words as hints.” | |
| 433 | Add words until the list is over 100 (for example **Import from Wispr Flow…**); keep Settings open on **Dictionary** and dictate | The footer says “… gets 100 words as hints: starred words first, then the words you use most.” After the paste, the words left out show “Not sent”; no starred word does | |
| 434 | Over 100 words: dictate a sentence that has a word marked “Not sent”, so the pasted text has it as written; dictate again | After the second dictation, that word no longer shows “Not sent” | |
| 435 | Over 100 words: add 12 new words, then dictate | At most 10 of the new words are sent (the rest show “Not sent”); words you used before keep their place | |
| 436 | Delete a starred word and add it again | It has no star | |
| 437 | Point at a “Not sent” label, then at a star | Help tags: “Not sent with the last dictation: the list is over 100 words. Star it to always send it.” and “Star to always send it to the speech model.” | |

## Offscreen-only doubts (closed 2026-10-24)

Since 2026-10-24 `make snapshots` captures each window as the window server draws it (`App/SnapshotCapture.swift`), as the active app's key window. The doubts listed here before draw as on screen in the snapshots: the "Undo" title on the dark Canceled pill (row 54) and the pill's Retry title are light, the empty Azure endpoint's example URL (row 74) and History's “Search” placeholder are grey, and the dark sidebar labels are light. History's selected row stays grey while the sidebar has the focus, as on screen.

## Gates (after a day of use; each needs the owner's go because it reads the app database)

- `make latency RUN=1` (the release app's database; `DEV=1` for kotoba Dev's): p50 <= 1.0 s and p90 <= 1.5 s from stop to Cmd-V, for 10-20 s dictations, per model. Cleanup-chord dictations are left out.
- `make memory` (the release app in /Applications; `DEV=1` for kotoba Dev from `make build`, with the release app quit, or `PID=<pid>`): idle footprint, compared with the floor in `docs/research/memory-spike.md`. Measure once with the main window never opened, and once after it was opened and closed.

## Dev install (kotoba Dev only)

| # | Do this | Expect | Result |
|---|---|---|---|
| 360 | With kotoba Dev open, open the release kotoba from /Applications | kotoba Dev’s pill shows “Quit kotoba to dictate with kotoba Dev” for 4 s, and its menu’s first line says the same. Tap ⌃⌥⌘, speak, tap: only the release kotoba records, and the text pastes once | |
| 361 | With “Show indicator: Always” in kotoba Dev, while the release runs, point at and click kotoba Dev’s idle pill | The help tag says “Quit kotoba to dictate with kotoba Dev”; the click starts no dictation | |
| 362 | Quit the release kotoba; dictate | kotoba Dev records and pastes again; its menu says “Tap ⌃⌥⌘ to dictate” | |
| 363 | Tap ⌃⌥⌘ in kotoba Dev to start a dictation, then open the release kotoba before you stop | kotoba Dev keeps recording; a click on its pill stops it and pastes (Esc and Return no longer reach kotoba Dev). The chord now goes to the release kotoba only. A held ⌃⌥⌘ stops at once and pastes | |
| 364 | Fresh kotoba Dev setup (`defaults delete tech.teensy.kotoba.dev onboarding.completed`), go to the last step | “Open kotoba when you log in” is off | |
| 365 | Open the release kotoba first, then open kotoba Dev | kotoba Dev shows the notice of row 360 and does not dictate; quit the release kotoba, and kotoba Dev dictates | |
| 366 | While the release kotoba runs, change kotoba Dev’s chord in Settings > General; quit the release kotoba; use the new chord | kotoba Dev dictates with the new chord | |

## Fix Dictation from History

| # | Do this | Expect | Result |
|---|---|---|---|
| 410 | In History, right-click a row with text | The menu has **Fix Dictation…**. It is not there for a row with no text, or with two rows selected | |
| 411 | Click **Fix Dictation…** on an older row | The window “Fix Dictation” opens with that row’s text; **Learn** is dimmed until you change the text | |
| 412 | Change a word, click **Learn**, then **Add and Copy** | The word is in Settings > Dictionary; the fixed text is on the clipboard | |
| 413 | In the Fix window, select part of one word that the dictation got right, click **Add Selected Word** | The whole word is added (Settings > Dictionary); the footer says “Added “<word>” to your dictionary.”; the button dims while that word stays selected | |
| 414 | Put the caret in a word with no selection; then select a sentence of five words or more | **Add Selected Word** is dimmed both times | |
| 415 | In the Fix window, click into the text, press ⌘A, then ⌘C; click at the end, press ⌘V | ⌘A selects the whole text, ⌘V pastes it; no beep | |
| 416 | With **Fix Dictation…** open for one row, choose it again for the same row | The window comes to the front and keeps your edit | |
| 417 | With **Fix Dictation…** open, choose it on another row, then open menu > **Fix Last Dictation…** | The window shows the other row’s text, then the last dictation, titled “Fix Last Dictation” | |

## Paste Last shortcut (kotoba Dev)

| # | Do this | Expect | Result |
|---|---|---|---|
| 440 | Settings > General, fresh install | “Paste last dictation” shows **Off**; ⌃⌘V in TextEdit does what TextEdit does, kotoba does nothing | |
| 441 | Record ⌃⌘V for “Paste last dictation”. Dictate into TextEdit, click into another TextEdit window, press ⌃⌘V and let go | The same text pastes once into the second window, after you let go of ⌃ and ⌘ (no “⌃⌘V” beep or menu action). After 2 s, ⌘V pastes what the clipboard held before | |
| 442 | Hold ⌃⌘, press V three times (and hold V once so it repeats), then let go | The last dictation pastes once; no “v” is typed | |
| 443 | Turn off “Copy last dictation”. Hold ⌃⌘, press V, then press C before you let go | Nothing pastes; ⌃⌘C reaches the app as usual. Click Reset next to “Copy last dictation” | |
| 444 | Start a dictation, press ⌃⌘V while it records, then stop it | Nothing extra pastes; only the new dictation pastes | |
| 445 | Try to record ⌃⌥⌘V, then ⌃⌘ alone, then ⌘V | Each is refused with a red note: “⌃⌥⌘V includes ⌃⌥⌘, so it would start a dictation.”, “Add a key to ⌃⌘, for example ⌃⌘V.”, “macOS uses ⌘V. Choose another shortcut.” The shortcut stays ⌃⌘V | |
| 446 | With Paste Last on ⌃⌘V, record right ⌘ for “Dictate” | Refused: “⌃⌘V includes right ⌘, so it would start a dictation.” Dictate keeps its shortcut | |
| 447 | Click the ⓧ next to ⌃⌘V; quit and reopen kotoba Dev | It shows **Off** after the restart; ⌃⌘V reaches the app again | |

## Copy Last shortcut (kotoba Dev)

| # | Do this | Expect | Result |
|---|---|---|---|
| 710 | Settings > General, fresh install | “Copy last dictation” shows ⌃⌘C; Home > How to Dictate lists it | |
| 711 | Dictate into TextEdit. Copy other text with ⌘C. Press ⌃⌘C, then ⌘V in TextEdit | The pill says “Copied. Press ⌘V to paste.”; ⌘V pastes the dictation; no “c” is typed and no menu action runs | |
| 712 | Hold ⌃⌘ and hold C so it repeats, then let go | One copy; no “c” is typed | |
| 713 | Start a dictation, press ⌃⌘C while it records, then stop it | The pill keeps showing the recording; the new dictation pastes; after it, ⌘V pastes the earlier dictation | |
| 714 | Record ⌃⌘V for “Paste last dictation”, then try to record ⌃⌘V for “Copy last dictation” | Refused: “This is the Paste Last shortcut.” Copy Last keeps ⌃⌘C | |
| 715 | Click the ⓧ next to ⌃⌘C; quit and reopen kotoba Dev | It shows **Off** after the restart; ⌃⌘C reaches the app again | |

## Push to talk double tap (kotoba Dev)

Record ⌥ for **Push to talk** first; Hands-free stays ⌃⌥⌘.

| # | Do this | Expect | Result |
|---|---|---|---|
| 770 | Settings > General and Home | The Push to talk line reads “Hold while you speak. Let go to paste. Double-tap for hands-free.” Reset Push to talk: the line has no double tap | |
| 771 | In TextEdit tap ⌥ twice quickly, let go, speak 10 s, tap ⌥ once | The start sound and the pill come at the second tap and stay after you let go; the text pastes after the last tap. Only the second tap starts the audio | |
| 772 | Double-tap ⌥, speak, then tap ⌃⌥⌘; double-tap ⌥ again, speak, press Esc | ⌃⌥⌘ stops and pastes; Esc shows Undo, as for every dictation | |
| 773 | Tap ⌥ once; then tap ⌥ twice slowly (about half a second apart) | No sound, no pill, nothing kept (each tap is dropped). If a slow double tap that felt natural did not start, write the gap you used | |
| 774 | Tap ⌥, then quickly press ⌥⌫ (delete a word) in TextEdit | The word is deleted; no sound, no pill, no recording | |
| 775 | Tap ⌥ three times quickly | The pill shows for a moment, then goes back; no text pastes, no error | |
| 776 | Reset Push to talk (one chord for both); double-tap ⌃⌥⌘ quickly | No text pastes, no error, as before; the next tap of ⌃⌥⌘ starts a dictation | |

## Add Word from the menu (kotoba Dev)

| # | Do this | Expect | Result |
|---|---|---|---|
| 716 | With the main window closed, menu bar menu > **Add Word…** | The main window opens at Dictionary with the add sheet in front, the cursor in its first field; ⌘V pastes and ⌘A selects all in it | |
| 717 | Type a word, click **Add**; close the window; menu > **Add Word…** again | The word is in the list; the sheet opens again, empty | |
| 718 | With the main window open at History, menu > **Add Word…**; press Esc; click **History**, then **Dictionary** | The window shows Dictionary with the sheet; Esc closes it; going back to Dictionary opens no sheet | |

## Main window (0.3.0)

0.5.0 replaces rows 482-486 and 490-493 (Home, Back and Forward, Insights, Usage) with "Main window on the page system (0.5.0)" below.

One window for Home, History, Insights, Usage and the settings. Rows 480-493 use kotoba Dev with the release kotoba quit.

| # | Do this | Expect | Result |
|---|---|---|---|
| 480 | Quit kotoba Dev; delete its saved frame (`defaults delete tech.teensy.kotoba.dev "NSWindow Frame Main"`); open kotoba Dev, then menu > **Settings…** | One window, about 960 × 640, opens at **General** in front of other apps. The sidebar has Home, History, Insights and Usage, then the header “Settings” over General, Speech, Dictionary, Modes and Microphone | |
| 481 | Click **Home** | kotoba’s icon, name and version; “Ready to dictate” with a green check; **Activity** with Today, This week and Streak (hidden before your first dictation); **Recent Dictations** with up to 5 rows; **How to Dictate** with your chords as set in General | |
| 482 | Settings > General: record another Dictate shortcut; click **Home** | **How to Dictate** and the empty state show the new chord. Record the old one again | |
| 483 | On Home, click the copy icon of a row, then press ⌘V in TextEdit; click **Show All**; click **Home**, then **Show Insights**; click **Home**, then **Change Shortcuts** | The row’s text pastes; the window shows History, then Insights, then General | |
| 484 | With Home shown, dictate in TextEdit | The new dictation is the top row of **Recent Dictations** at once; Today’s words go up | |
| 485 | On Home, click **Fix Last Dictation…** | The Fix window opens with the last dictation | |
| 486 | Turn kotoba Dev off in System Settings > Privacy & Security > Accessibility; look at Home; click **Allow Accessibility…**; turn it on again | Home says “Not ready to dictate” · “kotoba can’t hear your shortcut or paste yet.”; the button opens onboarding on the Accessibility step; after the grant, Home says “Ready to dictate” within about a second | |
| 487 | Menu > **History…**, select a row, press ⌘F, type a word, then press ⌘A and ⌘V in the search field; right-click a row with text | ⌘F puts the cursor in the search field; ⌘A selects the search text and ⌘V pastes; the row menu has Copy, Paste Again, Retry (failed rows), **Fix Dictation…** and **Delete…** | |
| 488 | Click **Home**, then **General**, and open the Edit menu each time | **Find…** is dimmed in both panes | |
| 489 | Move and resize the window, close it with ⌘W, open it from **Settings…**; quit and open kotoba Dev, open it again | It opens where you left it, at the same size, both times | |
| 490 | Click **Home**, **History**, then **Speech**; press ⌘[ twice, then ⌘] once; then click **Back** and **Forward** in the toolbar | ⌘[ shows History, then Home; ⌘] shows History; the toolbar buttons do the same. **Back** is dimmed on the first pane you opened, **Forward** on the last | |
| 491 | Show **Usage**, close the window; open kotoba Dev again from Spotlight | The window opens at **Usage** | |
| 492 | Show **Insights**, quit kotoba Dev, open it, then open it again from Spotlight | The window opens at **Insights** | |
| 493 | Show **Usage**, close the window; click the pill’s **Add Key…** (no key saved) | The window opens at **Speech**, not Usage | |

## UI polish (0.3.0)

0.5.0 replaces rows 700 and 702 (Usage, Home's rows) with "Main window on the page system (0.5.0)" below.

Layout and copy pass over the main window. Snapshots cannot show the toolbar's glass text or a real resize.

| # | Do this | Expect | Result |
|---|---|---|---|
| 700 | Show **Usage** in light and in dark mode; click **Last 30 Days**, then **This Month** | The period switch sits in the middle of the toolbar; the selected segment’s title is readable in both modes; the figures change; the traffic lights and the Back/Forward buttons do not move when you switch to Usage from another pane | |
| 701 | Click **General**, then **Dictionary**; then make the window as wide as the screen and click each again | The Dictionary boxes start and end where General’s boxes do, at both widths; nothing jumps sideways | |
| 702 | On **Home**, look at a row with “No text” | It has no copy icon; its time lines up with the other rows’ times. With no dictations, **Recent Dictations** has no **Show All** | |
| 703 | General > **Shortcuts**: set a cleanup shortcut that is not the default | The ⓧ and the reset arrow sit left of the shortcut; the right edges of the Dictate, Clean up and Paste last shortcuts line up | |
| 704 | Dictionary: compare the **Learn from my edits** switch with a switch in General | Same size | |
| 705 | Menu > **Fix Last Dictation…**; edit a word, click **Learn**; then do it with a long dictation where you fix many names | The window is as tall as its text and buttons, with no empty half; after **Learn** it grows downward (its top stays) to show **Words to Add**; with many words it stops growing and the form scrolls | |
| 706 | Settings > General, scroll to the end | One **App** box holds “Open kotoba when you log in”, “Show in Dock”, “Show in menu bar” and “Check for updates automatically”; turning off one of the two icons still dims the other and shows the footer | |

## Dock app (story 35, kotoba Dev)

Rows 520-535 use kotoba Dev with the release kotoba quit, so Dev keeps its hotkey. Read the Dock switches and the launch kind with `log stream --predicate 'subsystem == "tech.teensy.kotoba.dev"'` (“Dock icon shown”, “Launched by the owner”).

| # | Do this | Expect | Result |
|---|---|---|---|
| 520 | Quit kotoba Dev. Open it from Finder (“Show in Dock” on, the default) | The blue Dev icon with the “DEV” band appears in the Dock once, with no flash. The menu bar shows kotoba Dev, File, Edit, Window, Help; kotoba Dev holds About, Settings…, Hide kotoba Dev, Hide Others, Show All and Quit kotoba Dev ⌘Q. The main window opens | |
| 521 | Settings > General: turn **Show in Dock** off | The Dock icon stays while the window is open. Close the window: the Dock icon goes, kotoba Dev stays in the menu bar, and a dictation still pastes | |
| 522 | With **Show in Dock** off: menu > **Settings…** | The Dock icon and kotoba Dev’s menus appear with the window, with no ⌘-Tab. ⌘-Tab lists kotoba Dev. Close the window: the icon goes | |
| 523 | With **Show in Dock** off and the main window open, choose **Fix Last Dictation…**, then close the main window, then the Fix window | The Dock icon stays until the Fix window closes | |
| 524 | With **Show in Dock** off and no window open: menu > **About kotoba Dev** | The About panel opens in front; no Dock icon appears | |
| 525 | With **Show in Dock** off and the main window open: turn **Show in Dock** on, then off | On: nothing changes (the icon is there). Off: the icon stays until the window closes. The window stays in front and key; ⌘A and ⌘V work in a text field | |
| 526 | Turn **Show in menu bar** off | The menu bar icon goes; **Show in Dock** is dimmed, and the footer says why. Turn it on again: the icon comes back in the same place | |
| 527 | Turn **Show in Dock** off | **Show in menu bar** is dimmed, with the footer | |
| 528 | With **Show in Dock** on and the menu bar icon off, close all windows; click the Dock icon. Minimize the window, then click the Dock icon again | The main window opens; the minimized window comes back | |
| 529 | Right-click the Dock icon. Pick another microphone. With TextEdit in front, right-click the Dock icon and choose **Paste Last Dictation** | The menu has the menu bar menu’s items and the Dock’s own Options and Quit, but no second Quit. The mic changes. The text goes into TextEdit | |
| 530 | Turn Wi-Fi off, dictate twice, turn Wi-Fi on | The Dock icon shows the badge 1, then 2; it goes when the retries are sent | |
| 531 | **Show in Dock** on, TextEdit in front: dictate with the chord, then with a click on the idle pill (“Show indicator: Always”) | Both paste into TextEdit. kotoba Dev never becomes the active app (TextEdit keeps the menu bar) | |
| 532 | Open the main window, then press ⌥⌘H in TextEdit. Dictate | The pill shows; the main window stays hidden; the text goes into TextEdit | |
| 533 | Start a recording, then choose kotoba Dev > **Quit kotoba Dev** (⌘Q) | Quit waits; the audio is in History after the next launch | |
| 534 | Turn **Open kotoba when you log in** on. Log out and in | The Dock icon is there; no window opens. The log says “Launched at login” | |
| 535 | Run the release app and kotoba Dev together | Two Dock icons: the release icon and the blue Dev icon. Dev gives way (its menu says so) | |

## Onboarding and saved keys (0.3.0)

Rows 500-514 use kotoba Dev with the release kotoba quit. A fresh setup: `defaults delete tech.teensy.kotoba.dev onboarding.completed`, remove kotoba Dev's Microphone and Accessibility grants.

| # | Do this | Expect | Result |
|---|---|---|---|
| 500 | Fresh setup; open kotoba Dev, then click through the steps | The icon and title stay at the same height on every step. Welcome shows kotoba's app icon, "Fast", "Accurate" and "Private" with one line each, the **Shortcut** box, and under it "Tap ⌃⌥⌘, speak, then tap it again." and "Or hold ⌃⌥⌘ while you speak, and let go." No key names in words | |
| 501 | Microphone step before you allow | No **Skip for Now**; **Continue** is dimmed; Return presses **Allow Microphone** | |
| 502 | Accessibility step before you allow | No **Skip for Now**; **Continue** is dimmed | |
| 503 | Key step with a key saved earlier (quit and reopen kotoba Dev on this step) | The masked key ("sk-or-v1-…" and four characters) with **Change…** and **Remove**; "Key saved" under it; no empty key field | |
| 504 | Click **Change…**, then press Esc | The field shows with the cursor in it and a **Cancel** button; Esc puts the masked key back; the saved key still works | |
| 505 | Click **Change…**, paste another key (⌘V), press Return | The new key's last four characters show; the key check runs again | |
| 506 | Click **Remove**; click **Cancel**; click **Remove** again, then **Remove** in the alert | The alert “Remove Your OpenRouter Key?” says kotoba can’t dictate until you save a new key; Cancel keeps the key; Remove shows the empty field "Paste your OpenRouter key", and the Done step says kotoba has no key | |
| 507 | With Wispr Flow installed, Continue from the key step | "Bring Your Words from Wispr Flow" shows as a step (7 dots); **Import from Wispr Flow…** shows the same alert as Settings > Dictionary with the counts | |
| 508 | Click **Import** in the alert | "Added N words and M replacements." with a checkmark; **Continue** is the default button; Settings > Dictionary lists the words | |
| 509 | Run the Wispr Flow step again after an import | "Nothing New in Wispr Flow"; **OK** shows "Your dictionary already has every word from Wispr Flow." | |
| 510 | Without Wispr Flow (rename its folder in Application Support), reopen onboarding | No Wispr Flow step; 6 dots | |
| 511 | Settings > Speech with a saved key | The masked key with **Change…** and **Remove** on the right; "Saved" or the key check under "Key" on the left | |
| 512 | Settings > Speech > **Change…**, press ⌘V, then ⌘A | The key pastes (dots), then all of it is selected; no beep | |
| 513 | Settings > Microphone > **Test Microphone** right after the onboarding grant (first run) | The bar moves for 5 s, the orange dot shows, and "Listening for 5 seconds. Speak to see the level." shows under the row; `log show --last 5m --predicate 'subsystem == "tech.teensy.kotoba.dev" AND category == "audio"'` has "The mic test started on …" | |
| 514 | Start a dictation, then click **Test Microphone** while it records | "A dictation is recording. Test again when it ends." with an orange warning; the dictation goes on | |
| 515 | Key step: save a good key; Try It step: dictate into the field | **Continue** turns prominent on each step once it is done | |
| 516 | Leave Microphone off and go to the Done step | “kotoba can’t use the microphone yet.” (the same words as Home) with **Allow Microphone**; the text above says to open kotoba from the menu bar or the Dock | |
| 517 | Settings > Speech > **Remove**, then press Esc | The same alert; Esc cancels and the key stays | |

## Audit fixes (kotoba Dev, 2026-10-17)

Rows 740-751 need real hardware or a TCC change, which a snapshot or unit test cannot make. Use kotoba Dev with the release kotoba quit. Read the log with `log show --last 5m --predicate 'subsystem == "tech.teensy.kotoba.dev"'`.

| # | Do this | Expect | Result |
|---|---|---|---|
| 740 | With kotoba Dev idle, run `sudo killall coreaudiod` in a terminal; wait 5 s, then dictate | The text pastes on the first try. The log has “Rebuilding the mic input: audio service restarted” | |
| 741 | Start a hands-free dictation, run `sudo killall coreaudiod` while you speak, keep speaking, then stop | The text has your words from after the restart too, or the pill says “No sound from the mic”; the next dictation works with no relaunch | |
| 742 | Open a second copy of kotoba Dev while one runs (`open -n` on the built app, or a copy in ~/Downloads) | The second copy quits at once with no second Dock icon and no menu bar item; the running copy shows its main window in front. The log has “Another copy of this install runs” and no “Hotkey tap started” from the second pid | |
| 743 | With the release kotoba running, open kotoba Dev | Both run (two installs); Dev gives way as in row 535 | |
| 744 | In System Settings > Privacy & Security > Accessibility, turn kotoba Dev off. Click the idle pill (“Show indicator: Always”), speak, click again | The pill says “Copied. Press ⌘V to paste.” with **Allow Pasting…**; ⌘V pastes the text. Turn kotoba Dev back on afterwards | |
| 745 | Fresh Accessibility (row 500 setup), onboarding on the Accessibility step: allow kotoba Dev in System Settings and do not click kotoba | The onboarding step turns to allowed within about 1 s while System Settings stays in front | |
| 746 | Open the main window, switch to another app for 5 min. Then run `top -l 2 -s 30 -stats pid,command,idlew -pid <kotoba Dev pid>` | `idlew` (idle wake-ups) is near 0, not about 30 per 30 s | |
| 747 | Disk full, short: quit kotoba Dev; `hdiutil create -size 30m -fs APFS -volname KotobaFull /tmp/kfull.dmg && hdiutil attach /tmp/kfull.dmg`; move `~/Library/Application Support/kotoba-dev/audio` aside and link it: `ln -s /Volumes/KotobaFull ~/Library/Application\ Support/kotoba-dev/audio`; fill it: `mkfile 29m /Volumes/KotobaFull/fill`. Open kotoba Dev and dictate 10 s | The pill says “Couldn’t save audio. Disk full?”; no request, no History row | |
| 748 | Disk full, partway: as row 747, but `mkfile 28m` (about 1 MB free), then dictate for 2 min | The first part pastes and the pill says “Pasted what was saved. Disk full?”. Afterwards remove the link, move the old `audio` folder back and `hdiutil detach /Volumes/KotobaFull` | |
| 749 | Add the input source “Dvorak - QWERTY ⌘” and select it; dictate into TextEdit. Switch back afterwards | The text pastes (no beep, no ⌘. cancel) | |
| 750 | Turn kotoba Dev off in Accessibility, wait 2 s, turn it on again (do not click kotoba). Then dictate with the chord into TextEdit | The chord starts the recording and the text pastes, with no relaunch. The log has “Hotkey tap made again after Accessibility came back” | |
| 751 | Start `kill -STOP <pid>` on a running kotoba Dev (it hangs), then open a second copy (`open -n`). Afterwards `kill -CONT <pid>` and quit one copy | If the open fails, the second copy keeps running (the log has “This copy runs instead”); it never quits with no copy left. Note what the log says for a hung copy | |

## Polish and View Changes (kotoba Dev)

Polish sends the last dictation to OpenRouter (DeepSeek V4.1 Flash, about USD 0.0004 a request). Use kotoba Dev with its own OpenRouter key and the release kotoba quit. Read the log with `log show --last 5m --predicate 'subsystem == "tech.teensy.kotoba.dev"' | grep -i polish`.

| # | Do this | Expect | Result |
|---|---|---|---|
| 800 | Settings > General > “Polish last dictation”: click **Use ⌥1** | The shortcut shows ⌥1; Home lists “Polish last dictation ⌥1” | |
| 801 | Copy some text. In TextEdit, dictate a rambling request of 30 s with a file name in it, then press ⌥1 | The pill shows “Polishing”, then “Polished” with Undo. The dictation in TextEdit is replaced by a shorter text with the same file name; ⌘V after 2 s pastes the text you copied. The log has “the text to replace is selected” | |
| 802 | Right after row 801, click **Undo** on the pill | The text from before Polish is back in TextEdit; History’s row has no “Polished” note | |
| 803 | cmux, a Claude Code prompt with some words you typed first: dictate one or two short sentences (under 800 characters, one line), touch nothing, press ⌥1 | Your typed words stay; the dictation is replaced by the polished text; “Polished” with Undo. Click Undo: the dictation is back. The log has “the text to replace is not found” | |
| 804 | Row 803 with a long dictation (over 800 characters, or Claude Code shows “[Pasted text #1 +N lines]”) | Nothing changes in the prompt; “Polished. Copied, press ⌘V”; ⌘V pastes the polished text. Then press Backspace once on a “[Pasted text …]” item and write what it deletes (the whole item, or one character): this decides a follow-up | Owner, 2026-10-17: one Backspace deletes the whole item; a second ⌘V shows the whole text. Follow-up closed: kotoba cannot see if the terminal folded the paste, so long prompts stay “Copied, press ⌘V” |
| 805 | Row 803, but press an arrow key (or click in the prompt) before ⌥1 | Nothing changes in the prompt; “Polished. Copied, press ⌘V” | |
| 814 | Plain zsh in cmux (no Claude Code): type `echo `, dictate a short sentence, touch nothing, press ⌥1 | `echo ` stays and the dictation is replaced by the polished text; nothing runs | |
| 815 | A browser text field (Chrome or Safari), dictate, touch nothing, press ⌥1 | Replaced (“Polished” with Undo), by selection or by Backspace. Write which the log names (“selected” or “not found”) | |
| 816 | In TextEdit, dictate, change one word of the pasted text, then press ⌥1 | Your edited text stays as you left it; “Polished. Copied, press ⌘V” | |
| 817 | Press ⌥1 and switch to another app at once | “Polished. Copied, press ⌘V”; ⌘V pastes the polished text; nothing pasted in either app | |
| 819 | Terminal.app with Shell > Secure Keyboard Entry on: dictate, touch nothing, press ⌥1. Turn it off afterwards | Nothing changes in the prompt; “Polished. Copied, press ⌘V” | |
| 818 | Speech model Azure MAI-Transcribe-2 (Advanced), remove the OpenRouter key, press ⌥1 | The pill says “Add your OpenRouter key” with **Add Key…**; it opens Speech with an “OpenRouter Key for Cleanup and Polish” section where the key can be pasted | |
| 806 | Menu bar menu > **Polish Last Dictation** | As row 801 | |
| 807 | Turn Wi-Fi off, press ⌥1 | “Couldn’t polish. Nothing changed.” with Retry; nothing pasted. Turn Wi-Fi on and click Retry: as row 801 | |
| 808 | Start a dictation (tap the chord), then press ⌥1 while it records | Nothing happens: the pill stays “Listening” | |
| 809 | After a polish: press the Paste Last chord, then menu > **Paste Last Without Cleanup** (cleanup dictation) | Paste Last pastes the polished text; Without Cleanup pastes the raw transcript | |
| 810 | History: right-click the polished row > **View Changes…**, in light and dark appearance | A sheet with “Transcript → Polished” (and the cleanup pairs for a cleanup dictation); removed words struck through in red, added words underlined in green; Done closes it | |
| 811 | Row 810 with VoiceOver on (⌘F5), move to the text | VoiceOver reads the text with “removed:” and “added:” before the changed words | |
| 812 | Settings > Usage after a polish | “DeepSeek V4.1 Flash · Polish model” with a cost; the dictation and word counts did not change | |
| 813 | In Slack, dictate, then ⌥1 | Write which: replaced (“Polished” with Undo) or copied (“Polished. Copied, press ⌘V”) | |

## Core audit fixes (kotoba Dev, 2026-10-17)

Rows 860-872 need real apps, a slow target or a lock, which a unit test cannot make. Use kotoba Dev with the release kotoba quit. Read the log with `log show --last 5m --predicate 'subsystem == "tech.teensy.kotoba.dev"'`.

| # | Do this | Expect | Result |
|---|---|---|---|
| 860 | Copy a word. Dictate into Terminal, Slack, Cursor, Safari and TextEdit, one each; after each, press ⌘V in a scratch note | Each app gets the transcript; each ⌘V afterwards pastes your copied word (restored right after the app read the text) | |
| 861 | Copy a word. Start a build in Xcode (or any load that makes Slack or Cursor slow), dictate into that app, and stop while it is busy | The app pastes the transcript, never your copied word, however late; then ⌘V elsewhere pastes your word | |
| 862 | With Raycast clipboard history on, copy a word, dictate into TextEdit, Slack and Terminal | The transcript pastes each time; Raycast's history has no transcript entry; ⌘V afterwards pastes your word. The log has no “An app read the transient text before the Cmd-V” | |
| 863 | Click the Finder desktop (no text field), copy a word, dictate | Nothing pastes; after 10 s the pill says “Copied. Press ⌘V to paste.”; ⌘V in TextEdit pastes the transcript; History shows it as copied | |
| 864 | Hold ⌥ (push to talk) for dictation A, release, then at once hold ⌥ again for dictation B and speak for 5 s, release | A pastes as soon as you release B's hold (not as ⌃⌥⌘V, no beep), then B pastes after it | |
| 865 | Dictate into Slack, and switch to TextEdit before the text arrives (turn Wi-Fi off for the stop, then on after the switch) | Nothing pastes into TextEdit; the pill says “Copied. Press ⌘V to paste.” | |
| 866 | Start a hands-free dictation, speak, lock the screen (⌃⌘Q); unlock | Recording stopped at the lock; nothing was typed into the lock screen; after unlock the pill says “Copied. Press ⌘V to paste.” and ⌘V pastes what you said | |
| 867 | Start a hands-free dictation, speak, close the lid (or Apple menu > Sleep); wake | The recording stopped at sleep; the text is copied, or (no network at wake) the dictation is in History as failed and is sent when the network returns | |
| 868 | Use the network link conditioner (or a slow hotspot) at about 1 Mbps up; dictate 3 min | The text pastes (no fixed 75 s cut). With the uplink cut mid-upload, the pill says “OpenRouter took too long. Saved.” or “Couldn’t reach OpenRouter. Saved.”, not both | |
| 869 | Make a dictation fail three times with a server error (owner trial only if one occurs naturally), then relaunch | The relaunch does not send it again; History **Retry** still sends it | |
| 870 | With an iPhone or iPad on the same Apple Account and Handoff on, dictate into TextEdit, then paste on the phone | The phone pastes what you copied before, never the transcript (kotoba's paste stays on this Mac) | |
| 871 | Click the Finder desktop and dictate (no app reads it), then within 10 s dictate into TextEdit | The second dictation pastes; History shows the first as copied, not pasted; ⌘V afterwards pastes your copied word | |
| 872 | Copy a word. Dictate into TextEdit, press ⌥1 (Polish), then **Undo** on the pill; after each, press ⌘V in a scratch note | Polish and its Undo replace the text in TextEdit; each ⌘V afterwards pastes your copied word | |


## Mouse button shortcut (kotoba Dev)

Use a mouse with side buttons (the owner's BSK V3 PRO). If its own software maps the side buttons to keys, turn that off for this test: kotoba must get them as mouse buttons.

| # | Do this | Expect | Result |
|---|---|---|---|
| 900 | Settings > General: click the **Push to talk** recorder, then press the back side button over it | The recorder shows “Mouse Button 4” (or the number macOS gives that button) and the note “Apps no longer get Mouse Button 4.”; while it listened, the note said “You can also press a middle or side mouse button.” | |
| 901 | In TextEdit hold the side button, speak 5 s, let go | The pill and sound come after the hold threshold; the text pastes at the release, as with ⌥ | |
| 902 | In Safari or Chrome, open a page and then a link, hold the side button 2 s to dictate into the address bar while you move the pointer over links, then press the other side button | The bound button never goes back a page; links still highlight under the pointer while it is held, and nothing is dragged or selected; the other side button still goes forward or back as before | |
| 903 | Double-click the side button quickly, speak 10 s, click it once | A double click starts hands-free; the single click stops and pastes; one click alone drops with no sound | |
| 904 | Click the **Hands-free** recorder, hold ⌥ and press the middle button. In TextEdit hold ⌥ and middle-click, speak, then ⌥-middle-click again; in Safari middle-click a link | Hands-free shows “⌥ Middle Mouse Button”; the first ⌥-middle-click starts, the second stops and pastes; a plain middle click still opens the link in a new tab | |
| 905 | Click the **Clean up** recorder and press a side button | Refused: “Only Hands-free and Push to talk can use a mouse button.”; the old shortcut stays | |
| 906 | Hold the side button and left-click within the first moment, then hold it and left-click after the pill shows | The early click drops the press (no sound); the late click changes nothing and the dictation goes on | |
| 907 | Keep the side button for Push to talk and use the mouse for an hour of normal work (scrolling, middle clicks, middle-button drags such as panning, the other side button); then reset Push to talk | No click or drag feels slower than with the shortcut reset; Activity Monitor shows kotoba Dev's CPU at idle as before | |
| 908 | Hold the side button to dictate in TextEdit, press and let go of ⌥ while you speak, then let go of the button | The dictation goes on through ⌥ and pastes at the button's release (kotoba reads the button as down) | |
| 909 | With the side button for Push to talk, open Settings > General, hold the side button over the window and, while you hold it, click Reset on Push to talk; let go, then tap ⌃⌥⌘ and type a few keys | ⌃⌥⌘ starts and stops a dictation as usual; no key is lost or stuck | |

## Low audit fixes (kotoba Dev, 2026-10-17)

Rows 930-939 need a real mic, real source apps or a quit, which a unit test cannot make. Use kotoba Dev with the release kotoba quit.

| # | Do this | Expect | Result |
|---|---|---|---|
| 930 | Start a hands-free dictation on AirPods, speak, and while you speak start a FaceTime call (the mic changes rate), then stop | The stop takes under half a second; the text has what you said before the call. Repeat with Esc during the call and **Undo** on the pill: the recording goes on with no click or pitch jump | |
| 931 | Copy styled text from Pages or Safari (bold and a link). Dictate into TextEdit, then press ⌘V in a rich TextEdit note | The styled text pastes with its bold and link, not as plain text | |
| 932 | Copy a photo in Photos (or a file in Finder). Dictate into TextEdit, then press ⌘V in Finder or a Mail draft | The photo (or file) pastes as before the dictation; the dictation pastes at once, with no wait for the photo | |
| 933 | Turn Wi-Fi to a slow hotspot, dictate 30 s, and press ⌘Q within a second of the stop | kotoba quits within about 3 s; at the next launch, the dictation is in History as pasted (or copied), not sent again into Recovered | |
| 934 | Esc a dictation at once after the start tap (before you speak), and let the Undo window close | No new row of 0:00 in History | |
| 935 | Record from a USB mic. Start a hands-free dictation, speak, and while you speak change the mic's rate in Audio MIDI Setup (48 kHz to 44.1 kHz), keep speaking, then stop | The text has the words from before and after the rate change; the pill does not say “No sound from the mic”. The log may show “Rebuilding the mic input: the mic finished its change” | |
| 936 | Start a hands-free dictation, then turn kotoba Dev off in System Settings > Privacy & Security > Microphone while it records | Within about 2 s the pill says “Microphone access is off” with **Open System Settings…** (no level meter), not “No sound from the mic”. Stop: no “Transcribing”, no History row, and the pill says “Microphone access is off” again. Turn access back on before the next row | |
| 937 | Select a word in Settings (the key field or the Dictionary pane) and press ⌘C, switch to TextEdit, dictate; then run `log show --last 2m --predicate 'process == "kotoba Dev"' \| grep "background thread"` | The dictation pastes, ⌘V afterwards pastes the copied word, and the log has no “synchronous promise fulfillment requested from a background thread” | |
| 938 | Join a Wi-Fi with a captive portal (a hotel or café login page) without logging in, and dictate | The pill says “Secure connection blocked. Saved.” with **Retry** (or “Couldn’t reach …” if the portal drops the connection); after you log in, **Retry** transcribes it | |
| 939 | Make a dictation fail (Wi-Fi off), quit kotoba Dev, delete its file in `~/Library/Application Support/kotoba-dev/` (the newest .flac), relaunch with Wi-Fi on | The launch sends nothing for it; History shows it as “Audio missing”; the Dock badge does not count it | |

## Spoken line breaks (kotoba Dev, 2026-10-17)

Rows 940-945 need real speech, a real speech model and real target apps. Turn on Settings > General > **Start a new line when you say “new line”** first, and quit the release kotoba.

| # | Do this | Expect | Result |
|---|---|---|---|
| 940 | In TextEdit dictate “Buy milk new line buy eggs new paragraph that’s all” | Three lines: “Buy milk”, “Buy eggs”, an empty line, then “That’s all” (or the same with the speech model’s own punctuation); no space at a line end or start; History shows the same text | |
| 941 | In TextEdit dictate “Add a new line after the header” | The words paste as said, with no line break | |
| 942 | Dictate with the cleanup shortcut into Slack (Writing mode): “Hi Ravi new paragraph the report is late new line please send it today” | The cleaned text keeps the empty line and the line break; the words “new line” and “new paragraph” are not in it | |
| 943 | In Terminal at a zsh prompt, dictate “echo one new line echo two” | Two lines sit in the prompt and nothing runs until you press Return. The second line starts with “echo”, not “Echo” (Terminal is in Code mode) | |
| 944 | In Terminal, run `cat` (no bracketed paste), dictate “one new line two”, then press ⌃C | “one” runs as a line in `cat` (it echoes back): the known limit for programs without bracketed paste. kotoba sent no Return key: the break is a character in the paste | |
| 945 | Turn the setting off and dictate “First new line second” | The words paste as said | |

## Memory after use (kotoba Dev, 2026-10-17)

Rows 946-951 need the app launched by Launch Services (Finder, the Dock or a login), not from Terminal: only then does it get the allocator's space-efficient mode (`LSEnvironment` in `project.yml`). Build with `make build`, quit the release kotoba, and open kotoba Dev from Finder. Each `make memory DEV=1` reads the running kotoba Dev. Before: release 0.4.1 after the same use read 68 MB (peak 181 MB).

| # | Do this | Expect | Result |
|---|---|---|---|
| 946 | Open kotoba Dev from Finder, wait 1 min with no window open and no dictation, then run `make memory DEV=1` | “allocator: space efficient”; footprint at or under 15 MB (0.4.1 after launch: 15.9 MB) | |
| 947 | With Settings > General > **Open kotoba when you log in** on, log out and in (or restart); wait 1 min, then run `make memory DEV=1` | “allocator: space efficient”: the login launch also gets the mode | |
| 948 | Use kotoba Dev for 20 min: 10 dictations, open the window, show every pane (scroll History, open Insights, Usage and General), close the window, wait 1 min, then run `make memory DEV=1` | Footprint about 40-50 MB, peak about 160 MB (0.4.1: 68 MB, peak 181 MB) | |
| 949 | After row 948, do 20 more dictations without opening the window, wait 1 min, run `make memory DEV=1` again | Footprint within 3 MB of row 948: dictations do not add memory | |
| 950 | Open the window on General, wait 30 s, and read kotoba Dev's Memory in Activity Monitor; close the window and read it again after 30 s | Note both numbers in Result (the window's graphics peak on screen is not measured yet) | |
| 951 | After rows 948-949, run `make latency-log DEV=1 LAST=1h` | p50 at or under 1.0 s and p90 at or under 1.5 s, as before the change | |

## Capture lifecycle in KotobaCore (kotoba Dev, 2026-10-19)

The mic input's lifecycle moved from App/ into KotobaCore's `AudioCapture` behind the `CaptureHardware` port; its tests run on a fake. These rows prove the CoreAudio adapter still does what the tests assume. After each row, `log show --last 5m --predicate 'process == "kotoba Dev" AND category == "audio"'` shows each “Recording from …” and “Rebuilding the mic input: …”.

| # | Do this | Expect | Result |
|---|---|---|---|
| 980 | Built-in mic in use, AirPods connected and in your order below it. Dictate. Then move AirPods to the top of **Microphone Order**, dictate, move the built-in mic back to the top, dictate | Each dictation pastes; the menu's **Microphone** check and the pane's “In use” follow the order; the second dictation records from AirPods, the third from the built-in mic | |
| 981 | AirPods first in your order. Start a hands-free dictation, speak, take both AirPods out (they disconnect) while you speak, keep speaking, then stop | The recording goes on with the built-in mic; the text has the words from before and after; no crash; the log shows “Rebuilding the mic input: audio route changed” | |
| 982 | USB mic first in your order. Start a dictation, speak, unplug the USB mic, keep speaking, plug it back in, keep speaking, then stop | The recording moves to the next mic at the unplug and stays on it (the USB mic is used again from the next dictation); the text has all the words | |
| 983 | Only the built-in mic in your order. Start a dictation and, while it records, connect AirPods (they become the system default) | The recording keeps the built-in mic; the next dictation also uses the built-in mic (your order wins) | |
| 984 | AirPods first in your order. Start a dictation on AirPods, speak, and start a FaceTime call while you speak (the headset changes to the call format), then stop | As row 930: the stop takes under half a second, the text has what you said before the call, no “No sound from the mic” | |
| 985 | Start a dictation, press Esc, unplug the mic in use (or take out AirPods) within the 5 s, then click **Undo** | The recording goes on with the next mic; the text after Undo is at normal pitch | |
| 986 | Run `sudo killall coreaudiod`, wait 5 s, then dictate | The dictation records and pastes with no “No microphone found”; the log shows “Rebuilding the mic input: audio service restarted” | |

### One capture at a time, and quit waits for billed answers (2026-10-20)

A press, an Undo, an absence and quit take turns (`DictationPipeline.inTurn`), and quit waits for billed work (`PendingWork.bill`). Only a real run proves the timing.

| # | Do this | Expect | Result |
|---|---|---|---|
| 987 | Start a dictation, speak, press Esc, then click **Undo** on the pill and press the chord at once (the same moment) | One dictation pastes with the words from before and after Esc; History shows one row; no second recording starts | |
| 988 | Start a dictation, speak, press Esc, click **Undo** and press ⌘Q at once | kotoba quits; at the next launch the dictation is in Recovered (sent once) | |
| 989 | In History, choose **Transcribe Again** on a dictation and press ⌘Q at once | kotoba quits within about 3 s; at the next launch the row has the new text and Insights counts the second answer | |
| 990 | AirPods as the system default, none in your order. Dictate (built-in mic). Then, if you can make the built-in mic fail to open (for example, another app holds it exclusively), dictate again | The first dictation records on the built-in mic. With the built-in mic not opening, the pill says no mic opened; the AirPods never switch to call quality | |

## Main window on the page system (0.5.0, kotoba Dev)

Home, Activity and the window shell on the 0.5.0 page system (docs/research/ui-redesign.md). Snapshots cannot show a real click, the sidebar on screen, a resize or a paste into another app.

| # | Do this | Expect | Result |
|---|---|---|---|
| 1100 | Open the window (menu > **Open kotoba Dev…**). Look at the sidebar; drag the window wider until it stops | The sidebar starts with the kotoba Dev icon and name; it is as wide as System Settings' sidebar (215 pt). The window stops growing at about 1,055 pt; the page column stays in the middle with no wide blank side | |
| 1101 | System Settings > Appearance > Sidebar icon size: Small, then Large; look at the kotoba sidebar each time | The tiles and the app icon follow the size; no symbol is cut off or blurred | |
| 1102 | Click **Home**, **History**, **Activity**, **Shortcuts**, **Speech**, **Dictionary**, **Cleanup**, **Microphone**, **General** in turn | The title bar, traffic lights and sidebar rows do not move; no page has a toolbar | |
| 1103 | With "Prefer tabs: Always" (System Settings > Desktop & Dock), open the window, then Menu > **Fix Last Dictation…** | Two separate windows, no tabs | |
| 1104 | Dictate in TextEdit, then open Home; click **Paste Again** on the Last Dictation card | TextEdit comes to the front and the text pastes there once | |
| 1105 | On Home's Last Dictation card, click **Copy**, then press ⌘V in TextEdit; click **Fix…** | The text pastes; the Fix window opens on the last dictation | |
| 1106 | Start a hands-free dictation, and while it records look at Home's Last Dictation card | **Paste Again** is dimmed until the dictation ends | |
| 1107 | On Home, click the today card; click **Home**, then **Show All** | The window shows Activity, then History | |
| 1108 | A new install with a key but no dictation (or a test user): on Home, click **Try It…** | Onboarding opens on the Try It step | |
| 1109 | Turn kotoba Dev off in System Settings > Privacy & Security > Accessibility; look at Home; click **Allow Accessibility…**; turn it on again | Home's first card says “Not ready to dictate” with the button; it opens onboarding on the Allow Access step; after the grant the today card comes back within about a second | |
| 1110 | On Activity, click **Month**, then **Week**; dictate in TextEdit with Activity shown | The chart changes period; today's bar and the figures go up after the dictation | |
| 1111 | On Activity, click **Advanced…**, then **Done** | A sheet lists this month's spend by model; Done closes it | |
| 1112 | Show **Activity**, close the window; open kotoba Dev again from Spotlight. Then with 0.4 having left the window on Insights or Usage, open it | It opens at Activity; a pane saved as Insights or Usage opens Activity too | |
| 1170 | On **Speech**, click the **Grok via OpenRouter** row, dictate into TextEdit, then click **MAI-Transcribe-2 via OpenRouter** and dictate again | The check moves to the clicked row; each dictation is transcribed (History shows both); VoiceOver reads the checked row as selected | |
| 1171 | On **Speech**, click **Advanced…**, click **MAI-Transcribe-2 via Azure**, click **Done**; then **Add Endpoint…**, type “abc” in the endpoint field, then a real https endpoint, and click **Done** without pressing Return | The page shows the Azure row checked, an Azure Key group and “Azure needs your endpoint”; “abc” shows the red hint; after Done the endpoint is saved (open **Advanced…** again: it is there) and the warning row goes | |
| 1172 | On **Speech** with no key saved, paste a key with ⌘V, select it with ⌘A, click **Save**; then **Change…**, **Cancel**; then **Remove** and confirm | ⌘V and ⌘A work in the field; the masked key shows with “Key works”; Cancel keeps the key; Remove asks first, then shows the empty field | |
| 1173 | On **Dictionary**, choose Edit > Find… (⌘F), type part of a word, then a word that is not there; clear the field | The cursor goes into the page's search field; the list narrows; “No words match …” shows; clearing brings every word back | |
| 1174 | On **Dictionary**, click **+**, type a word (⌘V and ⌘A work), click **Add**; double-click a row, change it, **Save**; Control-click a row > **Edit…**; select two rows and press Delete | Add Word and Edit Word sheets open and save; the context menu edits; Delete removes both rows | |
| 1175 | On **Dictionary**, move the pointer over a word, click its star; move the pointer away; click the star again | The star shows on hover; a starred word keeps its yellow star without hover; the footer says how many words kotoba sends as hints; there is no Advanced… button | |
| 1176 | With word suggestions waiting, look at the Dictionary sidebar row, then on **Dictionary** click **Add** on one, the × on another, then **Add All** | The sidebar row shows the count; each suggestion leaves the list; the count goes down to none | |
| 1177 | On **Cleanup**, turn on **Every dictation in writing apps**, dictate “um so I think, uh, yes” into Notes; turn it off and dictate again | With it on the pasted text has no “um” or “uh”; with it off the text is as spoken | |
| 1178 | On **Cleanup**, click **+** > a recent app, change its style to Code, select it and click **−**; click **+** > **Choose App…** and pick an app; with no Rewrite shortcut, click **Set Shortcut…** | Each app joins the list with a style and leaves it; the open panel adds the app; Set Shortcut… opens Shortcuts | |
| 1179 | On **Cleanup**, click **Advanced…**, click **Claude Haiku 5.5**, **Done**; dictate with the **Dictate with cleanup** shortcut; open **Activity** > **Advanced…** | The check moves to Claude Haiku 5.5; this month's spend lists it as the cleanup model | |
| 1180 | Remove the OpenRouter key on **Speech**, open **Cleanup**, click **Add Key…** | Cleanup's first group says it needs the OpenRouter key; Add Key… opens Speech | |

## Status menu, onboarding and Fix Last Dictation on the page system (0.5.0, kotoba Dev)

The status menu, the five onboarding steps and the Fix Last Dictation window (docs/research/ui-redesign.md). Snapshots cannot show a system prompt, a grant, a real menu or a window in front of another app. The owner does every TCC step. A fresh setup: `defaults delete tech.teensy.kotoba.dev onboarding.completed`, remove kotoba Dev's Microphone and Accessibility grants.

| # | Do this | Expect | Result |
|---|---|---|---|
| 1130 | Open the menu bar menu before the first dictation, then after one with cleanup; hold ⌥ while the menu is open | Before: “Hands-free · Press ⌃⌥⌘ to start and stop” and “Push to talk · Hold ⌃⌥⌘ while you speak” in grey, Microphone, **Open kotoba Dev…**, Quit. After: a “Last Dictation” header with **Paste**, **Copy** (⌃⌘C on the right), **Rewrite** (only with an OpenRouter key saved) and **Fix…**; with ⌥ held, Paste reads **Paste Without Cleanup** and pastes the text before cleanup. No Speech Model, Add Word…, word suggestions, History…, Settings… or About | |
| 1131 | With TextEdit in front, menu > **Open kotoba Dev…**; close the window; menu > **Paste Last Dictation** | The window opens in front on the page it showed last; the paste lands in TextEdit | |
| 1132 | With two mics connected, menu > **Microphone** > the second mic; dictate; open the Microphone page | The dictation records from the picked mic; it is first in the Microphone page's list | |
| 1133 | Fresh setup, open kotoba Dev. On Welcome, look at the keys; click **Get Started** | Welcome shows the app icon, “Welcome to kotoba” and its line centred, three rows (Fast, Accurate, Private), and Hands-free and Push to talk with keycaps that have “control”, “option”, “command” under them, evenly spaced. Get Started opens Allow Access with 2 of 5 dots | |
| 1134 | On Allow Access, click the Microphone row's **Allow…**; the owner clicks Allow in the system prompt | The prompt shows; the row turns to “Allowed”; the Accessibility row's **Allow…** becomes the default button (in the accent colour); the window stays on Allow Access and Continue stays dimmed | |
| 1135 | Click the Accessibility row's **Allow…**, then **Allow…** again; the owner turns kotoba Dev on in System Settings | The first click shows the system prompt, the second opens System Settings > Accessibility; the row turns to “Allowed” within about a second; Continue becomes the default button and Return presses it | |
| 1136 | Close onboarding on Allow Access, quit and reopen kotoba Dev. Then quit, run `defaults write tech.teensy.kotoba.dev onboarding.step microphone` (a 0.4 step), reopen | It opens on Allow Access both times | |
| 1137 | On the key step, paste a key with ⌘V, select it with ⌘A first; on Try It, dictate, then ⌘A and ⌘V in the field | ⌘A and ⌘V work in both fields; the key row shows the masked key and “Key works” under its name; Try It shows “It works.” | |
| 1138 | With Wispr Flow installed, go to Done; click **Import…**, then **Import** | Done has a “Wispr Flow dictionary” row; the alert lists what it adds; the row then says what it added and “Imported”. Without Wispr Flow (rename its folder in Application Support) there is no row | |
| 1139 | Turn kotoba Dev off in Accessibility; click the pill's **Allow Pasting…**, then Home's **Allow Accessibility…** | Each opens onboarding on Allow Access | |
| 1140 | With TextEdit in front, menu > **Fix…** (under Last Dictation); select a word, click **Add Selected Word** | The window opens in front of TextEdit, as wide as in 0.4; a green check line says “Added “word” to your dictionary.” | |
| 1141 | Fresh kotoba Dev setup, go to Done and wait; then turn **Open at login** on and off | No error shows before you touch the switch. If macOS refuses the change, a grey footnote under the group says so, with an **Open Login Items…** link; no error row inside the group | |
| 1142 | On Done, click **Done** | Onboarding closes and the kotoba Dev window opens in front on Home | |
| 1143 | Open onboarding with Wispr Flow installed, then with its folder in Application Support renamed | With Wispr Flow, Welcome has a fourth row “From Wispr Flow”; without it, three rows | |
| 1144 | On the key step with no key saved, click **Get a Key at OpenRouter…** (under the key’s name), then **Open Speech Settings…** (xAI or Azure) | The first opens OpenRouter’s keys page in the browser; the second opens the window on Speech with its Advanced… sheet | |
| 1145 | In Shortcuts, set Paste Last to ⌃⌥V and Rewrite Last to ⌥1; dictate with cleanup; open the menu; with the menu open press ⌃⌘C once | Paste shows ⌃⌥V and Rewrite ⌥1 on the right; Paste Without Cleanup is an item of its own; ⌃⌘C copies the last dictation once | |

## Shortcuts, Microphone and General on the page system (0.5.0, kotoba Dev)

Shortcut recorders, the spoken commands, the Bluetooth switch and the Microphone page's live row status. Snapshots cannot press a chord, plug a mic or read VoiceOver.

| # | Do this | Expect | Result |
|---|---|---|---|
| 1190 | On **Shortcuts**, click the Hands-free recorder, press ⌃⌥⇧⌘ (refused) then ⌥⌘; turn VoiceOver on and move through the Hands-free row | The refusal shows under the recorder and the button keeps its width while it listens; ⌥⌘ is saved and dictates; VoiceOver reads the title, the line under it and the recorder, and reaches Turn Off and Reset on a row that has them | |
| 1191 | On **Shortcuts**, turn on “Start a new line when you say “new line””, dictate “one new line two” into TextEdit | Two lines are pasted | |
| 1192 | Mac with a built-in mic, AirPods connected and chosen as the system input, kotoba's list empty; dictate. Then turn off “Use Bluetooth microphones only from the list” on **Microphone** and dictate again | First dictation records from the built-in mic (AirPods playback stays at full quality); after the switch the AirPods record and the page shows the Bluetooth warning, with no restart | |
| 1193 | On **Microphone** with a USB mic first in the list and in use, unplug it, then plug it back in | Its row goes from “In use” to “Not connected” and the next mic shows “In use” within about a second; plugging it back gives “In use” back to it | |
| 1194 | Mac with no built-in mic (or the built-in mic removed from the list and unavailable), AirPods as the system input, kotoba's list empty, switch on; dictate, click **Choose Mic…**, add AirPods with +, dictate again | The pill says “Not in mic list: AirPods Pro” with **Choose Mic…**; it opens Microphone; after the add the next dictation records from the AirPods | |
| 1198 | Open **Microphone** with the built-in mic in use; pick the built-in mic in the menu bar's Microphone menu; then drag another mic on the page | The built-in mic moves to the top of the list at once; the drag keeps the menu's pick | |
| 1199 | Mac with no built-in mic running 0.4.6 with AirPods as the system input: put the AirPods in their case, update to 0.5.0 and let it relaunch; take the AirPods out and dictate. Then open **Microphone** | The dictation records from the AirPods; “Use Bluetooth mics only from the list” is off and the list is as 0.4 left it | |

## History on the page system (0.5.0, kotoba Dev)

| # | Do this | Expect | Result |
|---|---|---|---|
| 1150 | On **History**, choose Edit > Find… (⌘F) and type a word from one dictation; then type a word that no dictation has | The cursor goes to the search field above the list; only matching rows stay and the field keeps the cursor while you type; then one row says “No results for “<word>”” and the field stays | |
| 1151 | On History, click a row, press ↓ and ↑, press Space, Space again; ⇧-click a second row and press ⌘C, then ⌘V in TextEdit | The selection moves with the arrows; Space plays and stops the audio (a speaker symbol by the time); both texts paste, oldest first, a blank line between | |
| 1152 | With TextEdit the last app you were in, Control-click a History row and choose **Paste Again** | TextEdit comes to the front and the text is pasted; the menu has Copy, Paste Again, Fix…, Transcribe Again (or Retry), Play Audio, Show Audio in Finder and Delete… | |
| 1153 | Select two rows and press Delete; confirm | “Delete 2 Dictations?” asks first; both rows go, with their audio | |
| 1154 | Control-click a row with text and audio; choose **Show Audio in Finder**; then **Transcribe Again With** > another speech model (paid, under $0.01) | Finder shows the audio file selected; the row reads “Transcribing”, then the new text | |
| 1155 | Control-click a cleaned or rewritten row, choose **View Changes…**, click each comparison, then **Done** | Removed words are struck through, added words underlined; the count under the text changes with the comparison | |
| 1156 | On History, choose a shorter **Keep audio** period than now, with older audio saved; then click **Delete Audio Now…** next to it and confirm | Both ask first and say the size; after Delete the size under “Keep audio” goes down; General has no audio rows | |
| 1157 | With more than 200 dictations, scroll History to the end | The next rows load as the end comes into view, with no click | |
| 1158 | Look at History and then at Home, Activity and General in turn | The title bar keeps one height on every page; History has no toolbar | |
| 1159 | On History, select a row with text and audio; open the menu bar's **Dictation** menu; choose **Show Audio in Finder** (⇧⌘R); select a row and press ⌘⌫ | The menu has Copy Without Cleanup, Paste Again, Fix…, Retry, Transcribe Again, Transcribe Again With, Play Audio, View Changes…, Show Audio in Finder and Delete…, each dimmed when it cannot apply; Finder shows the file; ⌘⌫ asks to delete. On Home the menu's items are dimmed | |
| 1160 | On History, select a row with audio, then click in the search field and type “see you” | The space goes into the field; no audio plays | |
| 1161 | On History, play a row's audio (Space), then type a search that leaves that row out | The audio stops when the row goes | |
| 1162 | On History, scroll down several days, then press ⌘F and type | The cursor goes to the search field at the top, which stayed in view | |

## Page system: sheets and list pages (0.5.0, kotoba Dev)

| # | Do this | Expect | Result |
|---|---|---|---|
| 1195 | Open Activity > **Advanced…** (a sheet with Done only) and press Esc; open it again and press Return | Esc closes the sheet; Return closes it too (Done) | |
| 1196 | Open Dictionary > Add Word (a sheet with Cancel and Add), type a word, press Esc | The sheet closes and nothing is added | |
| 1197 | On History, type in the search field, then scroll the list down and up, and wait for a new dictation to arrive | The search field stays above the rows and keeps the cursor; the title bar has one tint across the whole page in light and dark | |

## The 0.5.0 pill (kotoba Dev)

One glass capsule that changes shape (docs/research/ui-redesign.md, "Pill"). Snapshots draw each look; these rows need a real chord, a real pointer and a real mic. Dictate in any text field.

| # | Do this | Expect | Result |
|---|---|---|---|
| 1200 | **General** > Indicator > Show: **Always** | A thin glass bar at the bottom center | |
| 1201 | Point at the bar, then move the pointer away | It grows to “Dictate ⌃ ⌥ ⌘”; away, the thin bar again | |
| 1202 | Click the bar | A recording starts: the hands-free pill (×, bars, Stop) | |
| 1203 | Press ⌃⌥⌘ and let go, speak, click **Stop** | The hands-free pill with × and Stop; after Stop the bars sweep, a green check shows, then the bar; the text pastes | |
| 1204 | Start again and click **×**; click **Undo**; cancel once more and wait | “Canceled” with Undo; Undo goes on recording; untouched, the pill goes back to idle after about 5 s | |
| 1205 | Hold ⌃⌥⌘ while you speak, let go | Bars only while held (push to talk); after the release the sweep, the check and the paste | |
| 1206 | Point at a message (for example “Canceled”), then move away | It stays while the pointer is on it and goes after you move away | |
| 1207 | Drag the pill to the left edge, then to the right edge; at each edge repeat rows 1203 and 1205 | It stands vertical at the edge, with the same looks turned 90° | |
| 1208 | With Always on, change the indicator's place in General while the bar shows | The bar moves to the middle of that edge, not near its bottom | |
| 1209 | During a recording, drag the pill to another place and drop it | It stays at the new place, centred there | |
| 1210 | At a side edge, click and point in the clear area next to the pill | The clicks and the pointer reach the app below | |
| 1211 | In a hands-free recording, mute the mic | Orange dots, “No sound from the mic”, Choose Mic… and Stop; × is gone (Esc still cancels) | |
| 1212 | Dictate, fix a word in the pasted text, then dictate again | “Added “word”” with Undo shows after the second paste and stays for its time; the check does not replace it | |
| 1213 | Dictate for more than 10 minutes; open the menu bar menu | From 10:00 the time shows after the bars and counts up once a second; the menu's status line says “Still recording · 10 minutes” | |
