# kotoba

A native macOS menu-bar dictation app: tap a shortcut, speak, tap again, and your words are pasted into the app you are using.

## Features

- Tap ⌃⌥⌘ to start and stop, or hold it while you speak. Esc cancels. You can change the shortcut in Settings.
- Text goes into the focused app (terminals, editors, browsers, chat), and your clipboard comes back after the paste.
- Cloud speech models through your own OpenRouter key. No account, no telemetry. Keys stay in the macOS Keychain.
- A personal dictionary for names and technical words, plus replacement rules. You can import your Wispr Flow dictionary.
- When you correct a word right after a paste, kotoba learns the correction or suggests it for your dictionary.
- A second shortcut for cleanup: it removes filler words and fixes punctuation.
- A failed dictation keeps its audio, and you can try it again. Nothing you say is lost.
- Choose your microphone, and set the order in which kotoba prefers them.
- Small and native (AppKit), with a floating indicator that shows what kotoba is doing.

## Install

Requires macOS 26 or later.

1. Download the latest `kotoba-<version>.dmg` from [Releases](https://github.com/shiroyasha9/kotoba/releases).
2. Open it and drag kotoba to Applications.
3. Open kotoba from Applications. It appears in the menu bar, not in the Dock.

kotoba updates itself with [Sparkle](https://sparkle-project.org). It checks once a day; turn this off in Settings > General. You can also click "Check for Updates…" in the menu.

## First run

A setup window walks you through three steps, then lets you try a dictation:

1. **Microphone.** Allow microphone access when macOS asks.
2. **Accessibility.** Turn on kotoba in System Settings > Privacy & Security > Accessibility. kotoba needs it to notice the shortcut in every app and to paste your text.
3. **OpenRouter key.** Create a key at [openrouter.ai](https://openrouter.ai) and paste it. You pay OpenRouter for the audio you send.

## Build from source

You need Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. In `project.yml`, set `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` to your own signing identity and team. The values in the repository belong to the maintainer and do not work on your Mac.
2. If you publish your own builds, also change `SUFeedURL` and `SUPublicEDKey` in `project.yml` (see `docs/release.md`).
3. Run:

   ```sh
   make gen     # generates Kotoba.xcodeproj from project.yml
   make build   # builds the app into build/DerivedData
   ```

`make check` runs the formatter, the linter, the build and the tests (it also needs `swiftlint`). `AGENTS.md` and `CODING_STANDARDS.md` describe how the code is organised.

## Licence

Apache License 2.0, see [LICENSE](LICENSE). Third-party code and its licences are listed in [NOTICE](NOTICE).
