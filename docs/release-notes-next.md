## kotoba 0.5.0

kotoba 0.5.0 redesigns the whole app. The indicator is now a small glass pill, the window is rebuilt in the style of System Settings, and the pages, the menu and the messages are rewritten to say what happens next. Under the new look, cleanup is faster, MAI-Transcribe-2 drops “um” and “uh” as it transcribes, and five bugs from 0.4.6 are fixed.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/shiroyasha9/kotoba/main/docs/images/showcase-home-dark.png">
    <img src="https://raw.githubusercontent.com/shiroyasha9/kotoba/main/docs/images/showcase-home-light.png" alt="The kotoba window on Home: today’s words with the week’s bars, the time saved and the streak, the keys for hands-free and push to talk, and the last dictation with Fix…, Copy and Paste Again">
  </picture>
</p>

### Highlights

- A new glass pill that changes shape as you dictate, and that you can drag to the bottom or to either side of the screen.
- A new window: Home, History and Activity at the top, then Shortcuts, Speech, Dictionary, Cleanup, Microphone and General.
- Cleanup takes about half as long with its new default model.
- Without cleanup, MAI-Transcribe-2 now leaves out “um”, “uh”, repeated words and false starts.
- Bluetooth microphones stay out unless you add them to your list, so AirPods no longer drop you to call quality.

### The pill

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/shiroyasha9/kotoba/main/docs/images/showcase-pills-dark.png">
    <img src="https://raw.githubusercontent.com/shiroyasha9/kotoba/main/docs/images/showcase-pills-light.png" width="400" alt="The kotoba pill in four looks: recording, with the voice level bars, Cancel and Stop; three dots while the text is on its way; done, with a check; and the notice that kotoba added Kubernetes to the dictionary, with Undo">
  </picture>
</p>

- One small glass capsule replaces the old indicator. It grows out of a thin bar when you start and goes back into it at the end.
- Push to talk shows bars while you hold the shortcut. Hands-free adds Cancel (×) and Stop. A small wand before the bars means the dictation will be cleaned up.
- The bars move with your voice, all at once, in kotoba’s coral. When you speak loudly, they glow.
- While your text is on its way, the bars gather into three dots with a soft coral light moving under them. A check draws itself when the text pastes.
- Words show only when you need to know something or can act on it: an error with its fix, “No sound from the mic”, Undo, an added word, and the time after 10 minutes.
- Drag the pill to move it. While you drag, faint outlines show each place it can go, and it snaps to the nearest one when you let go. General > Indicator > Position follows your drop.
- With General > Indicator > Show set to Always, the pill waits as a thin bar. Point at it to see “Dictate” and your Hands-free shortcut, and click it to start a dictation.
- With Reduce Motion on, the pill fades in place, the dots hold still, and it moves to a new place at once.
- The pill uses no more memory or CPU than the old indicator, and does no work while it waits.

### The window and its pages

- The window follows System Settings. The sidebar starts with kotoba’s icon and name, and each page opens with one line on what it does. The window’s title shows the page you are on.
- Charts and the pill’s bars use kotoba’s coral. Selection, buttons and switches keep your accent colour, and with the Multicolor accent, kotoba uses its coral there too.
- Home shows today’s words, the time saved and your streak, with the last 7 days as bars. Click the card to open Activity. Below are your shortcuts, your last dictation with Fix…, Copy and Paste Again, and the 4 dictations before it, each with its day (“Yesterday”, “Tuesday”). When the last dictation waits for a retry, Retry is its only button.
- Activity replaces Insights and Usage. It shows your words per day for the week or the month, highlights, your top apps this month, and this month’s spend in cents. Advanced… lists spend by model to the fraction of a cent. Usage’s Last 30 Days view is gone.
- History has its search in the window’s toolbar (⌘F), and Keep audio with Delete Audio Now…, which were in General. Every action for a dictation is in its Control-click menu and in the new Dictation menu in the menu bar: ⇧⌘R shows the audio in Finder, ⌘⌫ deletes. Audio that is playing stops when a search or a delete takes its row away.
- Shortcuts is a new page with every shortcut and how it works, Esc, and the “press enter” and “new line” voice commands, which were in General.
- Speech keeps the settings you rarely touch in an Advanced… sheet: the xAI and Azure routes, the Azure endpoint, other keys, the Grok switch and Keep filler words. A key that works shows “Connected”. Before you remove a key, kotoba says what stops without it.
- Dictionary has its search, Import from Wispr Flow… and + in the toolbar. Star a word on its row; the line under the list says how many words go as hints. Delete or the Control-click menu removes a word. Word suggestions show as a count next to Dictionary in the sidebar, and the note on what “Learn from edits” reads now sits beside its switch.
- Cleanup replaces Modes. Cleanup, Rewrite and App styles share one page, each with an example that strikes through the words it drops. Polish is now called Rewrite, and modes are now app styles. The cleanup model is in Cleanup > Advanced….
- Microphone says how kotoba picks a mic: the first connected one in your list, then the next when it is unplugged. Each mic shows whether it is in use or not connected, and a mic you pick in the menu bar menu moves to the top of the list.
- General holds sounds, the indicator, login, the Dock and menu bar, and updates. If macOS will not let kotoba open at login, a note under the switch links to Login Items & Extensions.
- The window has a maximum width, as System Settings does. Esc closes a sheet that has only a Done button.
- VoiceOver reads each shortcut’s keys by name, for example “control option command”.

