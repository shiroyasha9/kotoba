# Idle-memory spike (day 1)

Date: 2026-10-15, 19:57-20:02 IST. Machine: M3 Pro, macOS 27.0.1, Xcode 27.0 (Swift 6.4). Input device: MacBook Pro Microphone (built-in, 48 kHz, 1 ch).
Code: `spikes/memory/` (throwaway; `Spike.swift` with one compile flag per variant, `build.sh`, `measure.sh`). Raw output: `spikes/memory/results/` (gitignored).

Purpose: measure the idle floor for the spec's memory gate, and the cost of Liquid Glass, a prepared audio engine and SwiftUI.

## Variants

All are minimal `LSUIElement` apps, built with `swiftc -O` (not an Xcode Debug build), hardened runtime, signed with "Developer ID Application: Mubin Ansari (7U6G55576W)", bundle ID `tech.teensy.kotoba.memspike` (shared, so one microphone grant covers all).

- A: AppKit `NSStatusItem` with an `NSMenu`.
- B: A + a borderless floating `NSPanel` whose content view is `NSGlassEffectView` with a label; shown for 1 s, then `orderOut` (panel kept alive for reuse).
- C: B + `AVAudioEngine`: input node touched, `prepare()` called, not started.
- D: dropped (owner rejected pre-roll / always-open mic on 2026-10-15). Not built, not launched.
- E: A + a SwiftUI settings window (`NSHostingController` in an `NSWindow`, `Form` with a picker, toggle and text field); shown for 1 s, then closed and released.

## Results (idle 30 s after launch, 2 rounds each)

| Variant | phys_footprint (r1 / r2) | Peak footprint | Dirty (vmmap TOTAL, r1 / r2) | Swapped (r1 / r2) | Notes |
|---|---|---|---|---|---|
| A status item | 12.3 / 12.5 MB | 12.9 MB | 8.8 / 9.0 MB | 3.5 / 3.5 MB | Floor. Malloc Small 6.6 MB is the largest category. |
| B + glass panel | 15.6 / 15.6 MB | 16.2 MB | 13.9 / 15.6 MB | 1.7 / 0 MB | Liquid Glass panel costs about +3.2 MB over A. |
| C + prepared engine | 16.7 / 16.8 MB | 17.6 MB | 12.3 / 12.7 MB | 4.4 / 4.2 MB | Prepared AVAudioEngine costs about +1.1 MB over B. |
| E + SwiftUI window, closed | 27.7 / 27.7 MB | 133.6 MB | 19.0 / 27.7 MB | 8.8 / 0 MB | SwiftUI stays about +15 MB over A after the window closes; about 133 MB while open. |

phys_footprint and peak come from `vmmap --summary` ("Physical footprint"); `footprint` reports the same totals (12 / 16 / 17 / 28 MB). Dirty is the DIRTY column of the vmmap TOTAL row; swapped is the compressed part. Footprint is about dirty + swapped, so the dirty/swapped split moves between rounds while the footprint does not.

Reading: AppKit + glass panel + prepared engine (the phase 1 shape) idles at about 17 MB, far under the original 50 MB aim and Jot's 90 MB. SwiftUI is the largest single cost: +15 MB that stays after the window closes, and a 133 MB peak while it is open.

## Engine start to first buffer (variant C, 10 runs)

Mode `--time-start`: per run, install a tap (requested 512 frames), `prepare()`, call `start()`, wait for the first tap callback, `stop()`, remove the tap, wait 1.5 s. Times are from the `start()` call.

| Measure | p50 | p90 |
|---|---|---|
| `start()` returns | 41.9 ms | 45.3 ms |
| First sample in the first buffer (`AVAudioTime.hostTime`) | 39.2 ms | 42.7 ms |
| First tap callback delivered | 147.5 ms | 150.7 ms |

Every first buffer held 4800 frames (100 ms at 48 kHz) although 512 were requested, so the first callback comes about 100 ms after the first sample. The audio is not lost: the buffer starts about 40 ms after `start()`. For the latency log, `firstAudioBuffer` should use the buffer's host time, not the callback time. Run 1 equals the later runs, so a prepared engine has no extra cold-start cost here. The spec's 20-40 ms assumption is close for the built-in mic; Bluetooth input was not measured.

## Stop wait: input tap vs sink node (2026-10-15, 20:49-20:50 IST)

Question: after the stop tap, how long does capture wait for the audio that holds the stop moment? Spike `spikes/memory/StopLatency.swift` (same bundle ID and signature as the memory spike, built-in mic, 48 kHz). Each run requests a stop at a random moment and waits until a delivered buffer ends after it; 10 stops per method.

| Method | Frames per callback | p50 | p90 | Max |
|---|---|---|---|---|
| Input tap, bufferSize 1024 (the first app build) | 4800 (100 ms; the tap ignores smaller requests) | 50.6-70.4 ms | 85.3-85.9 ms | 86.7-100.0 ms |
| `AVAudioSinkNode` (one hardware cycle) | 512 (10.7 ms) | 5.6-8.4 ms | 10.8-12.5 ms | 13.1-13.2 ms |

Ranges cover two runs. In the full stop path, `engine.stop()` took 12.7-19.9 ms and `prepare()` 7.1-21.6 ms, so the app runs both after the audio is handed to upload, not before.

