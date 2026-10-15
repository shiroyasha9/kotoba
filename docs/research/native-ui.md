# Native components audit (phase 2.6)

Owner ask, 2026-10-16: "make sure everything uses native apple components (and custom only when there is no native one)". Rule: CODING_STANDARDS.md "Native components". This file lists every custom UI piece in `App/`, the native replacement or the gap, and what changed.

## Sources

- Apple HIG, [Settings](https://developer.apple.com/design/human-interface-guidelines/settings): a Mac app's settings window "contains a toolbar that includes buttons for switching between views — called panes". kotoba follows the owner's rule instead (System Settings: a sidebar with grouped forms); see question 1.
- Apple HIG, [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables): a list "can support user interactions like selecting, adding, deleting, and reordering"; "People appreciate being able to reorder a list".
- Apple HIG, [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): Liquid Glass is for "controls and navigation elements"; "Don't use Liquid Glass in the content layer"; "Use Liquid Glass effects sparingly".
- Spike (macOS 26 SDK, offscreen, 2026-10-16): a `Form` with `.formStyle(.grouped)` is a plain hosting scroll view, not an `NSTableView`. No view in it registers a drag type, so `.onMove` inside a grouped Form does nothing on macOS. A `List` is an `NSTableView` (`SwiftUIOutlineListView`) and registers `com.apple.SwiftUI.listReorder`. So a list the user orders must be a `List`. A `List` with `.listStyle(.plain)` and `.scrollContentBackground(.hidden)` inside a grouped `Section` or a `GroupBox` draws as rows in the rounded box, as in System Settings > General > Login Items.

## Audit

| Piece | File | Was | Native replacement or gap | Status |
|---|---|---|---|---|
| Settings shell | `App/Settings/SettingsWindow.swift` | `NavigationSplitView`, sidebar `List` of `Label`s with plain outline symbols | Native split view. Added `.toolbar(removing: .sidebarToggle)`: System Settings has no sidebar toggle. Sidebar icons are now filled symbols, white on a coloured rounded square (`SettingsIcon`, custom: SwiftUI has no settings icon style). Each pane opens with a header box (`PaneHeader`: icon, title, one line on what the pane does). Title, symbol, colour and line live on `SettingsPaneID` | Done |
| Microphone: order list | `App/Settings/MicrophonePane.swift` | Default-style `List` with section headers and separators, a hand-made drag handle (`line.3.horizontal`) and a checkmark column | Grouped `Form`; the order is a plain `List` inside the "Your Order" box with `.onMove`, selection, Delete key and a context menu. Each row is `LabeledContent`: name, and status as secondary text ("In use", "Not connected", the Bluetooth note) | Done |
| Microphone: "Other Connected" rows with Add | same | A section of rows, each with a small Add button | A `+` `Menu` of the other connected mics and a `−` button under the list, as under every editable list in System Settings. The menu item carries the Bluetooth note as a second `Text` (SwiftUI shows it as the item's subtitle; check on screen, manual row 252) | Done |
| Microphone: level bar | same | Two `Capsule`s with a fixed green fill | `Gauge` with `.accessoryLinearCapacity` in an "Input level" row, as in System Settings > Sound | Done |
| Microphone: bottom button bar | same | `Divider` + `HStack` bar | "Test Microphone" in the Input level row; "Follow System Default" (small) on the right of the `+` `−` bar, next to the buttons that change the order | Done |
| Speech pane | `App/Settings/SpeechPane.swift` | Grouped `Form`, `Picker`, `SecureField`, `DisclosureGroup`, link buttons | Native. "Saved" label: only the symbol is green now | Done |
| Key check line | `App/Settings/KeyCheckLine.swift` | `Label`s with the whole label coloured green, red or orange | Only the symbol carries the status colour; the words keep the label colours | Done |
| Dictionary: list | `App/Settings/DictionaryPane.swift` | Default-style `List` filling the pane, `Divider`, footer bar | Plain `List` in a `GroupBox` with `+` `−` at its foot (Login Items look). A grouped `Form` cannot hold it: no selection and no lazy rows for hundreds of words. Empty state: `ContentUnavailableView` with an "Add Word…" button; the "0 words, 0 replacements" line is hidden | Done |
| Dictionary: Wispr import banner | same | Hand-made panel (`.background(.background.secondary)`, icon, text, buttons) | `.alert` with the same title, message and buttons (Cancel and Import, or OK). Snapshots draw the same words in an `NSAlert`, because an offscreen run cannot show a sheet | Done |
| Dictionary: entry editor sheet | same | Grouped `Form` sheet with toolbar Cancel/Add | Native | No change |
| Suggestions section | `App/Settings/SuggestionsSection.swift` (auto-learn) | `.borderedProminent` Add on each row, `.padding(.vertical, 2)` | Plain bordered Add (prominent is for the one default action); drop the fixed padding | Sent to auto-learn |
| General pane | `App/Settings/GeneralPane.swift` (shared) | Grouped `Form`; login-problem row was `HStack` + `Spacer` | Login-problem row is `LabeledContent` with the button as its value. Other rows are native | Done (Startup row only) |
| Shortcut recorder | `App/ChordRecorder.swift` (chord-recorder) | Custom | No native control: AppKit and SwiftUI have no shortcut recorder. Needs the gap comment | Sent to chord-recorder |
| Onboarding hero symbol | `App/Onboarding/OnboardingView.swift` | `.font(.system(size: 40))` | `.font(.largeTitle)` with `.imageScale(.large)` | Done |
| Onboarding step dots | same | Custom dots, `.font(.system(size: 9))` | No native control: macOS has no page indicator (UIPageControl is iOS only). Gap comment added; font is `.caption2` with `.imageScale(.small)` | Done |
| Onboarding Done step switches | `App/Onboarding/OnboardingSteps.swift` | `SwitchRow` (an `HStack` with `Text`, `Spacer`, hidden-label `Toggle`) | Grouped `Form` with two `Toggle`s, as tall as its rows | Done |
| Onboarding footer (Back, Continue, dots) | `App/Onboarding/OnboardingView.swift` | `Divider` + `HStack` of buttons | Native assistant layout | No change |
| Fix Last Dictation editor | `App/FixLastDictation.swift` | `TextEditor` with a hand-drawn border (`RoundedRectangle` stroke, background, clip) | `TextEditor` in a grouped `Form` section; the instruction is the section footer | Done |
| Fix Last Dictation words | same | `ScrollView` of checkboxes with a fixed 110 pt height | "Words to Add" section of checkbox `Toggle`s; the form scrolls | Done |
| Fix Last Dictation empty state | same | `VStack` of texts with `Spacer`s | `ContentUnavailableView` | Done |
| Status menu | `App/StatusMenu.swift` | `NSMenu` with titles, subtitles, states, submenus | Native | No change |
| Indicator pill | `App/IndicatorPillView.swift` (indicator-26) | `NSGlassEffectView`, `NSStackView`, `NSProgressIndicator`, glass `NSButton`; state dot is a layer-drawn circle | Glass is right here (a floating control, HIG Materials). Replace the dot with the SF Symbol `circle.fill` tinted by the state colour | Sent to indicator-26 |
| Pill level meter and countdown bar | `App/IndicatorBars.swift` (indicator-26) | CALayer bars | No fitting native control: `NSLevelIndicator` draws a bezel that does not fit glass; `NSProgressIndicator` needs a value update per frame, while one Core Animation run drains the bar with no idle work. Needs gap comments | Sent to indicator-26 |
| Pill glass stand-in | `App/IndicatorSnapshots.swift` | `NSBezierPath` capsule | Snapshot only (glass does not render offscreen) | No change |

## Why the "Learn from my edits" row is not a Form row

Review 2026-10-16 (quality #6) asked for a short grouped `Form` with the header and the switch above the word list. Spike (macOS 26 SDK, the Settings split view at 720 x 480): a `Form` with `.fixedSize(horizontal: false, vertical: true)`, or with a height measured by `onScrollGeometryChange`, above a `GroupBox` with the word `List` makes the hosting view's fitting height 1963-2174 pt (the list at its full height); the hosting view then grows to that height, and `windowSnapshot` fails. In the real window the same ideal size would push the Settings window past the screen. So the row stays a plain composition (`HStack`: title and subtitle, `Spacer`, a `.switch` toggle) with a comment that names the gap. The Microphone list has no such problem: it sits inside a scrolling form, so its height is measured with `onScrollGeometryChange` (no fixed row height).

## Offscreen limit: text on glass draws black in dark snapshots

Lead report 2026-10-16: in dark snapshots the sidebar labels and the pill's glass button titles (Undo, Retry) draw near black. Spikes (macOS 26 SDK, a dark offscreen window, `cacheDisplay`, the harness's path):
- The window has the dark appearance (`render` sets `NSWindow.appearance`); the sidebar's views report `NSAppearanceNameVibrantDark` and sit inside an `NSGlassEffectView` (the macOS 26 floating sidebar).
- In the same window, SwiftUI `Text` with `.primary` or `.secondary` draws light outside glass and near black inside an `NSGlassEffectView`. `Text` with an explicit `Color.white` and an AppKit `NSTextField` with `labelColor` draw light inside the same glass. A `.glass` button title draws near black inside and outside glass.
- `NSColor.labelColor` resolves to white at 0.9 alpha under VibrantDark, so the color itself is right. I found no compositing filter in the in-process layer tree, so the glass treatment of this text is applied when the window server composites the window, a step that `cacheDisplay` skips.
- Setting the glass content's appearance to darkAqua, or the sidebar effect view to inactive or within-window blending, does not change the image. CARenderer cannot draw the window's layers in process.
Conclusion: an offscreen limit of the glass treatment, not an app bug; the harness cannot fix it with public API. The app code sets no colors on these labels. Check once on screen in dark mode (sidebar labels, pill Undo and Retry).

## Cost

The rebuilt windows use the same frameworks (SwiftUI, AppKit) and are still built on open and released on close. The Microphone pane went from one `List` to a `Form` with one `List`; the Dictionary pane gained two `GroupBox`es; each pane gained a header with one gradient-filled tile; Fix Last Dictation and the onboarding Done step gained a `Form`. Each adds one hosting scroll view while its window is open, and nothing at idle. No framework loads at launch, and the hot path is untouched. I did not run `footprint`: the change is a few views inside windows that are already measured (+19-21 MB after close, docs/progress.md).

## Unresolved questions

1. HIG says a Mac app's settings window uses toolbar tabs; the owner's rule says a System Settings sidebar. Kept the sidebar. Confirm.
2. Microphone: the other connected mics are now in the `+` menu, not in a visible "Other Connected" section. Is a visible list of connected mics still wanted?
3. The drag reorder, the `+` menu, the Delete key and the import alert's Return and Esc cannot show in an offscreen snapshot. They need the manual rows in `docs/testing/phase2-manual.md`.
4. Sidebar icon colours (General grey, Speech blue, Dictionary orange, Microphone red) and the header lines are my choice. Change any?