### Setup

- Setup has 5 steps: Welcome, Allow Access (Microphone and Accessibility, each with its own Allow… button), your key, Try It and Done.
- Try It shows both ways to dictate, with each key’s name under it and Change… beside it.
- If you used Wispr Flow, setup takes its shortcuts as it opens, marks them “Imported from Wispr Flow”, and asks you to quit Wispr Flow while it runs, so one press does not start both apps. A shortcut you changed in kotoba stays yours. Its dictionary import is on Done.
- Setup stays in front until you finish it. A click in the Dock, Open kotoba… or Settings… (⌘,) brings it back. Done opens kotoba on Home.

### The menu bar

- The menu is shorter: the status line with your Hands-free and Push to talk shortcuts, then Paste, Copy and Fix… under a Last Dictation header, with their shortcuts, then Microphone, Open kotoba…, Check for Updates… and Quit.
- Hold ⌥ to see Paste Without Cleanup. Rewrite shows once you save an OpenRouter key.
- Speech Model, Add Word…, word suggestions, History…, Settings… and About are gone from the menu. Add words on the Dictionary page; About and Settings… are in the app menu.

### Messages that say what happens next

- “Will retry.” means kotoba sends the dictation again by itself. “Audio kept.” means it waits for you to press Retry. After 3 failed tries, the pill says “No text after 3 tries. Audio kept.”
- In History, a dictation that waits shows “Waiting for retry”, and one the speech service refused shows “Can’t transcribe”.
- When your speech service is out of credit, Home, the menu bar menu and its icon say so, with Add Credit…. A cleanup or Rewrite that fails for lack of credit shows the same notice for OpenRouter. kotoba still records and saves your dictations. Once you add credit, Send Saved Dictations on Home or in the menu sends them, and so does your next dictation. The menu’s Retry Saved Dictations is now Send Saved Dictations.
- When a Bluetooth mic is kept out and no other mic is there, the pill names it, for example “Not in mic list: AirPods Pro”, with Choose Mic…. “No microphone found” now offers Choose Mic… too.

### Speed and accuracy

- Cleanup now uses DeepSeek V4.1 Flash by default. On 60 real dictations, half the cleanups took under 0.56 seconds (1.05 seconds with Gemini 3.5 Flash-Lite, the old default), and 9 in 10 took under 1.15 seconds (2.17 seconds before). None lost words.
- If DeepSeek can’t answer, the cleanup goes once to Gemini 3.5 Flash-Lite, as Rewrite already did.
- Without cleanup, MAI-Transcribe-2 now leaves out “um”, “uh”, repeated words and false starts as it transcribes. On 60 real dictations, 22 “um”s and “uh”s went to none, every dictionary word stayed, and the time did not change beyond normal variation.
- Keep filler words in Speech > Advanced… brings them back, and it now works for every speech model, not only Grok.
- MAI-Transcribe-2 through Azure now pastes every word you said, as it does through OpenRouter. Before, Azure masked swear words.
- Your dictionary gets “kotoba”, starred, so the speech model spells the app’s name right. If you remove it, it stays removed.
- The window uses less memory. On a test build, open on Home it took 31 MB (36 MB in 0.4.6), and at its highest, with every page shown, 155 MB (159 MB).

### Fixes

- kotoba’s windows no longer join as tabs when System Settings > Desktop & Dock > “Prefer tabs when opening documents” is set to Always.
- The sidebar is now as wide as the one in System Settings.
- Quitting right after a paste now waits until your clipboard is back. Before, kotoba could quit with the dictation still on the clipboard in place of what you had copied.
- When push to talk has its own shortcut, letting go just as the start sound plays no longer loses the recording. It now stops and pastes, as a longer hold does.
- A long MAI-Transcribe-2 dictation that is sent again (a retry, or Transcribe Again in History) no longer fails after about 20 minutes. It now sends a small copy of the audio, as a first try does, so recordings up to about 105 minutes fit. A dictation that is still too long says “Too long for OpenRouter. Audio kept.”, and History shows “Too long to send”.

### Upgrading from 0.4.x

- kotoba 0.4.6 offers this update at its next update check. To get it now, choose Check for Updates… in the menu bar menu.
- Your keys, history, dictionary, shortcuts, mic list, sounds and the pill’s place all carry over.
- If you never picked a cleanup model, cleanup moves to DeepSeek V4.1 Flash. A model you picked stays.
- If you turned on Keep filler words for Grok, it now keeps them with MAI-Transcribe-2 too.
- On a Mac with no built-in mic, the update turns “Use Bluetooth microphones only from the list” off once, so kotoba records as 0.4.6 did. Macs with a built-in mic get the switch on.
- A window you left on Insights or Usage opens on Activity, and a window wider than the new maximum opens at that width.
- Where things moved:
  - Insights and Usage are now Activity.
  - Modes is now Cleanup, Polish is Rewrite, and the cleanup model is in Cleanup > Advanced….
  - How to Dictate and the voice commands are on Shortcuts.
  - Keep audio and Delete Audio Now… are on History.
  - The xAI and Azure routes, the Azure endpoint, the Grok switch and Keep filler words are in Speech > Advanced….
  - Hints are the stars on Dictionary’s rows.
  - About and Settings… are in the app menu.
