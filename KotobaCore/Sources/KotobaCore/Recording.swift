import Foundation

extension DictationPipeline {
    /// One dictation from key-down until it is stopped, cancelled or dropped.
    struct Recording {
        let id: DictationID
        let file: URL
        let startedAt: Instant
        /// True until the chord-up that decides tap or hold.
        var isUndecided: Bool
        /// The cleanup modifier was seen before the announcement; it cannot change after it.
        var isCleanupSeen = false
        /// The indicator and start cue are on. They wait until the press is a tap (released in
        /// time) or a hold (threshold passed), so a shortcut press shows and plays nothing.
        var isAnnounced = false
        let captureEvents: Task<Void, Never>
        /// The clipboard, taken at the announcement (so a shortcut press reads nothing) while capture runs.
        var clipboard: ClipboardGuard.Pending?
        let warning: Task<Void, Never>
        let announcement: Task<Void, Never>
    }
}
