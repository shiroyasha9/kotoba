# Dock app (story 35)

Status: research and design, 2026-10-16 14:20-14:50 IST. Agent `dock-app`. No code changed in the app. Machine: M3 Pro, macOS 27.0.1 (26A434). Spike code and raw results: `<runbooks>/2026-10-16-kotoba-dock-app/spike/`. No spike activated an app or posted an input event.

Owner decision (2026-10-16): kotoba becomes a Dock app. General settings get "Show in Dock" (default on). The menu bar icon stays, with its own show or hide setting.

Built 2026-10-16 15:00-15:30 IST on branch `dock-app` (agent `dockapp`), on top of the one main window (c605284). The owner's answers to the open questions changed items 4, 8 and 10 and added the Dev icon; see "Owner decisions" and "As built" at the end. Where this text and those sections differ, the sections win.

## Recommendation

1. **Keep `LSUIElement: true` in `project.yml`.** At launch, the first step of `applicationDidFinishLaunching` sets the policy from the setting: `.regular` when "Show in Dock" is on, else nothing (the plist already gives `.accessory`). Measured: one policy change, no Dock icon before it, +0.25 MB, 0.5 ms (see Measured cost).
2. **Do not set the policy in `applicationWillFinishLaunching`, and do not make the plist regular.** In `willFinishLaunching` the same switch costs +1.1 MB idle and +35 ms to `didFinishLaunching`. With a regular plist, LaunchServices reports the app as regular from exec, so a "Show in Dock: off" launch is a Dock app for about 100 ms before the switch to `.accessory`: the flicker.
3. **The toggle needs no relaunch.** `setActivationPolicy(_:)` runs at the toggle event. Apple: "You can set any activation policy in macOS 10.9 and later." Measured: the call takes 1.3-2.4 ms, idle footprint does not change, and a window that is open stays on screen.
4. **(Changed by the owner: see Owner decisions 1.)** **"Show in Dock: off" means `.accessory` at all times**, as kotoba is today. No switch to `.regular` while a window is open (Wispr Flow, VoiceInk and TypeWhisper do that; see Open questions 1). Each runtime switch is an event with known focus bugs; this keeps the switches to the owner's own toggle.
5. **The menu bar icon toggle sets `NSStatusItem.isVisible`** on the one `StatusBarItem` that lives for the whole app. Set `autosaveName` so macOS keeps its place. Do not set `behavior = .removalAllowed`, so a ⌘-drag cannot remove it behind the setting's back. While the icon is hidden, the listening blink does not run.
6. **Guard: the Dock icon and the menu bar icon cannot both be off.** The toggle for the last visible place is disabled, with a footer that says why. The macOS 26+ System Settings > Menu Bar switch can still hide kotoba's icon, and no API tells kotoba (Apple DTS, see Evidence). So the safety net is reopen (item 7).
7. **Every reopen shows the main window**: a Dock click, a second open from Finder, Spotlight, Raycast or `open -a`. Main (c605284) already shows the main window at its last pane (`MainWindowController.show()`); the handler moves to `App/AppWindows.swift`. The handler keeps ignoring `hasVisibleWindows`: Apple's notes say a status item makes it always true.
8. **A launch by the user opens the main window; a login launch opens none.** Read `keyAELaunchedAsLogInItem` from the open-application Apple event in `applicationDidFinishLaunching` (the event is not yet there in `willFinishLaunching`, measured). Onboarding still opens first while setup is not complete. Hex ships the same check. Apple does not say that `SMAppService.mainApp` sets the flag, so the owner trial checks it (T12).
9. **One full main menu for both policies**: kotoba (About kotoba, Check for Updates…, Settings… ⌘,, Services, Hide kotoba ⌘H, Hide Others ⌥⌘H, Show All, Quit kotoba ⌘Q), File (Close ⌘W), Edit (as today), Window (Minimize ⌘M, Zoom, Bring All to Front, set as `NSApp.windowsMenu`), Help (`NSApp.helpMenu`, "kotoba Help" opens the README). Today `NSMenu.hiddenMain()` (`App/MenuChoices.swift:62-87`) has File as its first item. AppKit shows the first item as the app menu, so a regular kotoba would show Close under the "kotoba" title and have no Quit.
10. **Dock menu (`applicationDockMenu`)**: built on each right-click from the same `MenuModel` as the status menu, without About and Quit (the Dock adds Quit, Options and Show All Windows). Apple's HIG: "People can hide or choose not to use your menu bar extra, but a Dock menu is aways [sic] available." Nothing is built at idle.
11. **Indicator panels get `canHide = false` and `isExcludedFromWindowsMenu = true`** (`IndicatorPanel.makeFloatingPanel`, `App/IndicatorDropTargets.swift:80-93`). Measured: `NSApp.hide` (⌘H, or ⌥⌘H in any other app) hides a panel with the default `canHide = true`. When such a panel is ordered in while kotoba is hidden, kotoba unhides with every window, also Settings. With `canHide = false` the pill stays and kotoba stays hidden. Both results are the same for `.regular` and `.accessory`; a Dock app is simply hidden far more often.
12. **The dictation path does not change.** The hotkey tap, the nonactivating pill, the sounds and the CGEvent paste never activate kotoba under either policy. The paste goes to the front app. kotoba is the front app only when the owner made it so (Dock click, ⌘-Tab, a kotoba window), as today with a window open.
13. **Quit**: ⌘Q, the Dock's Quit and logout all go through `applicationShouldTerminate`, which already waits for a live recording (`App/AppDelegate.swift:155-163`). `applicationShouldTerminateAfterLastWindowClosed` keeps its default (false): kotoba runs on with no window.
14. **One owner of the policy**: a new App type is the only caller of `setActivationPolicy` (and `App/Snapshots.swift:93`, which sets `.prohibited` for snapshot runs). A SwiftLint rule enforces it, like `window_front`. Snapshot runs and `make check` exit before the app delegate runs, so they never show a Dock icon.
15. **Cost gate for the build**: measure kotoba Dev idle `footprint` 30 s after launch with the Dock on and off (2 rounds each) and report it; the spike predicts under +0.3 MB.

