## kotoba next

### New

- kotoba has a new look, closer to System Settings. Each page opens with one line on what it does, the sidebar starts with kotoba’s icon and name, and the charts and the pill’s bars use kotoba’s coral. Selection, buttons and switches keep your accent colour.
- The indicator is now a small glass pill that changes shape. Push to talk shows bars while you hold the shortcut; hands-free adds Cancel (×) and Stop. While your text is on its way, the bars become a slow sweep, and a check shows when the text pastes. Words show only when you must know something or can act: an error with its fix, “No sound from the mic”, Undo, an added word, and the time after 10 minutes.
- With Settings > General > Show indicator set to Always, the pill waits as a thin bar. Point at it to see “Dictate” and your Hands-free shortcut, and click it to start a dictation.
- Home shows today’s words, the time saved and your streak, with the last 7 days as bars; click the card to open Activity. Below are your shortcuts, your last dictation with Copy, Paste Again and Fix…, and the 4 dictations before it.
- Microphone has a new switch, on by default: “Use Bluetooth microphones only from the list”. Bluetooth microphones record at call quality and can miss your first word. When AirPods are the Mac’s default input and are not in your list, kotoba records from the built-in mic, or from a USB mic on a Mac without one. With no other mic, the pill says, for example, “Not in mic list: AirPods Pro” with Choose Mic…, which opens Microphone so you can add them. On a Mac with no built-in mic, the update turns this switch off once, so kotoba records as 0.4.6 did. A new install on such a Mac keeps the switch on, and when your list is empty, it adds the Bluetooth mic that is the default at first launch.

### Changed

- Activity replaces Insights and Usage. It shows your words per day for the week or the month, highlights, your top apps this month, and this month’s spend in cents. Advanced… lists spend by model to the fraction of a cent. Usage’s Last 30 Days view is gone. If the window was on Insights or Usage in 0.4.6, it opens on Activity.
- Cleanup replaces Modes. Cleanup, Rewrite and App styles share one page, each with one example. Polish is now called Rewrite, and modes are now app styles. The cleanup model is in Cleanup > Advanced….
- Shortcuts is a new page with every shortcut and how it works, Esc, and the “press enter” and “new line” voice commands, which were in General.
- History has its search on the page (⌘F), and “Keep audio” with Delete Audio Now…, which were in General. Every action for a dictation is in its Control-click menu and in the new Dictation menu in the menu bar: ⇧⌘R shows the audio in Finder, ⌘⌫ deletes.
- Speech and Dictionary keep their rarely used settings in an Advanced… sheet. On Speech: the xAI and Azure routes, the Azure endpoint, other keys and the Grok switches. On Dictionary: starred words and the hint limit. Word suggestions show as a count next to Dictionary in the sidebar.
- Microphone says how kotoba picks a mic: the first connected one in your list, then the next when it is unplugged. Each mic shows whether it is in use or not connected, and a mic you pick in the menu bar menu moves to the top of the list.
- The menu bar menu is shorter: the status line, Paste, Copy and Fix Last Dictation, Microphone, Open kotoba… and Quit. Hold ⌥ to see Paste Last Without Cleanup. Rewrite Last Dictation shows once you save an OpenRouter key. Speech Model, Add Word…, word suggestions, History…, Settings… and About are gone from it; add words on the Dictionary page, and find About and Settings… in the app menu.
- Setup has 5 steps: Welcome, Allow Access (Microphone and Accessibility, each with its own Allow… button), your key, Try It and Done. Welcome shows both ways to dictate, with each key’s name under it. When Wispr Flow is installed, its dictionary import is on Done.
- Messages say what happens next. “Will retry.” means kotoba sends the dictation again by itself; “Audio kept.” means it waits for your Retry. After 3 failed tries, the pill says “No text after 3 tries. Audio kept.” In History, a dictation that waits shows “Waiting for retry”, and one the speech service refused shows “Can’t transcribe”.

### Improved

- On a test build, kotoba keeps about 37 MB after you close its window, down from about 40 MB in 0.4.6. With the window open on Home, it uses about 31 MB, down from about 36 MB.
- The pill uses no more memory or CPU than the old indicator, and does no work while it waits.

### Fixed

- kotoba’s windows no longer join as tabs when System Settings > Desktop & Dock > “Prefer tabs when opening documents” is set to Always.
- The sidebar is as wide as the one in System Settings. Before, it was narrower.
- Quitting right after a paste now waits until your clipboard is back. Before, kotoba could quit with the dictation still on the clipboard in place of what you had copied.
- When push to talk has its own shortcut, letting go just as the start sound plays no longer loses the recording. Before, the pill showed, then the recording was gone with nothing kept. Now it stops and pastes, as a longer hold does.
