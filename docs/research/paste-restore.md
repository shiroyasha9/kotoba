# Paste restore: the read is not the hand-over

Date: 2026-10-19, 17:13-18:00 IST. Machine: M3 Pro, macOS 27. Code: `spikes/paste-race/` (throwaway).

## The failure

A dictation into cmux (a Ghostty-based terminal) pasted nothing, and the transcript was not on the clipboard. The unified log (`com.apple.CFPasteboard`, info level) shows the order:

| Time (IST) | Process | Event |
|---|---|---|
| 17:13:03.748 | `cmux-paste-text-worker` | CopyData, generation 116: "Will request data from daemon" |
| .748 | kotoba | "Promise fulfilled - 72 bytes" (the read signal); kotoba restores at once: BeginGeneration, generation 117 |
| .748 | pboard | "Promise resolved with result: 1" |
| .749 | `cmux-paste-text-worker` | "result: -6 generation: 116 null data" |
| .750 | `cmux-paste-text-worker` | reads generation 117: the restored clipboard, an image; a terminal pastes nothing |

The next dictation, 14 s later, worked: the worker got its 171 bytes about 1 ms before kotoba's restore. The margin was about 1 ms either way.

## What macOS tells the writer

Nothing after the ask. `NSPasteboardItemDataProvider` has two methods: the ask for the data, and `pasteboardFinishedWithDataProvider(_:)`, called when "the data provider has fulfilled all promises, or because ownership of the pasteboard has changed" (https://developer.apple.com/documentation/appkit/nspasteboarditemdataprovider/pasteboardfinishedwithdataprovider(_:)). There are no pasteboard notifications (Hammerspoon polls: https://hammerspoon.org/docs/hs.pasteboard.watcher.html). Jot's code says the same: "there is no OS-level delivery receipt for synthetic paste" (https://github.com/google-gemini/jot-gemini-transcribe-macOS/blob/9976926959a6043eac01ffff4d914a7c7762ecfa/JotCore/Sources/InsertionEngine/InsertionCoordinator.swift#L75-L77).

A target can also need the clipboard after its read. cmux keeps the change count from the Cmd-V and drops the paste when it moved, before and after the read (`workers/cmux-paste-text/main.m` L181, L218 at `f6532b1`; https://github.com/manaflow-ai/cmux/blob/f6532b1d361fa8a1a8562a8ddcb76b9a63be6d33/workers/cmux-paste-text/main.m). Its PR #14549: "Dictation tools restore the clipboard about 100 ms after Cmd+V" (https://github.com/manaflow-ai/cmux/pull/14549). Chromium reads the types, the text, then `org.chromium.source-url` in one paste.

## Spike

`spikes/paste-race/`: a writer promises text on a private named pasteboard (not the general one), a reader process reads it, and the writer restores at a variant's moment.

| Variant | Lost reads |
|---|---|
| Restore at once after the ask (kotoba before this fix) | 2 of 300; 380 of 1000 in a second run |
| Restore at `pasteboardFinishedWithDataProvider` | 120 of 300 (it comes before the hand-over) |
| Restore 1, 5 or 20 ms after the ask | 0 of 300 each |

From the ask to the reader having the text: p50 0.12 ms, p99 0.19 ms, max 0.53 ms (1000 reads, idle Mac).

## What other apps do

Only Handy also uses a promised item as the read signal. It restores 200 ms after the last read, with an 8 s cap and a change count guard; macOS users report that it fixed the old-clipboard paste (`src-tauri/src/paste_tx/mod.rs` L27-32, L50-63 at `a70ac84`, https://github.com/cjpais/Handy/issues/502). The others restore after a fixed time from the Cmd-V: Espanso 300 ms, OpenWhispr 450 ms, Hex 500 ms, FreeFlow and Jot 1 s, OpenSuperWhisper 1.5 s (100 ms failed), VoiceInk 2 s. Keyboard Maestro stopped restoring. Accessibility insertion does not reach a terminal (Ghostty's AX is read-only).

## Decision

Keep the promised item and restore `ClipboardGuard.readSettle` (200 ms, as in Handy; owner, 2026-10-19) after the paste target's read. The read still sets the time, so a busy app that reads late still gets the transcript (Handy #502). The 200 ms covers the hand-over (under 1 ms), a target's check after its read, and a second read in the same paste, with room under load. The cost: the owner's clipboard comes back 0.2 s later, and the change count guard keeps a copy made in that time. The hot path does not change (the restore is after the Cmd-V).

## To revisit

- If a paste is lost again: confirm it in the log first (`log show --info --predicate 'subsystem == "com.apple.CFPasteboard"'` around the paste; a reader's "result: -6" or a read of the restored generation). Info lines stay only a short time, so read them soon. Then raise `readSettle` toward 300 ms (Espanso) or 500 ms (Hex). The cost of a longer settle is small: a ⌘V in it pastes the transcript again, and the change count guard keeps any copy made in it.
- Not done: a floor of about 1 s from the first read (research recommendation). It guards against a clipboard manager that ignores the nspasteboard.org markers and reads after the Cmd-V but before the target (Alfred did in Handy #502). The owner uses Raycast only, which honors the markers (seen in the 2026-10-19 log: it read only the restored generation). Add it if such a manager comes into use.
- Pick the settle from data: the gap per target app from "Promise fulfilled" to the reader's last pasteboard access, read from the CFPasteboard log for cmux, Chrome, Slack, Terminal and a native text view.
