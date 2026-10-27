# History page width

Date: 2026-10-27. macOS 27 (SDK 27.0), branch `history-width`. Owner's problem: every page keeps its cards in the centred 560 pt column (`PageForm`), but History (`PageList`) drew its cards and rows across the whole detail column, so it looked out of place next to Activity.

## Decision

Owner, 2026-10-27: option A, the column. History's cards and rows sit in the same centred column as every other page; the scroll bar stays at the window's edge. Option B (a list beside a detail pane) was prototyped and dropped; its code is not kept. Measured card edges, History against Activity, in points: 328 to 848 for both at the default window (main: 236 to 940), 235 to 700 for both at the smallest, 375 to 895 for both at the widest. History's footprint after the page opens: 41.1-41.2 MB, main 40.8-41.3 MB (`make window-memory`). "Delete Audio Now…" keeps its full width (`fixedSize`): in the smallest window it read "Delete Audio N…", on main too.

## What Apple says

- HIG, Lists and tables: "Keep item text succinct so row content is comfortable to read." and "If each item consists of a large amount of text, consider alternatives that help you avoid displaying over-large table rows. For example, you could list item titles only, letting people choose an item to reveal its content in a detail view." It names Mail as "a table within a split view". https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- HIG, Split views: "Selecting an item in the view's primary pane displays the item's contents in the secondary pane." "Set reasonable defaults for minimum and maximum pane sizes." "Consider letting people hide a pane when it makes sense." No numbers. https://developer.apple.com/design/human-interface-guidelines/split-views
- HIG, Sidebars: "reducing the size of a Mail viewer window can automatically collapse its sidebar"; "Consider automatically hiding and revealing a sidebar when its container window resizes." https://developer.apple.com/design/human-interface-guidelines/sidebars
- HIG, Layout: layout guides "restrict the width of text for optimal readability"; no number for macOS. https://developer.apple.com/design/human-interface-guidelines/layout
- HIG, Inspectors: not read (the page did not load for the research agent). Treat any inspector rule here as unverified.
- WWDC25 310, Build an AppKit app with the new design: "Sidebars appear as a pane of glass that floats above the window's content, whereas inspectors use an edge-to-edge glass that sits alongside the content." The scroll edge effect lives in `NSScrollView`. https://developer.apple.com/videos/play/wwdc2025/310/
- WWDC25 323, Build a SwiftUI app with the new design: the inspector "sits opposite the sidebar"; `.inspector(isPresented:)` on the split view, its toggle in the toolbar. https://developer.apple.com/videos/play/wwdc2025/323/
- WWDC25 356, Get to know the new design system: one scroll edge effect per view; scroll views run under the sidebar. No list-width guidance. https://developer.apple.com/videos/play/wwdc2025/356/
- No Apple source gives a width cap for a list page.

## Apple's apps (from memory of the apps, not checked on this Mac)

- Mail, Notes, Voice Memos, Messages: a list beside a detail (the message, the note, the recording with its transcript, the conversation); the list keeps its width and the detail takes the rest. Mail's "classic layout" box (detail under the list) went away in Catalina (third-party reports: https://www.imore.com/how-restore-missing-side-preview-macos-mail).
- Reminders: one list across the window; details of a reminder in a popover or inspector.
- System Settings: a fixed-width window, so its content column never grows.
- No Apple list app puts its list in a narrow centred column with empty margins; when there is room, the room goes to a detail pane.

## SwiftUI and AppKit facts, measured here

Measured in `make snapshots` (framed window at 960 x 640, legacy scroll bars as on the owner's Mac), by reading the list's `NSScrollView` in a snapshot check.

- `List` still ignores `contentMargins(.horizontal, _, for: .scrollContent)` and `contentMargins(.horizontal, _)`: rows stay full width. A grouped `Form` honours them (that is how `PageForm` works). Docs: https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:) (they do not name `List`).
- `safeAreaPadding(.horizontal, m)` on a `List` keeps its `NSScrollView` the whole window wide (x 0 to 960: it runs under the sidebar and the margins) and sets the scroll view's `contentInsets` (left 318, right 102 at the default size). AppKit tiles the scroll bar inside `contentInsets`, so the bar sat at x 841, at the column's edge, not the window's. This is the 2026-10-25 finding, and it still holds; the scroll view itself is not narrowed.
- `contentMargins(.trailing, -m, for: .scrollIndicators)` does not move the bar (negative margin ignored).
- `padding(.horizontal, m)` narrows the scroll view itself (x 318 to 858).
- `NSScrollView.scrollerInsets` with `right = -contentInsets.right` puts the bar back at the window edge (header: "The distance the scrollers are inset from the edge of the scroll view"). A legacy bar also takes its 17 pt from the content area ("only inset by ... non-overlay scrollers", `NSScrollView.h`), so the trailing padding is 17 pt less with legacy bars, else the selection ends 17 pt short of the cards (it did on main too).
- A grouped `Form` keeps its sections at most about 704 pt wide in a wider pane (on main, History's pinned cards in the widest window were 283 to 987 pt, not 235 to 1035).

## Options prototyped

- A, the column (chosen): `PageList` puts its pinned form in the column (`pageColumn()`, the modifier `PageForm` now shares) and its rows there by safe-area padding; `ScrollerAtEdge` (an empty `NSView` in each row's background) sets `scrollerInsets` so the bar stays at the window's edge.
- B, list and detail (dropped): from a page width of 720 pt, a 320 pt pane at the trailing side, at full height, with the selected dictation's full text, its text before cleanup, Play and its actions; the cards and the list took the rest. It used about 1.2 MB more once History opened, its list pane wrapped the "Keep audio" subtitle to four lines at the default window, and it made History unlike every other page again. Cards across both panes did not work: a grouped form keeps its sections at most about 704 pt wide.
- Not prototyped: SwiftUI `.inspector`. It is attached to the whole split view (WWDC25 323), so History alone would need the window to own it, and its toggle goes in the toolbar, which History's design keeps free of buttons.

Snapshots: `window-history-framed` (default), `window-history-small` and `window-history-wide`, light and dark.

## Unresolved

- Does the Inspectors HIG page add a rule for an always-shown detail pane? (Only matters if a detail pane comes back.)
