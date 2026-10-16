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
        /// The mode of the app in front at key-down cleans every dictation: the cleaner warms and the pill says so. The
        /// app in front at the stop decides in the end (`output`).
        let cleansAtKeyDown: Bool
        /// The cleaner's connection was warmed for this dictation, so a later step does not warm it again.
        var isCleanerWarm = false
        /// The indicator and start cue are on. They wait until the press is a tap (released in
        /// time) or a hold (threshold passed), so a shortcut press shows and plays nothing.
        var isAnnounced = false
        let captureEvents: Task<Void, Never>
        /// The clipboard, taken at the announcement (so a shortcut press reads nothing) while capture runs.
        var clipboard: ClipboardGuard.Pending?
        let warning: Task<Void, Never>
        let announcement: Task<Void, Never>
        /// Whether the mic gave sound lately, for the no-sound warning.
        var sound: NoSoundPolicy
        /// The timer at `sound.deadline`; nil while the warning shows.
        var soundDeadline: Task<Void, Never>?
        /// The front app at the stop; a submit Return goes only to it, and its mode decides `output`.
        var frontAppAtStop: FrontApp?
        /// What the dictation does with its transcript, decided at the stop.
        var output = DictationOutput.transcript

        /// The pill marks the dictation as one that will be cleaned up.
        var isCleaned: Bool { isCleanupSeen || cleansAtKeyDown }
    }
}
