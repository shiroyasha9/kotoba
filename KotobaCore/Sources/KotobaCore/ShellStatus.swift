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
        let was = Phase(dictation)
        let phase = Phase(state)
        dictation = state
        let isRecordingStart = phase.isRecording && !was.isRecording
        return Reactions(
            cue: isRecordingStart ? .start : was.isRecording && phase == .transcribing ? .stop : nil,
            readsSecureInput: isRecordingStart, isRecordingShown: phase.isRecording, readsGrants: phase.readsGrants,
            readsQueues: phase == .recovered)
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
        let phase = Phase(dictation)
        let icon: Icon =
            if phase.isRecording {
                .listening
            } else if facts.firstMissing != nil || queues.waitingCount > 0 || facts.hasWaitingUpdate {
                .needsAttention
            } else {
                .ready
            }
        let status: MenuStatus<Missing> =
            if isHistoryUnavailable {
                .historyUnavailable
            } else if facts.isYielding && !phase.isLive {
                .yieldsToRelease
            } else if phase != .idle {
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

    /// What the shell needs to know of a `DictationState`. The only place this module reads one.
    private enum Phase: Equatable {
        case idle
        case recording(isSilent: Bool)
        case transcribing
        /// A live dictation past its recording, or an Undo window: its own text comes first.
        case working
        /// A recovered text: a retry transcribed a queued dictation.
        case recovered
        /// An error or a delivery note: the dictation is past. `readsGrants`: its text and button depend on the mic
        /// and Accessibility grants now (I2).
        case outcome(readsGrants: Bool)

        init(_ state: DictationState) {
            self =
                switch state {
                case .idle: .idle
                case .recording(_, let isSilent, _): .recording(isSilent: isSilent)
                case .transcribing: .transcribing
                case .cleaning, .undoable, .polishing: .working
                case .recovered: .recovered
                case .captureFailed, .copied: .outcome(readsGrants: true)
                case .failed, .timedOut, .connectionBlocked, .hostNotFound, .needsSetup, .rejected, .cleanupFailed,
                    .cleanupTooSlow, .returnSkipped, .nothingRecorded, .audioNotSaved, .audioCut, .clipboardNotKept,
                    .polished, .polishFailed:
                    .outcome(readsGrants: false)
                }
        }

        var isRecording: Bool {
            if case .recording = self { true } else { false }
        }

        /// A dictation the owner is still in: a recording, its transcript and cleanup, an Undo window, a Polish.
        var isLive: Bool {
            switch self {
            case .recording, .transcribing, .working: true
            case .idle, .recovered, .outcome: false
            }
        }

        /// The mic can also go silent because its access was turned off while kotoba runs.
        var readsGrants: Bool {
            self == .outcome(readsGrants: true) || self == .recording(isSilent: true)
        }
    }
}
