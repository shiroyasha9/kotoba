# Codex performance pass

Date: 2026-10-16. Branch: `perf/codex-astra`.

Two production changes reduce temporary upload memory and the data retained by the Recovered menu. User-visible behavior is unchanged. No KotobaCore decisions changed.

No app launch, microphone capture, network request, paid API call, credential read, or owner database read was performed. Package tests use fake ports, intercepted URL requests, and temporary fixture databases. Signing, entitlements, generated project files, and dependencies were not changed.

## Changes

### 1. Release upload read buffers after each chunk

- Location: `KotobaProviders/Sources/KotobaProviders/ProviderHTTP.swift:236`.
- Cause: `BodyWriter` reads 48 KiB at a time, but `FileHandle` produces autoreleased objects. Without an inner pool, temporary read buffers accumulate until the surrounding pool drains. Small Swift `Data` values alone do not bound the live Objective-C buffers.
- Change: put each read, optional base64 conversion, and synchronous write inside an autorelease pool. End-of-file still ends the loop; read and write errors still propagate. The original FLAC stays on disk for retries.
- Gain, measured: about 0.97 MiB less footprint growth for a 1 MiB input and 32.20 MiB less for a 32 MiB input. See the probe below. This fixes a resource-lifetime problem and reduces memory pressure during large uploads. It does not prove a reduction in fresh-launch idle memory or production latency.
- Risk: one pool push/pop per chunk adds work on the stop-to-upload path. No buffer escapes the pool, and `FileHandle.write` completes before it drains. Timing was noisy; a speed improvement is not claimed.
- Verification: provider fixtures pass for OpenRouter JSON and xAI/Azure multipart requests. The existing base64 test at `KotobaProviders/Tests/KotobaProvidersTests/OpenRouterProviderTests.swift:45` now covers 0, 49,151, 49,152, 49,153, 49,154, and 150,001 bytes. These cover EOF, exact chunk boundaries, multiple chunks, and both base64 padding lengths. The test change has no production cost.

### 2. Retain menu previews instead of full recovered records

- Locations: `App/AppDelegate.swift:41`, `:223`, and `:309`.
- Cause: the app retained every full recovered record from the last 24 hours. The menu needs only a title and ID. On every menu open it also rebuilt these titles and counted each full transcript. Copy already reads the full record from the store at `App/AppDelegate.swift:274`.
- Change: project recovered records into `MenuChoice` values when history refreshes. Keep a 40-character preview, an ellipsis when needed, and the record ID. Examine at most 41 characters to decide truncation. The menu reuses those values.
- Gain, estimated: retained text changes from the full raw and cleaned transcripts to the previews. For 100 recovered records with 20 KiB of unique ASCII transcript text each, the retained text payload falls from about 1.95 MiB to about 4.2 KiB, plus IDs and collection overhead. Cleaned text can increase the saving. Actual process footprint and allocator release were not measured. Empty queues have no saving. Title construction moves off menu opening, and truncation no longer walks an arbitrarily long transcript.
- Risk: a preview must never replace the text used for Copy. The existing ID-based store read remains in place. History refreshes still read full records temporarily, so peak query memory and unbounded queue size are not fixed here.
- Verification: all app sources typecheck with Swift 6, complete concurrency checking, and warnings as errors. A standalone probe compared old and new titles for 50 cases: nil, empty, lengths around 40, long strings, combining accents, emoji, flags, CRLF, CJK, and Devanagari. All titles matched. Owner verification: recover a long transcript, check its menu title, copy it, and confirm the complete text reaches the clipboard. Include a cleanup dictation to check that cleaned text is copied.

## Upload measurement

The probe ran on macOS 27.0.1, arm64, with Apple Swift 6.4. It compiled the exact old and revised `BodyWriter` implementations with `swiftc -O -swift-version 6`. It used existing synthetic files of 1 MiB + 1 byte and 32 MiB + 1 byte, filled with byte 123, and encoded them to temporary files without URLSession. Input file creation was outside the measurement. Five alternating before/after runs used fresh processes for each size and version.

Each run wrapped the operation in an outer autorelease pool and sampled `task_info(TASK_VM_INFO).phys_footprint` immediately before and after body construction, before that outer pool drained. This is the physical-footprint metric used by `footprint`; these are standalone process deltas, not app idle measurements or sampled peak values. The extra byte exercises a partial last chunk.

| Input | Before: median footprint rise | After: median footprint rise | Reduction | Median body time before / after |
|---|---:|---:|---:|---:|
| 1 MiB + 1 byte | 2.219 MiB | 1.250 MiB | 0.969 MiB | 9.09 / 7.85 ms |
| 32 MiB + 1 byte | 33.422 MiB | 1.219 MiB | 32.203 MiB | 104.81 / 81.35 ms |

The 32 MiB footprint rise ranged from 33.328-33.438 MiB before and 1.188-1.359 MiB after. Its body times ranged from 80.24-205.79 ms before and 63.29-206.09 ms after. Concurrent build activity and filesystem effects make those timings unsuitable for a speed claim. The memory difference was consistent. Pool drainage also does not guarantee that freed allocator pages immediately return to the OS.