## Evidence

### Apple documentation

- [`setActivationPolicy(_:)`](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)): returns "true if the policy switch succeded"; "You can set any activation policy in macOS 10.9 and later." The page does not say when to call it.
- [`.accessory`](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory): "doesn't appear in the Dock and doesn't have a menu bar, but it may be activated programmatically or by clicking on one of its windows"; it "corresponds to value of the `LSUIElement` key ... being `1`." [`.regular`](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/regular): "appears in the Dock and may have a user interface."
- [`LSUIElement`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement): "whether the app is an agent app that runs in the background and doesn't appear in the Dock."
- [`activate()`](https://developer.apple.com/documentation/appkit/nsapplication/activate()) (macOS 14): "calling this method doesn't guarantee app activation." [AppKit release notes for macOS 14](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14): "apps should not assume that activation requests will always succeed." `WindowFront` already handles this (`App/WindowFront.swift`).
- [`applicationShouldHandleReopen`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldhandlereopen(_:hasvisiblewindows:)): called when "the Finder reactivates an already running application ... or used the dock". [Older AppKit notes](https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/): with NSStatusItems "the hasVisibleWindows flag will always be YES".
- [`applicationDockMenu(_:)`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)), [`applicationShouldTerminateAfterLastWindowClosed`](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)).
- [`keyAELaunchedAsLogInItem`](https://developer.apple.com/documentation/coreservices/keyaelaunchedasloginitem): "If present in a `kAEOpenApplication` event, the receiving application was launched as a login item and should only perform actions suitable to that environment." [`SMAppService.mainApp`](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) says nothing about the flag. Forum threads [718649](https://developer.apple.com/forums/thread/718649) and [760186](https://developer.apple.com/forums/thread/760186) ask and get no answer.
- [`NSStatusItem.isVisible`](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible): it "persists and restores automatically based on the value of autosaveName". [`.removalAllowed`](https://developer.apple.com/documentation/appkit/nsstatusitem/behavior-swift.struct/removalallowed): "Upon removal, the item's isVisible property changes to false."
- No API reads the System Settings "Allow in the Menu Bar" state: DTS, [thread 788101](https://developer.apple.com/forums/thread/788101) ("No.") and [thread 801489](https://developer.apple.com/forums/thread/801489) ("There isn't currently any programmatic API to detect that setting"; `isVisible` stays true, FB20384263).
- [`nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel): "does not activate the owning app." No page gives other rules for a `.regular` app. [`hidesOnDeactivate`](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate) defaults to true for NSPanel; kotoba sets false (`App/IndicatorPanel.swift:195`).
- [`canHide`](https://developer.apple.com/documentation/appkit/nswindow/canhide): "whether the window can hide when its application becomes hidden"; default true. [`isExcludedFromWindowsMenu`](https://developer.apple.com/documentation/appkit/nswindow/isexcludedfromwindowsmenu): default false.
- [`isRestorable`](https://developer.apple.com/documentation/appkit/nswindow/isrestorable): a restorable window needs a [`restorationClass`](https://developer.apple.com/documentation/appkit/nswindow/restorationclass). kotoba's windows are built in code with none, so AppKit restores none at login. TypeWhisper's login-restore bug came from SwiftUI scenes ([PR 908](https://github.com/TypeWhisper/typewhisper-mac/pull/908)), which kotoba does not use.
- HIG, [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar): "Let people - not your app - decide whether to put your menu bar extra in the menu bar." "Avoid relying on the presence of menu bar extras." [Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus): "Make custom Dock menu items available in other places, too."

### Known pitfalls of a runtime switch

| Report | macOS | Problem | Status in this design |
|---|---|---|---|
| [forum 650270](https://developer.apple.com/forums/thread/650270), [127774](https://developer.apple.com/forums/thread/127774) | 10.15, 2020 | After `.accessory` to `.regular`, the previous app's menu bar stays until ⌘-Tab | Owner trial T3; no recent report |
| [forum 774096](https://developer.apple.com/forums/thread/774096) | 2025 | No menu bar after a display reconnect and a switch | Rare; T3 notes it |
| [forum 836619](https://developer.apple.com/forums/thread/836619) | 2026 | The window "jumps to the background" on a switch back to `.accessory`; DTS: strict activation "is intended" | Spike: an inactive window stays on screen; the active case is T4 |
| [forum 735682](https://developer.apple.com/forums/thread/735682) | 2023 | Policy set before `NSApplicationMain`: the Dock icon flashes; DTS recommends `LSUIElement` | Avoided: plist agent, switch in `didFinishLaunching` |
| [Hex 146](https://github.com/kitlangton/Hex/issues/146), [VoiceInk 576](https://github.com/Beingpax/VoiceInk/issues/576) | 26.2, 26.3 | Login launch opened a window; menu-bar-only mode could not open Settings after login | Item 8; T12 |
| [Hex 33](https://github.com/kitlangton/Hex/issues/33) | 15.3 | A `.regular` app shows in ⌘-Tab | Standard Dock-app behaviour |

### Reference apps

| App | Plist | Dock setting | Menu bar icon setting | Both hidden | Reopen | Login launch |
|---|---|---|---|---|---|---|
| Hex (MIT) | No `LSUIElement` | "Show Dock Icon", default on; policy in `didFinishLaunching` and on change ([AppDelegate L35-36, L150-158](https://github.com/kitlangton/Hex/blob/3e300721b8784ea19ede0359d8fbcca94cfb6a04/Hex/App/HexAppDelegate.swift#L150-L158)) | None, always shown | Cannot happen | Settings ([L160-163](https://github.com/kitlangton/Hex/blob/3e300721b8784ea19ede0359d8fbcca94cfb6a04/Hex/App/HexAppDelegate.swift#L160-L163)) | No window, `keyAELaunchedAsLogInItem` ([L75-82](https://github.com/kitlangton/Hex/blob/3e300721b8784ea19ede0359d8fbcca94cfb6a04/Hex/App/HexAppDelegate.swift#L75-L82)) |
| FreeFlow (MIT) | `LSUIElement` true | None; `.regular` while Settings is open, `.accessory` on close ([AppDelegate L89-134](https://github.com/zachlatta/freeflow/blob/797a3f32e6b525b8d942512db2801466d3a651f7/Sources/AppDelegate.swift#L89-L134)) | `MenuBarExtra(isInserted:)` ([App.swift L7-10](https://github.com/zachlatta/freeflow/blob/797a3f32e6b525b8d942512db2801466d3a651f7/Sources/App.swift#L7-L10)) | Relaunch opens Settings | Settings ([L40-46](https://github.com/zachlatta/freeflow/blob/797a3f32e6b525b8d942512db2801466d3a651f7/Sources/AppDelegate.swift#L40-L46)) | Setup only |
| Jot (Apache-2.0) | `LSUIElement` true, `.accessory` again in code ([AppDelegate L46-56](https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/8f2d7a44d533dedc432351caa41227e65b0a4cec/App/Sources/AppDelegate.swift#L46-L56)) | None | None | Cannot happen | None | None |
| VoiceInk (GPL, ideas only) | `LSUIElement` false | "Menu bar only", default off; `.regular` while a window is open ([WindowManager L26-42](https://github.com/Beingpax/VoiceInk/blob/6a14368a2285acfdf79045a9feaf1b625e9bc397/VoiceInk/App/Windows/WindowManager.swift#L26-L42)) | None | Cannot happen | Main window in Dock mode | No check (bug 576) |
| TypeWhisper (GPL, ideas only) | `LSUIElement` true | Picker: menu bar icon, Dock icon, Dock icon while a window is open ([AppearanceSettingsView L36-67](https://github.com/TypeWhisper/typewhisper-mac/blob/180eed2cd7583f3e6f37c1c6710ba01324bd37f2/TypeWhisper/Views/AppearanceSettingsView.swift#L36-L67)) | `MenuBarExtra(isInserted:)` | Allowed; text says "open from Spotlight" | Settings or Setup | Setup only |
| Wispr Flow (closed; strings in the 1.6.1147 bundle) | Electron | "Show in Dock", default on; when off, `.regular` only while a window shows | None found | Cannot happen | Not traced | No main window when opened at login |
| Raycast (closed, [manual](https://manual.raycast.com/settings)) | `LSUIElement` true | None | "Show in Menu Bar" | Option-Space and ⌘, still open it | n/a | n/a |
| CleanShot X | Not found | Not found | Not found | Not found | Not found | Not found |

No reference app has a Dock menu.

## Measured cost

Spike: a minimal AppKit app with one status item, like kotoba's launch shape. Built `swiftc -O`, ad-hoc signed. Launched with `open -g -j -n` (no activation). "LS policy" is `NSRunningApplication.current.activationPolicy` read at each step; it is what the Dock follows. Footprint is `phys_footprint` from `task_info` 10 s after launch; `footprint -p` gave the same rounded values. Medians; the first run of each bundle was a cold start (385 ms and 564 ms to `didFinishLaunching`) and is in the medians.

| Variant | n | Exec to `didFinishLaunching` | `open` to `didFinishLaunching` | Idle footprint | Policy as LaunchServices saw it |
|---|---|---|---|---|---|
| Plist agent, no switch (kotoba today) | 6 | 93.6 ms | 144.5 ms | 14.52 MB | accessory from exec |
| Plist agent, `.regular` in `didFinishLaunching` (**recommended**) | 6 | 82.8 ms | 127.5 ms | 14.77 MB | accessory, then regular once |
| Plist agent, `.regular` in `willFinishLaunching` | 6 | 128.2 ms | 176.4 ms | 15.63 MB | accessory, then regular once |
| Plist regular, no switch | 3 | 110.5 ms | 157.1 ms | 15.81 MB | regular from exec |
| Plist regular, `.accessory` in `willFinishLaunching` | 3 | 99.4 ms | 166.3 ms | 15.16 MB | **regular from exec for about 100 ms, then accessory** (flicker) |

- The `setActivationPolicy` call itself: 0.46-0.97 ms at launch, 1.35-2.41 ms at runtime (n = 6 runtime switches).
- Runtime switches in one process, footprint 8 s after each step (2 runs): 14.97 / 15.00 MB accessory, 14.67 / 14.70 MB regular, 14.70 / 14.74 MB accessory again, 14.70 / 14.74 MB regular again. A runtime switch costs no memory.
- An off-screen window of an inactive app stays visible and on screen in WindowServer after `.accessory` to `.regular` and back.
- App hide (`NSApp.hide`, both policies): a nonactivating floating panel with `canHide = true` goes off screen. Ordering a `canHide = true` panel in while hidden unhides the app (all its windows come back) but does not activate it. A `canHide = false` panel stays on screen while hidden, and ordering it in does not unhide the app.
- The open-application Apple event (`aevt`/`oapp`) is present in `didFinishLaunching` and absent in `willFinishLaunching`. For `open` launches, `launchIsDefault` was true and the login item flag false.
- Not measured: the real kotoba (item 15 measures it during the build), anything that needs kotoba to be the active app (no activation was allowed), and a real login.

## Files to change

- `project.yml:74`: `LSUIElement: true` stays. Rewrite its comment: the launch starts as an agent so no launch shows a Dock icon by mistake; `App/DockAndMenuBar.swift` makes it a Dock app.
- `KotobaCore/Sources/KotobaCore/AppPresence.swift` (new, pure): the value `showsInDock`, `showsMenuBarIcon`; a change that would turn both off is refused; `launchWindow(isLoginLaunch:isSetupComplete:)` gives none, onboarding or main window; reopen always gives the main window. Like `InstallYield`.
- `App/DockAndMenuBar.swift` (new): applies `AppPresence` to `NSApp.setActivationPolicy` and `StatusBarItem.isShown`; the only caller of `setActivationPolicy` outside `App/Snapshots.swift`.
- `App/AppDefaults.swift`: keys `app.showsInDock` and `app.showsMenuBarIcon`, both registered as true.
- `App/AppDelegate.swift:77-129`: apply the presence first in `applicationDidFinishLaunching`, after `NSApp.mainMenu`; read the login item flag there; open the launch window (item 8). `:150-153`: reopen shows the main window. Add `applicationDockMenu(_:)`.
- `App/StatusBarItem.swift`: `isShown` sets `item.isVisible`; `autosaveName`; `showIcon` starts no blink while hidden.
- `App/MenuChoices.swift:57-87`: `hiddenMain()` becomes the full main menu of item 9 (app menu first). Its doc comment changes.
- `App/StatusMenu.swift` and `App/AppMenu.swift`: a Dock variant of `MenuModel.build` without About, Quit and the update item.
- `App/IndicatorDropTargets.swift:80-93`: `canHide = false`, `isExcludedFromWindowsMenu = true` in `makeFloatingPanel`.
- `App/Settings/GeneralPane.swift` (or its main-window successor): a "Dock and Menu Bar" section with "Show in Dock" and "Show in menu bar", and a footer while one of them is disabled.
- `App/ReleaseAppWatcher.swift:4-7`: the comment says kotoba is an `LSUIElement` app. The release can now be either; KVO on `runningApplications` covers both, so only the comment changes.
- `.swiftlint.yml`: a rule `activation_policy` for `setActivationPolicy(` outside `App/DockAndMenuBar.swift` and `App/Snapshots.swift`.
- `App/Snapshots.swift` registry: the General pane with both toggles on and with one disabled; the Dock menu and the main menu as text (`menu-dock.txt`, `menu-main.txt`).
- `CODING_STANDARDS.md:44-46` ("Windows and text entry"): kotoba is a Dock app by default; the main menu is visible when it is; the rule "never remove it" stays.
- `docs/spec.md`: story 35 and "Platform and UI" (see Spec change).
- `README.md:11, :144`: "Menu-bar dictation" and "It appears in the menu bar, not in the Dock."
- `docs/testing/phase2-manual.md`: the owner trial rows below.
- `docs/release.md` / release notes: an update turns the Dock icon on; say where the switch is.

## Test plan

### Unit tests (`KotobaCore/Tests/KotobaCoreTests/AppPresenceTests.swift`)

- Default: Dock on, icon on.
- Dock off with the icon on: accepted. Icon off with the Dock off: refused, state unchanged. And the reverse.
- Launch window: login launch gives none; user launch with setup incomplete gives onboarding; with setup complete gives the main window. Reopen gives the main window in every state.

### Snapshots and checks

- `make snapshots`: the General pane in light and dark, both toggles on, and "Show in Dock" off with "Show in menu bar" disabled and its footer. `menu-main.txt` starts with the kotoba menu and has Quit kotoba ⌘Q. `menu-dock.txt` has no About and no Quit.
- `make check` with the new lint rule.
- Cost: kotoba Dev, `footprint` 30 s after launch, Dock on and off, 2 rounds each; launch time from process start to the "Hotkey tap started" log line, 3 runs each.

### Owner trial (only a real click proves these)

Run with kotoba Dev while the release app is quit (so Dev keeps its hotkey). Read focus from `log stream --predicate 'subsystem == "tech.teensy.kotoba.dev"'`.

| # | Steps | Expected |
|---|---|---|
| T1 | Quit kotoba Dev. Open it from Finder, "Show in Dock" on. | The Dock icon appears once, with no flash. The menu bar shows kotoba, File, Edit, Window, Help. The main window opens. |
| T2 | Turn "Show in Dock" off, quit, open from Finder. | No Dock icon at any moment. The main window opens. |
| T3 | With the window open, turn "Show in Dock" on. | The Dock icon appears. The menu bar shows kotoba's menus at once, with no ⌘-Tab. |
| T4 | Turn "Show in Dock" off with the window open. | The Dock icon goes. The window stays in front and key; ⌘A and ⌘V work in a text field. |
| T5 | Turn "Show in menu bar" off. | The icon goes; "Show in Dock" is disabled, with the footer. Turn the icon on again: it comes back in the same place. |
| T6 | Dock on, icon off, close all windows. Click the Dock icon. Then minimize the window and click the Dock icon again. | The main window opens; the minimized window comes back. |
| T7 | Dock off, icon on. Turn kotoba off in System Settings > Menu Bar. Open kotoba from Spotlight. | The main window opens. |
| T8 | Right-click the Dock icon. Pick a microphone. With TextEdit in front, choose Paste Last Dictation. | The menu matches the status menu. The text goes into TextEdit. |
| T9 | Dock on, TextEdit in front: dictate with the chord, then with a click on the idle pill ("Show indicator: Always"). | Both paste into TextEdit. kotoba never becomes active. |
| T10 | Open Settings, then press ⌥⌘H in TextEdit. Dictate. | The pill shows; Settings stays hidden; the text goes into TextEdit. |
| T11 | Start a recording, press ⌘Q in kotoba's menu. | Quit waits; the audio is in History after relaunch. |
| T12 | Launch at login on. Log out and in. | The Dock icon is there; no window opens. The log shows the login item flag true. |
| T13 | Run the release app and kotoba Dev together. | Two Dock icons; Dev gives way (pill text) as today. |

## Spec change

Story 35, new text:

> 35. As a user, I want kotoba in the Dock and in the menu bar by default, with a setting to hide either one, so that it stays out of the way as much as I want.

New story 35a:

> 35a. As a user, I want a click on the Dock icon, or opening kotoba again from Finder or Spotlight, to show the kotoba window, so that I can always get back in, even when its icons are hidden.

"Platform and UI", replace the second bullet with:

> - kotoba is a Dock app by default ("Show in Dock", General). The Info.plist keeps `LSUIElement`, and launch sets the `.regular` policy from the setting, so no launch shows a Dock icon by mistake; the setting applies at once, without a relaunch. The `NSStatusItem` menu bar icon has its own setting; the two cannot both be off. A launch by the user opens the main window; a login launch opens none. The recording indicator is an AppKit panel using `NSGlassEffectView`; it never activates kotoba and never hides with it.

## Open questions (answered in Owner decisions)

1. "Show in Dock: off": never in the Dock (recommended, today's behaviour), or in the Dock while a kotoba window is open, as Wispr Flow, VoiceInk and TypeWhisper do? The second gives ⌘-Tab and a visible menu bar while a window is open, but adds a policy switch at each window open and close, which is where the known focus bugs are.
2. May the owner hide both icons (TypeWhisper allows it and says "open from Spotlight")? Recommended: no.
3. Should a launch by the user (Finder, Dock, Spotlight) open the main window? Recommended: yes, never at login. Today a launch shows nothing unless onboarding is due.
4. Dock menu: the full status menu, or a short list (History, Settings…, Microphone, Speech Model, Paste Last Dictation)?
5. A Dock badge with the count of saved dictations that wait for a retry (`NSApp.dockTile.badgeLabel`, set on the existing queue refresh, no idle work)?
6. kotoba Dev and the release show the same icon in the Dock. Should Dev get its own icon?
7. Existing installs: an update to 0.3.0 turns the Dock icon on (default on). Confirm that this applies to updates too, not only to new installs.

## Owner decisions (2026-10-16)

1. "Show in Dock" off: kotoba is in the Dock only while one of its windows is open, and back to `.accessory` when the last one closes, event-driven. Counted: every window shown through `WindowFront.show` (main window, onboarding, Fix Dictation). Not counted: the indicator pill and drop targets, the menus, the About panel, Sparkle's windows. kotoba enters the Dock at the click (`WindowFront.activate`, before `NSApp.activate()`, as FreeFlow orders it) so the menu bar comes with the activation. A request that shows no window ends when kotoba resigns active.
2. The two icons cannot both be off: the toggle of the icon that is left is disabled, with a footer. A saved state with both off (a hand edit) shows the menu bar icon.
3. A launch by the owner opens the main window; a login-item launch opens none. Onboarding still opens first at every launch until it is done (as before).
4. Dock menu: the menu bar menu's items from the same `MenuModel.build`, without Quit (the Dock adds its own).
5. Dock badge: the number of dictations that wait for a retry, set when the count changes (and as kotoba enters the Dock); none at 0.
6. kotoba Dev has its own icon: `App/AppIconDev.icon` (blue, amber "DEV" band), from the icon generator; the Debug configuration selects it and `scripts/check-dev-install.sh` fails a Debug build with the release icon.
7. "Show in Dock" is on for new installs and for updates: a registered default, no migration.

## As built

- `KotobaCore/Sources/KotobaCore/AppPresence.swift`: the rules (settings, open windows, window request, launch window, badge), with table tests in `AppPresenceTests.swift`.
- `App/DockAndMenuBar.swift`: applies `AppPresence`; the only caller of `setActivationPolicy` besides `App/Snapshots.swift` (lint `activation_policy`). Reads the login flag (`DockAndMenuBar.launch()`). One `willClose` observer per open window, removed at close; one `didResignActive` observer.
- `App/WindowFront.swift`: `activate()` requests the Dock, `show(_:)` counts the window; `activateForAboutPanel()` does neither.
- `App/MainMenu.swift`: the full main menu (replaces `NSMenu.hiddenMain()`); `App/AppWindows.swift`: the launch window, reopen and `applicationDockMenu`.
- The launch's main window opens after the dictionary is read, so it has its Dictionary pane.
- Measured (kotoba Dev, `<runbooks>/2026-10-16-kotoba-dock-app/measure/`, launched as a login item): idle footprint 30 s after launch, medians of 3, main 25.91 MiB, Dock on 24.55 MiB, Dock off 24.53 MiB: no measurable change (spread 1.6 MiB). `DockAndMenuBar.start()` 1.1 ms with Dock on, 0.4 ms off; `applicationDidFinishLaunching` 84-94 ms warm in both. Not measured: the main window that a launch by the owner now opens (a SwiftUI window adds about 15 MB that stays after close, docs/spec.md).
- `open -g -j` does not make an agent app hidden (`NSApp.isHidden` stays false), so kotoba cannot tell such a launch from a user launch.