Result: the app now captures through a sink node and a lock-free ring drained by a writer thread (`App/AudioCapture.swift`, `App/CaptureWriter.swift`). New worst case for the stop wait: about 13 ms, was about 100 ms.

## Follow-up measurements for the phase 1 review (2026-10-15, 21:10-21:20 IST)

- **Writer setup before engine start (review item 7).** Creating the FLAC file and converter took 0.14-0.29 ms (10 runs), and 10.8 ms the first time in a process (codec load; 1,148 ms on the first run after a fresh build). The app now starts the engine first and builds the writer while audio waits in the ring, so this time is off the key-down path. Probe: scratchpad `writerprobe`, `AVAudioFile(forWriting:)` + `AVAudioConverter` in a loop.
- **Ring buffer (item 22).** A zero-filled 1 << 19 Float ring added 4,096,456 B footprint to a probe process; a 1 << 16 ring without zero-fill added 1,999,304 B (the probe's own floor). Saving: 2.0 MiB idle. During capture the smaller ring dirties at most 256 KiB.
- **Indicator panel (item 23).** Spike `spikes/memory/PanelCost.swift`: idle 11.7 MB; after the glass panel was created, shown once and hidden: 14.6 MB; 15 s after the panel was released: still 14.6 MB. Create + show took 68.8 ms the first time, then 16.2-23.1 ms. Releasing the panel frees nothing measurable and adds 16-23 ms to the next show, so the app keeps one panel for its lifetime (item 23 not applied).
- **Indicator panel, second probe (phase 2, indicator agent).** A bare debug AppKit process that runs the real `App/IndicatorPanel.swift` and `App/IndicatorPillView.swift`, footprint from `task_info` `phys_footprint` (the number `footprint` shows), 3 runs. It agrees with the spike above: releasing the panel 32 s after hide freed about 0.25 MB (15.30 -> 15.03 MB), and the next show took 21-46 ms against 4-8 ms with the panel kept. The gain is in not building at launch: building the panel and views at launch (the old `init`, window deferred) added 4.8 MB (7.39 -> 12.19 MB) and took 158 ms. The first show took 69-127 ms and added 7.8 MB (7.3 -> 15.1 MB), most of it one-time AppKit, glass and font setup. `CGWindowListCopyWindowInfo` (the focused-window screen lookup at each show) took 7-23 ms on the first call and 0.4-5 ms later. Decision: build the panel on first show and keep it; no release timer. Probe: scratchpad `indicator-bench` (session-local, not kept).

## Settings window (phase 2, 2026-10-15, before 21:30 IST)

Spike `spikes/settings-memory/` (`build.sh`, `measure.sh`): a status-item app built with `swiftc -O` from the real `App/Settings/{SettingsWindow,DictionaryModel,DictionaryPane}.swift` plus KotobaCore and KotobaStorage sources, with the Dictionary pane holding 36 terms and 2 rules. `SettingsBase` is the same app with no SwiftUI. Physical footprint from `vmmap --summary`, 2 rounds:

| State | r1 | r2 |
|---|---|---|
| SettingsBase, idle 30 s | 12.2 MB | 12.1 MB |
| SettingsSpike, idle 30 s (SwiftUI linked, window never opened) | 12.3 MB | 12.2 MB |
| Dictionary pane open (8 s after open) | 31.5 MB | 34.6 MB |
| 30 s after close | 31.3 MB | 32.9 MB |

- Linking SwiftUI costs about +0.1 MB at launch: the app's idle footprint does not change until Settings opens.
- Opening Settings adds +19-21 MB that stays after close, more than the +15 MB of variant E (a smaller form).
- No leak: `SettingsSpike --leak-check` opens and closes the window and checks weak references 2 s after close. The window, its `NSHostingController` and a per-open pane model are all deallocated. The memory that stays belongs to SwiftUI's loaded runtime, not to kotoba's objects. The app's `DictionaryModel` lives for the app's lifetime on purpose, because the pipeline reads it.
- Decision (lead, 2026-10-15): +19-21 MB after close is accepted for now. The idle gate is measured from launch with Settings never opened. If the owner wants it lower, the option is AppKit panes.

## Commands

```sh
cd spikes/memory
./build.sh A B C E        # swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -D VARIANT_<v>; codesign --options runtime
./measure.sh 2 A B C E    # per variant: open -g -n build/MemSpike<v>.app; sleep 30;
                          # footprint -p <pid>; vmmap --summary <pid>; kill -TERM <pid>
open -g -n build/MemSpikeC.app --args --time-start "$PWD/results/c-timing.txt"
```

Microphone: the first launch of C showed authorization status notDetermined, and the request returned granted (the owner clicked Allow in the TCC prompt). Later launches read status authorized.

## Unresolved questions

1. Does a prepared but not started engine (variant C) turn on the orange mic indicator? Not checked by eye during this run.
2. Footprint after hours idle and after many dictations (fragmentation, URLSession, SQLite) is not measured; this spike covers 30 s after launch only.
3. First-buffer timing on AirPods or other Bluetooth input is not measured.
4. Should Settings and History stay SwiftUI given +15-21 MB that persists after close, or move to AppKit? Accepted for now (see "Settings window"); AppKit panes are the option if the owner wants less.
