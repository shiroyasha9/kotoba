import Foundation

/// The owner's files: ~/Library/Application Support/kotoba/. This is the one place that names them. The stores take
/// their location as an argument with no default, so the package tests cannot open these files, and a snapshot run
/// stops here before it can.
@MainActor
enum AppFiles {
    static var directory: URL {
        precondition(!Snapshots.isRunning, "A snapshot run must not open the owner's files")
        return URL.applicationSupportDirectory.appending(path: "kotoba", directoryHint: .isDirectory)
    }

    /// The history, the retry queue and the usage ledger. `scripts/latency.sh` reads this path too.
    static var history: URL { directory.appending(path: "kotoba.sqlite") }
    /// Its own file, so a dictionary write never blocks a dictation save.
    static var dictionary: URL { directory.appending(path: "dictionary.sqlite") }
    static var audio: URL { directory.appending(path: "audio", directoryHint: .isDirectory) }
}
