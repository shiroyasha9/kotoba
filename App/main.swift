import AppKit

// Before anything reads a setting: the AppDelegate's stored properties read some at init.
AppDefaults.registerDefaults()

// Then, so a snapshot run (`--snapshots <folder>`) builds no hotkey tap and no audio engine; it exits when done.
Snapshots.runIfRequested()

// Then, before the delegate builds any service: a second copy of this install hands over to the running one and quits,
// so it never records, pastes or bills beside it (`CopyHandOver`).
if let running = CopyHandOver.runningCopy() {
    let handOver = CopyHandOver(to: running)
    NSApplication.shared.delegate = handOver
    NSApplication.shared.run()
} else {
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.run()
}