A review rerun on 2026-10-16 (same `BodyWriter` code and sampling, 3 alternating runs per version, 32 MiB + 1 byte) measured a footprint rise of 32.422 MiB before and 0.297 MiB after in every run: a 32.1 MiB reduction, the same as above. In the before version the rise also stayed after the outer pool drained.

The probe sources are in `spikes/upload-pool/`: `body-before.swift` and `body-after.swift` contain the exact implementations and footprint sampling, and its README gives the compile and run commands. Inputs and outputs go to the system temporary directory. On another checkout, extract `BodyWriter` before and after this change and use the same input sizes, outer-pool lifetime, and sampling points. No production credential or audio is needed.

## Validation and limits

- Passed: all 265 package tests - KotobaCore 164, KotobaProviders 57, KotobaStorage 44. Parameterized cases are included within those test counts.
- Passed: repository-wide `make format-lint` and `swiftlint lint --no-cache --strict --quiet`. No lint rule or limit changed.
- Passed: all `App/**/*.swift` files typechecked together with Swift 6, `-strict-concurrency=complete`, `-warnings-as-errors`, and target `arm64-apple-macos26.0`, against the freshly built package modules.
- Passed: 50 menu-preview equivalence cases and `git diff --check`. Changed Swift files remain below 400 lines.
- Package builds and tests used `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE` pointing to `build/ModuleCache`, agent-specific `.build-codex-astra` paths, `--disable-automatic-resolution`, and `--disable-sandbox`. The last option disables Swift's nested subprocess sandbox, which cannot start inside this runner; the outer workspace sandbox remains in force. Tests used the repository's 120-second timeout wrapper. Direct app typechecking also required Swift's `-disable-sandbox` for the Observation macro subprocess.
- Passed: `make check AGENT=codex-review` on 2026-10-16 in a review outside the Codex sandbox (swift-format, `swiftlint --strict`, xcodebuild, and 265 tests: KotobaCore 164, KotobaProviders 57, KotobaStorage 44). The Codex sandbox itself could not run the Xcode build, because Xcode tried to write under the protected user SwiftPM cache.
- No UI layout or text changed; no app or snapshot process was launched. Live copying, fresh-launch `footprint`, post-use app footprint, microphone behavior, and the p50 <= 1.0 s / p90 <= 1.5 s latency gates remain owner checks. Do not treat the standalone upload probe as a gate result.

## Ideas not selected

- Release the indicator after hiding: existing measurements show about 0.25 MiB reclaimed but 21-46 ms to show it again versus 4-8 ms when retained. Its current lazy creation is already the better tradeoff.
- Replace SwiftUI settings with AppKit: the measured 19-21 MiB retained runtime cost is accepted in the spec. A UI rewrite is much larger than this pass and does not improve the unopened-window idle gate. Existing window controllers clear their window references on close.
- Lazy-link SwiftUI or ServiceManagement: existing measurements put link-only costs at about 0.1 MiB and 16-80 KiB. Private/runtime loading workarounds are excluded.
- Defer audio preparation: this trades a small idle cost for first-word latency and conflicts with the agreed prepared-engine behavior. The capture ring is already small and not zero-filled.
- Replace the streamed upload with an in-memory body: this would reintroduce audio-sized buffers. Keep the file upload and fix its temporary-object lifetime instead.
- Add pooling to the capture writer without evidence: a synthetic probe using the unchanged `CaptureWriter` failed at `AVAudioFile(forWriting:)` with AVFAudio error 1718449215. It never opened the mic. No capture-memory or timing conclusion follows from that failed probe, so the real-time path was left unchanged.
- Build provider clients lazily: it could avoid unused session objects, but their retained cost was not measured. It also moves setup toward the first use. Keep the long-lived sessions and key-down warm-up.
- Delay dictionary/history loading or remove initial retry work: first dictation terms and recovery at launch are required behavior. They need an ordering analysis and seam tests before changing when they run.
- Remove pending-record persistence from the delivery path: it protects crash recovery. No storage-contention measurement supports weakening that guarantee.
- Add regex caches or database indexes: replacement performance was already measured in the earlier pass; there is no new workload or query-plan evidence here to justify more retained state or a schema change.
- Rewrite task ownership, retry pagination, or retention policy: AppDelegate has unowned observation tasks, and queue reads can still grow with history. These require lifecycle and ordering tests. A broad rewrite during a small measured performance pass would add more risk than the selected changes.

## Unresolved questions

1. What are fresh-launch and post-dictation app footprints in Debug and Release on the same machine, with no window opened? No new idle result was collected here.
2. Does the per-chunk pool change `uploadStart` to `bodyReady` timing in a quiet Release build, and do real stop-to-paste percentiles still meet the gates? The local timing sample cannot answer this.
3. How large do recovered and retry queues become in daily use? Menu retention is reduced, but full-record queries, copy lookup, and retry result arrays are still proportional to queue size.
4. Does the synthetic FLAC writer's format error occur in an owner-run probe outside this sandbox? CaptureWriter's existing conversion/write failure paths and audio route-change races still need a focused fault-injection pass.
5. Which long-lived AppDelegate tasks should end before pipeline shutdown, and how should in-flight capture and retry work settle? This pass does not establish complete task/observer lifecycle safety.
