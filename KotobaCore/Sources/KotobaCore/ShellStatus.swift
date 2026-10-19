import Foundation

/// The shell: the menu bar icon, the first line and counts of the menu bar and Dock menus, the Dock badge and the start
/// and stop cues. AppDelegate collects the facts and draws what this decides; the pill reads `DictationState` itself.
///
/// It keeps what only the shell tracks (the pipeline's last state, the history's queue counts, a queue read in flight)
/// and takes the facts other owners keep (grants and key, the release app, a waiting update) at each draw, so it holds
/// no second copy of them.
public struct ShellStatus: Sendable, Equatable {
    public enum Icon: Sendable {
        case ready
        /// Setup is not complete, a dictation waits for a retry, or an update waits.
        case needsAttention
        case listening
    }

    /// The menu's first line. `Missing` is the first thing setup still needs (the App's `Readiness.Missing`).
    public enum MenuStatus<Missing: Sendable & Equatable>: Sendable, Equatable {
        /// The history database did not open at launch.
        case historyUnavailable
        /// A development build gives way to the release app (`InstallYield`).
        case yieldsToRelease
        /// The dictation's own words, as the pill says them.
        case dictation(DictationState)
        /// Idle with setup not complete: "Finish Setting Up kotoba…" with the first thing to do.
        case finishSetup(Missing)
        /// Idle and ready: how to dictate.
        case ready
    }

    /// What other owners keep, read fresh at each draw.
    public struct Facts<Missing: Sendable & Equatable>: Sendable, Equatable {
        /// The first thing setup still needs; nil when kotoba is ready.
        public var firstMissing: Missing?
        /// A development build while the release app runs.
        public var isYielding: Bool
        public var hasWaitingUpdate: Bool

        public init(firstMissing: Missing? = nil, isYielding: Bool = false, hasWaitingUpdate: Bool = false) {
            self.firstMissing = firstMissing
            self.isYielding = isYielding
            self.hasWaitingUpdate = hasWaitingUpdate
        }
    }

    public struct View<Missing: Sendable & Equatable>: Sendable, Equatable {
        public var icon: Icon
        public var status: MenuStatus<Missing>
    }

    /// What the shell does once for a new pipeline state.
    public struct Reactions: Sendable, Equatable {
        public var cue: CueVoice.Cue?
        /// A recording just started: read Secure Input now, for the pill's note.
        public var readsSecureInput = false
        /// The pill shows a recording, so a click on it stops the dictation (`HotkeyClassifier.isRecordingShown`).
        public var isRecordingShown = false
        /// The state's text and button depend on the mic and Accessibility grants now: read them again.
        public var readsGrants = false
        /// A recovered text the store could not write is listed from memory, with no history write to announce it:
        /// read the queues (`queueReadRequested`).
        public var readsQueues = false

        public init(
            cue: CueVoice.Cue? = nil, readsSecureInput: Bool = false, isRecordingShown: Bool = false,
            readsGrants: Bool = false, readsQueues: Bool = false
        ) {
            self.cue = cue
            self.readsSecureInput = readsSecureInput
            self.isRecordingShown = isRecordingShown
            self.readsGrants = readsGrants
            self.readsQueues = readsQueues
        }
    }

    /// One menu item of the Recovered list: the start of the recovered text.
    public struct RecoveredPreview: Sendable, Equatable {
        public var id: DictationID
        public var title: String
    }

    /// The menu's counts from one read of the history.
    public struct Queues: Sendable, Equatable {
        /// Dictations that wait for a retry: the menu's Retry item, the icon's dot and the Dock badge.
        public var waitingCount = 0
        /// Recovered texts of the last 24 h, newest first.
        public var recovered: [RecoveredPreview] = []
        /// A dictation was pasted or copied, so the Last Dictation items have something to send.
        public var hasLastDictation = false
        /// The last dictation was cleaned up, so "Paste Last Without Cleanup" has the raw transcript.
        public var hasRawLastDictation = false

        /// A recovered text's menu item shows this many characters of it.
        static let previewLength = 40

        public init() {}

        /// `recovered` as the store and the retry queue list them.
        public init(
            waitingCount: Int, recovered: [DictationRecord], hasLastDictation: Bool, hasRawLastDictation: Bool
        ) {
            self.waitingCount = waitingCount
            self.recovered = recovered.map { record in
                let preview = (record.deliveredText ?? "").prefix(Self.previewLength + 1)
                let title =
                    preview.count > Self.previewLength ? preview.prefix(Self.previewLength) + "…" : preview
                return RecoveredPreview(id: record.id, title: String(title))
            }
            self.hasLastDictation = hasLastDictation
            self.hasRawLastDictation = hasRawLastDictation
        }
    }

    /// The pipeline's last state.
    public private(set) var dictation = DictationState.idle
    /// The last queue read.
    public private(set) var queues = Queues()
    private var queueRead = QueueRead.none
    /// Set when the history database does not open; the menu says so instead of the status.
    public var isHistoryUnavailable = false

    public init() {}

    /// The pipeline's new state.
    public mutating func dictationChanged(_ state: DictationState) -> Reactions {
        let wasRecording = dictation.phase.isRecording
        dictation = state
        let isRecordingStart = state.phase.isRecording && !wasRecording
        // The mic can also go silent because its access was turned off while kotoba runs.
        let isSilent = if case .recording(_, isSilent: true, _) = state.phase { true } else { false }
        let isRecovered = if case .recovered = state.notice { true } else { false }
        return Reactions(
            cue: isRecordingStart ? .start : wasRecording && state.phase == .transcribing ? .stop : nil,
            readsSecureInput: isRecordingStart, isRecordingShown: state.phase.isRecording,
            readsGrants: state.notice?.dependsOnGrants ?? isSilent, readsQueues: isRecovered)
    }

    /// A history write or a reaction asks for a queue read. True: start one now. False: one runs, and it reads once
    /// more when it ends.
    public mutating func queueReadRequested() -> Bool {
        switch queueRead {
        case .none:
            queueRead = .running
            return true
        case .running, .due:
            queueRead = .due
            return false
        }
    }

    /// A queue read ended with `queues`. True: a request came while it ran, so read again.
    public mutating func queueRead(_ queues: Queues) -> Bool {
        self.queues = queues
        let isDue = queueRead == .due
        queueRead = isDue ? .running : .none
        return isDue
    }

    /// The icon and the menu's first line for `facts` now.
    public func view<Missing>(_ facts: Facts<Missing>) -> View<Missing> {
        let icon: Icon =
            if dictation.phase.isRecording {
                .listening
            } else if facts.firstMissing != nil || queues.waitingCount > 0 || facts.hasWaitingUpdate {
                .needsAttention
            } else {
                .ready
            }
        let status: MenuStatus<Missing> =
            if isHistoryUnavailable {
                .historyUnavailable
            } else if facts.isYielding && !dictation.phase.isLive {
                .yieldsToRelease
            } else if dictation != .idle {
                .dictation(dictation)
            } else {
                facts.firstMissing.map { .finishSetup($0) } ?? .ready
            }
        return View(icon: icon, status: status)
    }
}

extension ShellStatus {
    private enum QueueRead {
        case none
        case running
        /// A request came while the read ran: one more read follows it.
        case due
    }
}
