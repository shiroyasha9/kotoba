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
4. Should Settings and History stay SwiftUI given +15 MB that persists after close, or move to AppKit?
