# kotoba

Native macOS menu-bar dictation: tap a chord, speak, tap again, the cloud transcript is pasted in about one second. Read `docs/spec.md` before feature work: it holds the agreed decisions, gates and phases. `docs/research/` holds the evidence behind them.

## Commands

- `make check`: the bar for every change (swift-format lint, `swiftlint --strict`, xcodebuild, `swift test`). Done means green.
- `make format`: fixes formatting in place.
- `make test`: KotobaCore tests only, the fast loop.
- `make gen`: regenerates `Kotoba.xcodeproj` from `project.yml`. Edit `project.yml`; the project, `App/Info.plist` and `App/Kotoba.entitlements` are generated.
- `bench/`: provider benchmark (bun, TypeScript), see `bench/README.md`. Runs against paid APIs need the owner's explicit go.

## Module boundaries

- `KotobaCore/`: pure Swift package. `DictationPipeline` (actor) takes hotkey events and drives six ports: `AudioSource`, `TranscriptionProvider`, `Paster`, `Pasteboard`, `PipelineClock`, `Store`. Every decision lives here: tap vs hold, Esc, the 10-minute warning, retry queue, clipboard restore rules, latency marks. Imports Foundation, os and Synchronization only (lint-enforced).
- `App/`: AppKit menu-bar app (`LSUIElement`). Thin adapters that implement the ports with AVAudioEngine, CGEventTap, NSPasteboard, URLSession, SQLite and the Keychain, plus the indicator panel and on-demand windows.
- `spikes/`: throwaway experiments, outside `make check`.

## Rules

- **Licence**: copy code only from MIT or Apache-2.0 projects (Jot, Hex, FreeFlow). Keep their notice at the top of the copied file and add an entry to `NOTICE`. GPL projects (VoiceInk, TypeWhisper) are read-only references: take ideas, write your own code.
- **Event-driven hot path** (key-down to Cmd-V sent): each step waits on its event (first audio buffer, HTTP response, pasteboard change). A real timeout sleeps on the injected `PipelineClock`, so tests control it.
- **One long-lived URLSession per provider**, created in the provider's init and warmed at key-down. Lint flags every `URLSession(`; that one line carries `// swiftlint:disable:next url_session_construction`.
- **Gates**: latency from stop tap to Cmd-V sent p50 <= 1.0 s and p90 <= 1.5 s; idle memory is measured with `footprint` (floor in `docs/research/memory-spike.md`). A change that adds work to the hot path or loads a framework at launch reports its measured cost.
- **Test-first through the seam**: hotkey events in, assertions on the fakes out. `KotobaCore/Tests/KotobaCoreTests/DictationPipelineTests.swift` shows the style.
- **Signing**: every build uses the Developer ID in `project.yml` (team 7U6G55576W), so TCC grants and Keychain access survive rebuilds. The keychain holds another team's identity; keep the full identity name.
- **Permissions**: the owner clicks Allow on every TCC prompt. Stop and ask when a prompt blocks you.

Code style and patterns: `CODING_STANDARDS.md`.
