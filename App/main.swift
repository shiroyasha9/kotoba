import AppKit

// First, so a snapshot run (`--snapshots <folder>`) builds no hotkey tap and no audio engine; it exits when done.
Snapshots.runIfRequested()

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
