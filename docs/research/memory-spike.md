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
- **Indicator pill, round 2.6 (indicator-26, 2026-10-16, 00:50-01:05 IST).** Probe: scratchpad `pillprobe` (session-local), a bare `swiftc -O` AppKit process with the real `App/IndicatorPanel.swift` and `App/IndicatorPillView.swift` (git HEAD for "before", the working tree for "after") and the KotobaCore sources; `phys_footprint` 3 s, 10 s and 40 s after the step, CPU time from `getrusage` between 10 s and 40 s; 2 rounds. Panel never shown: 7.9-8.4 MB before and 8.2-8.4 MB after (no change). Error pill with button (after: with the countdown bar): 17.6-18.3 MB before, 17.2-18.6 MB after (inside the run-to-run spread). "Show indicator: Always", round idle pill on screen: 16.1-16.5 MB, so the idle pill costs +7.8-8.1 MB over a launch that never shows the pill; this is the known first-show cost (AppKit, glass, fonts), paid at launch instead of at the first dictation. CPU at idle with the idle pill: 0.000-0.001 s per 30 s (no timers, no animations, no level metering). Showing the idle pill took 42-64 ms. The native `ProgressView(timerInterval:)` in place of the Core Animation bar (same probe, 2 rounds, 01:30 IST): +1.7-2.0 MB with the error pill shown, +0.9 MB with the idle pill, and 0.56-0.66 s CPU in the 7 s while the bar ran against 0.07-0.08 s without a bar: it redraws in the app process at the frame rate. The pill keeps the Core Animation bar. Launch order (review 2.6 perf #6, 02:10 IST, 5 runs): the idle pill now shows in a main-actor task queued after the hotkey tap start, and takes the pointer's screen instead of the window list. Showing it takes 36-40 ms, none of it before the tap start; before, 42-64 ms (with a first `CGWindowListCopyWindowInfo` of 5-8 ms) ran before the tap start.

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
- ServiceManagement (launch at login, phase 2.5) loads at launch: +16-80 KB (onboarding agent, test binary). Lazy linking does not work: with `-Xlinker -lazy_framework`, ld prints "lazy-load will be ignored for 'ServiceManagement' because deployment target version is too low" and keeps `LC_LOAD_DYLIB`. Accepted (lead, 2026-10-16); no `dlopen` workaround.
- Sparkle 2.10.0 (auto-update, 2026-10-16 01:45-02:01 IST, release agent): `SPUStandardUpdaterController` started at launch. Release builds launched by their binary, idle 35 s, `vmmap --summary` physical footprint, 5 rounds each: without Sparkle 15.0 / 15.6 / 15.4 / 15.5 / 15.4 MB (median 15.4), with Sparkle 16.8 / 15.6 / 15.6 / 16.0 / 15.9 MB (median 15.9). Cost: about +0.5 MB idle. The 16.8 MB round was the first launch, when Sparkle read the feed once (peak 20.7 MB); later launches do no network work until the daily check is due. Sparkle.framework adds 2.7 MB to the bundle.

## History window (phase 3, 2026-10-16, 02:40-02:50 IST)

Spike `spikes/history-memory/` (`build.sh`, `measure.sh`), built like the Settings spike: the real `App/History/{HistoryModel,HistoryView}.swift` and `App/InstalledApp.swift` plus KotobaCore and KotobaStorage sources, over a temporary history of 10,000 synthetic dictations; the window holds the first page (200 rows). Physical footprint from `vmmap --summary`, 2 rounds:

| State | r1 | r2 |
|---|---|---|
| HistoryBase, idle 30 s | 11.8 MB | 11.8 MB |
| HistorySpike, idle 30 s (SwiftUI linked, window never opened) | 12.3 MB | 12.3 MB |
| History window open (8 s after open) | 38.4 MB | 39.0 MB |
| 30 s after close | 36.1 MB | 36.2 MB |

- Opening History adds about +26 MB; about +24 MB stays after close. As for Settings, the part that stays is SwiftUI's loaded runtime: `HistorySpike --leak-check` shows the window, its `NSHostingController` and the `HistoryModel` deallocated 2 s after close. The two windows share that runtime, so opening both costs less than the sum (not measured).
- Store reads (`HistoryStoreTests`, debug build, 10,000 rows of about 30 words): a page of 200 rows about 1 ms, the next page about 1 ms, a search that matches nothing (full scan with `LIKE`) about 3 ms. No FTS index.
- Hot path: the stop reads the front app (bundle id and name) under a `Mutex`: about 83 ns per read (`swiftc -O` probe, 1,000,000 reads). Each saved row has two more text columns.

## Usage pane (phase 3, 2026-10-16)

Spike `spikes/usage-memory/` (`build.sh`, `measure.sh`), built like the History spike: the real `App/Settings/{SettingsWindow,UsagePane}.swift` and `App/InstalledApp.swift` plus KotobaCore, KotobaStorage and KotobaProviders sources, over a temporary history of 10,000 synthetic dictations; Settings opens on the Usage pane, which reads both periods. Physical footprint from `vmmap --summary`, 2 rounds:

| State | r1 | r2 |
|---|---|---|
| UsageBase, idle 30 s | 11.7 MB | 11.7 MB |
| UsageSpike, idle 30 s (SwiftUI linked, window never opened) | 12.4 MB | 12.5 MB |
| Settings open on Usage (8 s after open) | 32.7 MB | 32.6 MB |
| 30 s after close | 30.1 MB | 30.1 MB |

- Opening Settings on the Usage pane adds about +20 MB; about +18 MB stays after close, SwiftUI's loaded runtime as for the other Settings panes (+19-21 MB). `UsageSpike --leak-check`: the window, its `NSHostingController` and the `UsageModel` are deallocated 2 s after close. No Swift Charts: a list of at most a few models says the same, and Charts is one more framework to load.
- Store reads (`UsageLedgerTests`, debug build): both periods over 12,000 ledger rows (10,000 dictations) about 18 ms (three statements per period on the ledger's `time` index). The one-time move of kept dictations into the ledger at the first launch after this change: about 165 ms for 10,000. The footprint rows above were measured with the first design (usage columns on `dictations`); the pane and its reads did not change in kind.
- Hot path: before Cmd-V the pipeline builds one ledger entry per answer, no wait: the word count about 0.4 µs for 50 words and the entry about 0.4 µs (release build, 100,000 runs; the first word count over characters took 11 µs). The entry is written in the save after Cmd-V, in the same transaction. First design, measured: that save went from 91-96 µs to 121-125 µs per dictation (release build, 2,500 saves, 3 runs).

## Insights pane (phase 3, 2026-10-16, 07:00-11:00 IST)

Spike `spikes/insights-memory/` (`build.sh`, `measure.sh`), built like the Usage spike: the real `App/Settings/{SettingsWindow,InsightsPane}.swift` and `App/InstalledApp.swift` plus KotobaCore and KotobaStorage sources, over a temporary history of 10,000 synthetic dictations in 70 days (12,000 ledger rows) and 17 learned words; Settings opens on the Insights pane at 32 s and closes at 45 s. `InsightsNoChart` is the same app without the Swift Charts chart (Charts not linked), so the difference is the cost of Charts. 2 rounds each, two runs: `vmmap --summary` physical footprint (07:00 IST) and `footprint -p` (10:40 IST; it reports about 10 MB more for the same process, rounded to whole MB):

| State | NoChart (vmmap) | Spike (vmmap) | NoChart (footprint) | Spike (footprint) |
|---|---|---|---|---|
| Idle 30 s, window never opened | 17.9 / 17.9 MB | 17.9 / 17.9 MB | 28 / 28 MB | 27 / 26 MB |
| Settings open on Insights | 35.5 / 35.4 MB | 40.7 / 37.9 MB | 45 / 45 MB | 52 / 50 MB |
| 30 s after close | 34.2 / 31.5 MB | 37.6 / 34.8 MB | 44 / 44 MB | 48 / 46 MB |

- Linking Charts loads it at launch, and costs nothing measurable at idle: the idle rows match with and without it. The app links Charts only for this pane.
- Opening the pane adds about +17-20 MB without the chart, as for the other Settings panes (SwiftUI's runtime). The chart adds +2.5-7 MB while shown, of which +2-4 MB stays after close.
- Store reads: the pane's whole read (totals, 30 chart days, a 70-day streak, top apps, learned words) took 16-22 ms in the spike (`swiftc -O`). `InsightsTests.insightsOf10000DictationsStayFast` (10,000 dictations, 3 runs each): 15 ms in release and debug; with 50,000 dictations (a ledger of about a year at 140 dictations a day): 81-83 ms, then 74-94 ms (release, 3 runs) once all-time top apps scan the table instead of a range over the whole `time` index. The cost grows with the ledger: the totals and top apps scan it all (`count(DISTINCT dictation_id)` about a third of it), the chart days read ranges on the `time` index. The read runs on the history store, off the main thread, when the pane appears, and while it is shown after each ledger or dictionary write and at midnight; never at idle. A read that changes no figure does not redraw the pane.
- Recorded length (later the same day): words per minute and time saved now take each speech answer's recorded length from its dictation (`dictations.audio_duration_ms`, by primary key) and fall back to the billed `audio_ms` for a deleted dictation. With the perf test now saving kept dictations (release, 3 runs): 10,000 dictations 20-21 ms, 50,000 dictations 107-151 ms, against 15 ms and 74-94 ms before (a ledger only, no dictation rows to look up).
- Swift Charts logs "Custom UnitPoint values are not supported in AxisValueLabel's anchor property" once per process, also for a chart with default axes (probe, 2026-10-16): Apple's noise, not this pane's axes.

## Learning from edits (phase 2.6, 2026-10-16)

- `NSSpellChecker`: the first auto-learn loads it. Review measurement (`perf26/spell.swift`, 3 runs): `NSSpellChecker.shared` 7.5-33 ms on first use, first `checkSpelling` 1.2-14 ms, then 0.21-0.26 ms per word; footprint +1.28 to +1.34 MB, kept for the process lifetime. It loads only after an edit the owner made, and never while a dictation records or is sent (`EditLearner`). Idle before the first learn: no change to the floor.
- Readback sessions: no thread, observer or timer between sessions. Live per-paste cost: measured at the gate run.

## History audio playback (2026-10-17)

- Play in History makes an `AVAudioPlayer` at the click and drops it when the audio ends or stops; nothing is made at launch or while the pane is closed, so the idle footprint does not change. AVFAudio is loaded at launch for capture already. Probe (02:38 IST, scratchpad `playprobe`, session-local): a `swiftc -O` AppKit process with a prepared `AVAudioEngine`, then one play of a 1.5 s 16 kHz mono FLAC, `phys_footprint` from `task_info`, 3 runs: idle 8.56-8.81 MB; playing +1.80-1.82 MB; after the stop +1.4 MB at 10 s (the system's audio output setup, kept for the process). The first play took 51-71 ms from the click to `play()`.

## Large route primer (2026-10-17)

- The cold-route primer body (`OpenRouterPrimer.swift`, 512,179 bytes: one second of 48 kHz stereo 32-bit noise as WAV, base64 in JSON) is built for each cold primer, off the pipeline actor, and released after its send; only the silent body (under 1 KB) is kept. Probe (scratchpad `primer-mem`, `swiftc -O`, `phys_footprint` from `task_info`, 5 runs): build 1.1-2.1 ms; footprint +544 KiB while held. After release: +544 KiB when the buffer came from `malloc` (the allocator keeps the region), +32 KiB when it is its own `mmap` pages (`Data(bytesNoCopy:deallocator: .unmap)`), which the app uses. Building the WAV and its base64 whole first kept +1.47 MiB. So idle footprint does not change; a cold dictation holds about 0.5 MiB for the primer's round trip (2-4 s).

## Memory after use (2026-10-17, 15:20-16:45 IST)

The owner saw about 50 MB in Activity Monitor. Read-only inspection of the running release 0.4.1 (`footprint`, `vmmap --summary`, `heap`, one `leaks`; raw output in `<runbooks>/2026-10-17-kotoba-memory/`): footprint 68 MB at 25 min and 67.9 MB at 100 min, peak 181 MB. A plateau, not a leak: `leaks` found 0 leaks, and the footprint did not grow between the two reads. Malloc Small is 51 MB of the 68; `heap` counts 42.5 MB allocated in 156,000 blocks. The largest named holders: 62 blocks of 272 KB (17 MB, see 2), Swift metadata 6.4 MB, Objective-C method caches 2.2 MB, CoreSVG symbol trees about 1.5 MB. No kotoba object is larger than `SampleRing` (256 KB).

`make window-memory` (the Debug app binary, offscreen, the main window with the sample panes built, shown on every pane and closed three times; `App/Settings/SettingsSnapshots.swift`) gives the same shape: 8.8 MB at launch, 177-181 MB while open, 68.7 MB 5 s after the last close. One pane at a time (Home first, then the pane), 5 s after close: Home 43.6, Microphone 45.2, Speech 47.5, Usage 49.5, Modes 49.6, Insights 51.8, Dictionary 53.1, History 55.0, General 56.0 MB.

1. **The allocator keeps what the window frees (largest; fixed).** On macOS, libmalloc gives a process the system does not know (any third-party app) per-cluster slots, deferred reclaim and no segment deallocation (`xzone_malloc.c`, apple-oss-distributions/libmalloc). What a window's SwiftUI peak allocates and frees stays in the footprint until quit. `malloc_zone_pressure_relief` returns 0 bytes. Probe `spikes/allocator/` (150 MB in blocks, one in 50 kept): 40,000-byte blocks keep 178 MB after the free; with `MallocSpaceEfficient=1` (libmalloc: "policies usually associated with memory-constrained platforms (iOS) that trade some amount of time efficiency for space efficiency") 5.6 MB. 300-byte blocks keep 155-165 MB either way: a kept block on every page holds the page. A SwiftUI form with 80 switches (`spikes/colorsync/`), after close: 47.7 MB, 26.0 MB in the space-efficient mode.
   - Change: `LSEnvironment` `MallocSpaceEfficient=1` in `project.yml`. Launch Services sets it at each launch (Finder, Dock, login item, Sparkle relaunch); a binary started from the shell does not get it. `make memory` says whether the running app has it.
   - `make window-memory`, 5 runs each: 5 s after the last close median 68.8 MB (62.0-68.9) -> 41.3 MB (40.6-51.6); at launch 8.5 -> 6.1 MB; peak 182.7 -> 159.8 MB.
   - Cost (`swiftc -O` probe, 3 runs): a malloc/free pair 32 -> 53 ns; JSON encode plus decode of a 2 KB answer +0-7 %; a 1 MB base64 body built in 48 KB chunks 0.45 -> 0.55 ms; 4 threads freeing and allocating at once 2-3 times slower (13-20 ms -> 34-49 ms for 2 million pairs). `--snapshot-checks` took 8.5-10.8 s against 8.4-10.9 s (noise). A dictation allocates far less than these loops: the stop path should not move by a measurable amount (owner trial row 951 checks it).
2. **ColorSync curve tables (not changed).** The 272 KB blocks are `CMMParaCurveTag::MakeInvertedTRC` tables (stacks from a memgraph of the snapshot run). ColorSync builds them the first time text or a color is drawn for a display with its own ICC profile: 42 per profile for each of this Mac's two external monitors, in AppKit as in SwiftUI. The cache is bounded: in the spike the count went 72 -> 69 -> 48 as other transforms came in. Most of their pages are never written: drawing the windows in sRGB (`NSWindow.colorSpace`) leaves 6 tables instead of 42 but saves only 0.6-0.8 MB in `make window-memory` and 2.3 MB in the spike, and the menu bar menu, which kotoba cannot set, draws for the display anyway.
3. **SwiftUI's loaded runtime (stays).** Swift metadata, method caches, symbol trees, fonts and the AttributeGraph: what is left after close in the space-efficient mode, about 33-35 MB over launch in `make window-memory`. The window and its models are released on close (as `--leak-check` found in the History, Settings and Usage spikes); an audit of the pipeline, the readback, the pasteboard guard, the providers and the stores found no list, stream or task that grows per dictation or per window. Only a process for the windows that quits on close gives this back (not built; an estimate for the lead).
4. **A graphics peak while some panes show (not found).** With General, Insights, Dictionary or Modes on screen, about 105-110 MB of "owned unmapped (graphics)" (GPU memory the process owns) comes and is freed within a few seconds of offscreen idle; this is the 160-180 MB peak. Not caused by switches, pickers, text fields, app icons, the scroll edge effect or the length of the content (each tried alone in a spike or the probe). On screen, how long it stays while the window is open is not measured.

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
2. Footprint after hours idle and after many dictations: answered in part by "Memory after use" (a plateau at 68 MB from 25 to 100 min on 0.4.1). The footprint of the space-efficient build after a day of use waits for the owner trial (docs/testing/phase2-manual.md, rows 946-951).
3. First-buffer timing on AirPods or other Bluetooth input is not measured.
4. Should Settings and History stay SwiftUI given +15-21 MB that persists after close, or move to AppKit? Accepted for now (see "Settings window"); AppKit panes are the option if the owner wants less.
