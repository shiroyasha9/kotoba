# UI redesign (0.5.0)

Status: agreed with the owner on 2026-10-24 (grill session, about 19:00-20:55 IST). Prototype approved by the owner on 2026-10-25 (Home, Activity and the pill at 5418ff9 and 348e8bd); next: extract the system, then roll it out to every page.
Research notes (with a source for each claim): `<runbooks>/2026-10-24-kotoba-ui-redesign/`:
- `native-ui-libraries-research.md`: libraries, Apple's macOS 26 rules (WWDC25 219, 310, 323, 356; HIG), and the 15 most visible departures in the code, with file:line.
- `ui-inventory.md`: every surface, control and visible text, with file:line; duplications; advanced controls; internal terms.
- `pill-competitors.md`: the indicator of Hex (Swift and Rust), Jot, FreeFlow, VoiceInk, TypeWhisper, Wispr Flow, Superwhisper and macOS Dictation.
- `app-copy-research.md`: copy rules (Apple HIG Writing, Apple Style Guide, NN/g, Microsoft, Mailchimp), a 15-point checklist and before/after examples.
- `gpui-rune-research.md`: the Rust UI option (GPUI, anomalyco/rune), declined for now.

## Problem

Owner, 2026-10-24: the app "looks a bit off (wrong spacing, slightly off icons, typography etc). Feels like a first copy liquid glass", "everything feels hacked around", and the pages feel "overwhelming/confusing" for a normal user. A friend's review: the icons look wrong; sizing and padding do not look like System Settings; text colours; too many dividers; recent dictations need a better design.

Cause (research): the code, not a missing library. No MIT or Apache-2.0 library gives first-party polish on macOS 26. The departures: sidebar symbols stretched into fixed 20 pt tiles (`App/MainWindow.swift`, `PaneIcon`), a glass button on the pill's glass (`App/PillButtons.swift`), mixed symbol and text weights in the pill, about 60 hard-coded paddings, frames and radii (CODING_STANDARDS.md forbids them), corners that do not follow their container, content that stretches across a wide window, and the same information on several panes.

## Decisions

### Direction
- No Rust UI now (GPUI cannot draw Liquid Glass; rune went public on 2026-10-22 and has no accessibility; no measured memory gain). Windows and Linux are later. Look again then.
- Fix the look in Swift. Target: the polish of System Settings and Screen Time. Compare with the owner's on-screen captures of first-party windows and with Apple's rules. Check on macOS 27 only.
- Adopt no UI library. Copy no code from Apple sample code (its licence is not MIT); read it for patterns only. CodeEdit (MIT) is a reference that we may copy from with its notice.

### Process
- First a native prototype in a Worktrunk worktree on branch `ui-polish`, registered in `App/Snapshots.swift`. It covers Home, Activity and every pill state, and it sets the visual system: the content column, the header card, rows, cards, the chart, symbol sizes and the pill geometry. The owner approves it. Then every page uses that system. The prototype views go when the system is extracted.
- One release, 0.5.0, with the new system, all pages, the pill and the new copy.
- README: the owner takes the hero images (glass, the floating sidebar) on screen after the redesign. `make readme-images` keeps the pane images. Since 2026-10-24 they capture real glass and the active look, and `drawsSidebarColors` is gone; the sidebar still draws edge to edge, not inset, in snapshots, which stays open until the owner's on-screen check.
- Each change reports its measured cost (repo rule): `make window-memory` for the window (Swift Charts is new), the pill's idle CPU and footprint as in `docs/research/memory-spike.md`.

