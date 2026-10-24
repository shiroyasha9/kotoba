import KotobaCore
import SwiftUI

// MARK: - Snapshots

@MainActor
extension Pane {
    static func shortcutsSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .shortcuts(.sample()), named: "settings-shortcuts", height: 1_000),
            // Push to talk on its own chord: its line adds the double press.
            MainWindow.snapshot(
                of: .shortcuts(.sample(chords: HotkeyChords(defaults: nil, pushToTalk: Chord(modifiers: .option)))),
                named: "settings-shortcuts-push-to-talk", height: 1_000),
            // Cleanup off: its recorder says Off and offers Reset.
            MainWindow.snapshot(
                of: .shortcuts(.sample(chords: HotkeyChords(defaults: nil, cleanup: nil))),
                named: "settings-shortcuts-cleanup-off", height: 1_000),
        ]
    }
}