### Window
- Resizable. The content column has a maximum width and is centred, so lines do not stretch.
- No sidebar search and no back/forward buttons (about 9 pages, no drill-downs). Look again if the page map grows.
- Sidebar (owner, 2026-10-24 prototype review): the floating inset glass sidebar of Finder and Notes, not the edge-to-edge sidebar of System Settings, if SwiftUI or AppKit gives it natively; if not, keep the edge-to-edge one. Result (spike, 2026-10-24, `<runbooks>/2026-10-24-kotoba-ui-redesign/sidebar-spike/`): macOS 27 draws every sidebar edge to edge, Apple's apps too, and the floating look exists only behind private switches that do nothing. So the sidebar stays edge to edge. Keep the coloured tiles (System Settings look). Draw each symbol at its real weight and optical size, centred in a tile that follows `sidebarRowSize`. Do not use `.resizable()` on symbols.
- Branding (owner, 2026-10-25 prototype review: the window looked like another System Settings pane): the top of the sidebar shows the app icon and "kotoba" on every page. One brand colour, the icon's coral caret, is a colour asset (`Brand`). It is the app's accent colour (`NSAccentColorName`), which macOS uses only when the user's accent is Multicolor. The charts (Home, Activity) and the pill bars are always in the brand colour, as Screen Time's charts use fixed colours. Selection, buttons and switches follow the user's accent. Home gets no header card: the sidebar name and the today card do that job.
- Content symbols match the weight and scale of their text (for example "Words per minute").
- No hard-coded spacing, row heights or radii: system styles, `containerShape` and concentric corners. Text colours come from the system label colours. Few dividers: grouped sections separate the content.
- Taste decisions at the extraction (chief of staff, 2026-10-25, final; review-window.md "Taste"):
  - T1 tiles: Apple's rim and soft ring, not a flat swatch: a one-pixel rim 8 % lighter than the fill and the system shadow under the tile (blur 5 %, drop 1.25 % of the side). Measured against refs/apple/system-settings-general-sidebar-rows: the ring fades over 3 px above and 4 px under a 40 px tile, #cdcdcd at the side as Apple's #cdcccc.
  - T2 keycap legends: the primary label colour.
  - T3, T4: as the approved prototype (shortcut rows in their own card; the last dictation's text starts in the text column).
  - T5 week: the rolling 7 days ending today, always 7 slots with their day initials; a day before the first dictation has no bar (owner QA 1, Q10, replaces "no label before the first dictation").
  - T6 bars: all four corners rounded, no base line (Screen Time).
  - T7 axis labels: secondary (tertiary fails contrast).
  - T8 durations: the system formatter's narrow units ("14h 20m", "42s"), as Screen Time.
  - T9 wide window: a maximum window width, the sidebar plus one and a half content columns (about 1,055 pt), so the column fills at least two thirds of the detail area; the height stays free.
  - T10 copy: "Speaking speed, pauses included"; "Spend stays when you delete dictations."; Speech names OpenRouter, so "kotoba has no OpenRouter key yet." stays; a header card gets a "Learn More…" link only where there is more to learn (none yet).
- No Back and Forward (extraction, 2026-10-25). The window toolbar is on every page, so the title bar keeps one height (owner QA 1, Q12, replaces "no toolbar on any page"): History and Dictionary put their search in it, and Dictionary its + and Import, always in view, as Mail, Notes and Passwords (`pageSearch`, `pageToolbar`).

### Page map
- **Home** (owner, 2026-10-24 prototype review; built at the extraction, `App/Home/HomePage.swift`): first a "today" card in the Screen Time style: "640 words today" as the headline, "About 16 min saved · 5-day streak" under it, and a 7-day mini chart that opens Activity. No "Ready to dictate": when setup is not complete, the problem and its fix button take this place. Then the Hands-free and Push to talk rows with keycaps at a smaller size; the last dictation as a card (full text, app icon, time, Copy, Paste Again, Fix); the 4 dictations before it as compact one-line rows with "Show All". "How to Dictate" moves to Shortcuts.
- **History**: as now, restyled (chief of staff, 2026-10-25): a list as Apple's list apps draw one (`PageList`), with multi-select, the list keys (arrows, Space plays, Delete, ⌘C) and rows that load as they scroll into view. The header and one "Keep audio" row with "Delete Audio Now…" (moved here from General) stay above the list, each in its own card; the search is in the window toolbar (owner QA 1, Q9 and Q12). With no rows (an empty history, a search that finds nothing) a centred empty state takes the list's place, as in Mail; a failed read is a card under the others. Every row action is in the rows' context menu and in the menu bar's Dictation menu (as Mail's Message menu), "Transcribe Again With" as a submenu; no toolbar buttons, no "…" button.
- **Activity** (built at the extraction, `App/Activity/`): Insights and Usage in one page. Top Apps shows this month's words (chief of staff, 2026-10-25), in the page's 28 pt icon column, as Home. "This Month" has Spend in cents ("Less than $0.01" under a cent), Dictations and Audio; "Advanced…" opens spend by model to the fraction of a cent, with a total the rows add up to. The 0.4 Usage pane's "Last 30 Days" period is gone. A Screen Time-style chart (Swift Charts): one headline number, 7 rounded bars in the brand colour, no grid lines, one dashed average line in its own colour (system green) with "avg" in that colour in the axis column on the right, clear of the scale's labels (owner QA 1, Q10), axis labels on the right; the Week/Month switch sits at the top of the chart card, full card width, as Battery's (no toolbar; qa1-review 4); the chart starts at the first dictation. Then highlights, top apps and spend.
- Settings group:
  - **Shortcuts**: every chord, and the "press enter" and "new line" voice commands (split from General). It also takes 0.4 Home's "How to Dictate" card (removed at the extraction; see `App/Home/HomePane.swift` at 0b11e34, `shortcuts`): each set chord with `StatusText.shortcutTitle`/`shortcutHelp` (`pushToTalkHelp` for push to talk), the optional ones only when set, and "Esc · Cancel · While you dictate.".
  - **Speech**: the service and its key.
  - **Dictionary**.
  - **Cleanup**: Cleanup, Rewrite and App styles on one page, each explained with one example.
  - **Microphone**.
  - **General**: sounds, indicator, login, Dock and menu bar, updates.
- Each page opens with a header card: icon tile, title, one line on what the page does, and a link when there is more to learn.
- Advanced controls go in an "Advanced…" sheet at the foot of their page: the xAI and Azure routes, the Azure endpoint, other keys, the Grok switches, the cleanup model, spend by model, dictionary stars and the hint limit. History's "Transcribe Again With" and "Show Audio in Finder" act on rows, so they are in its context menu and the Dictation menu instead (chief of staff, 2026-10-25).
- Remove: the Grok switches from the menu; the competitor name in the "Use ⌃⌘V" help tag.

### Microphone
- The ranked list stays the main control (owner: when an external mic is unplugged, Wispr Flow moves to the AirPods, and kotoba must not).
- A header line explains the rule: kotoba uses the first connected mic in the list; when one is unplugged, it moves to the next.
- New switch, on by default: Bluetooth mics are used only when they are in the list. A Bluetooth default then gives way to the built-in mic, else to another real mic (USB, Thunderbolt, FireWire, PCI; never a virtual or aggregate device); with none, the press says "Not in mic list: <name>" with Choose Mic….
- Upgrades (chief of staff, 2026-10-25, review-upgrade): 0.4.6 kept a Bluetooth default on a Mac with no built-in mic, which is the switch off. So an update to such a Mac stores the switch off once and leaves the order alone, whatever is connected at that launch; a new install lists its connected Bluetooth default. Macs with a built-in mic change nothing.
- A mic picked in the status menu moves to the top of the list.
- Each row shows a live status ("In use", "Not connected", "Bluetooth: lower quality"). Test Microphone and the level gauge stay under the list.

### Status menu
Status line; Paste, Copy and Fix last dictation; Microphone; "Open kotoba…"; Quit. Remove the Speech Model submenu, "Add Word…" and the word suggestion item; suggestions show as a badge on Dictionary.

### Onboarding
5 steps: Welcome (keycaps with each key's name in small text under it), Permissions (Microphone and Accessibility as two rows, each with its own Allow button), Key, Try It, Done (the Wispr Flow import is a row here when Wispr Flow is installed). Text is bold and left-aligned (macOS 26).

### Fix Last Dictation
Stays a separate window (the status menu opens it while another app is in front). Restyled.

### Pill
Pattern: one small glass capsule that changes shape; no status words (Hex, Wispr Flow, Jot). Nothing inside it has its own glass (Apple: avoid glass on glass), so the buttons use a fill.
- Idle ("Show indicator: Always"): a still 40×8 glass bar (8×40 at a side edge), not a circle. On hover (a tracking area, no timer) it grows and shows the shortcut keycaps. A click starts a dictation.
- Recording: 9 bars driven by the existing level events, no "Listening". A scrolling waveform, as in Voice Memos (owner QA 1, Q16): each level enters as a new bar at the trailing edge (the bottom at a side edge) and the bars slide toward the leading edge, one place per level event; no centre origin. Push to talk: bars only. Hands-free: wider, with Cancel (×) and Stop buttons. A small wand when the dictation will be cleaned up.
- Processing: the bars settle into one slow sweep (a Core Animation loop that runs only while text is on its way), then a short check bloom, then idle. No "Transcribing" or "Pasted".
- Words show only when the user must know something or can act: errors with a fix button (Retry, Add Key…, Choose Mic…), a silent mic (orange bars and "No sound from the mic"), Undo after Esc or a rewrite, "Added ‘word’", the 10-minute timer. The capsule widens for them and stays one glass shape.
- Between looks the one glass flows to its new size with a spring (owner QA 1, Q17): AppKit's `NSAnimationContext.animate` with a SwiftUI spring (0.4 s, bounce 0.15), which retargets mid-flight with its speed, so recording, the sweep and the check flow into each other. The radius stays half the short side at every step (a capsule, a circle for the check). Items that stay slide to their new place with the same spring, new items fade in as the glass opens, items that go fade out inside the glass that clips them. The panel keeps its size (the room); only the glass moves. Reduce Motion: no bounce and no slide.
- VoiceOver reads a label for each state ("Recording", "Recording, hands-free", …). Undo and Retry stay real buttons.
- No work at idle: no timer, display link or animation while idle.
- Owner, 2026-10-24 prototype review: the bars use the accent colour, made brighter on light glass so they read over warm backdrops (2026-10-25: the brand colour instead, see Window). Hover shows only the Hands-free chord, after the word "Dictate" (2026-10-25). No Undo countdown bar: Undo goes away by itself and the capsule keeps one height. Secure Input keeps a short message ("Secure Input is on"), because it explains why a paste can fail. With a silent mic in hands-free, Cancel goes (Esc cancels). The capsule height comes from the measured button height, passed to the placement code. Buttons keep their full width, and the snapshot run fails on content longer than the pill.

### Copy
- Each row: a short title and at most one grey subtitle. A page's header line says what the page does. An ⓘ popover holds only the optional "why"; costs, privacy facts, warnings and steps the user must do stay on screen.
- Plain words, no internal terms. "Saved." on a failure becomes words that say it will retry.
- Names: Cleanup (fixes filler words and punctuation as you dictate), Rewrite (was Polish), App styles (was Modes).
- Model names stay visible (until pricing and plans exist): the model name is the row title, a plain description is the subtitle.
- Keys: symbols only (⌃⌥⌘); onboarding draws them as keycaps with the key name under each.
- A chord never shows alone: it always comes with the action it starts ("Dictate ⌃⌥⌘", a row title, a menu item's name) (owner, 2026-10-25, from Wispr Flow's hover label).
- Durations: the system duration formatter.
- Verbs: "press" and "hold", not "tap" ("Press ⌃⌥⌘ to start, press it again to stop." "Hold ⌥ while you speak.").
- New lint words for UI text: "we", "please", "enable", "disable", "toggle", interjections ("oops").
- Apply the checklist in `app-copy-research.md` line by line, then a `/humanizer` pass over all copy.

## Unresolved questions

- None for the visual system: the owner approved the prototype on 2026-10-25 and left the remaining taste items (keycap legend colour, the wide-window width limit, the independent review's taste findings) to the chief of staff.
