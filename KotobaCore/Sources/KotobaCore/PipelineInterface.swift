import Foundation

/// A key event from the Ctrl+Opt+Cmd chord or Esc, as the app's event tap reports it.
public enum HotkeyEvent: Sendable, Equatable {
    case chordDown
    /// The whole cleanup chord (the chord plus Shift by default) was down at some moment of this
    /// press. A dictation not yet announced becomes a cleanup dictation; later, it is ignored.
    case cleanupModifier
    case chordUp
    case escape
    /// A non-modifier key went down while the chord was held: the chord was part of another
    /// app's shortcut, not a dictation.
    case chordInterrupted
}

/// What the indicator shows.
public enum DictationState: Sendable, Equatable {
    case idle
    /// `isLong` turns on after `Settings.longRecordingWarning`; recording never stops on its own.
    case recording(isLong: Bool)
    case transcribing
    /// Esc cancelled the recording and the mic is off. Undo (or a chord tap) resumes it until
    /// `Settings.undoWindow` passes; then the cancel is final.
    case undoable
    /// Transcription failed. The audio is kept and queued for retry.
    case failed(DictationID)
    /// The route refused the request; a retry cannot help. The audio is kept.
    case rejected(DictationID, RejectReason)
    /// The route needs an API key. The audio is kept and retried when the owner saves one.
    case needsSetup(DictationID, SetupItem)
    /// The cleanup failed, so the raw transcript was pasted.
    case cleanupFailed(DictationID)
    /// Paste was not allowed, so the transcript is on the clipboard.
    case copied(DictationID)
    /// A retry transcribed a queued dictation; the menu lists it under Recovered.
    case recovered(DictationID)
    /// Capture did not start: no microphone access or no input device.
    case captureFailed

    /// What the indicator shows once a dictation reaches `record.status`.
    static func outcome(of record: DictationRecord) -> Self {
        switch record.status {
        case .recovered: .recovered(record.id)
        case .rejected: .rejected(record.id, record.rejectReason ?? .other)
        case .copied: .copied(record.id)
        case .failed where record.needsSetup != nil: .needsSetup(record.id, record.needsSetup ?? .key)
        case .failed, .pending: .failed(record.id)
        case .pasted, .cancelled: .idle
        }
    }
}

extension DictationPipeline {
    public struct Ports: Sendable {
        public let audio: any AudioSource
        public let provider: any TranscriptionProvider
        public let paster: any Paster
        public let pasteboard: any Pasteboard
        public let clock: any PipelineClock
        /// The pipeline wraps it so each write is announced on `historyChanges`.
        public internal(set) var store: any Store
        /// Cleans the transcript of a cleanup dictation; nil pastes the raw transcript.
        public let cleaner: (any TextCleaner)?
        /// What the current route still needs before it can send (a key or an endpoint); nil when ready.
        public let missingSetup: @Sendable () async -> SetupItem?

        public init(
            audio: any AudioSource,
            provider: any TranscriptionProvider,
            paster: any Paster,
            pasteboard: any Pasteboard,
            clock: any PipelineClock,
            store: any Store,
            cleaner: (any TextCleaner)? = nil,
            missingSetup: @escaping @Sendable () async -> SetupItem? = { nil }
        ) {
            self.audio = audio
            self.provider = provider
            self.paster = paster
            self.pasteboard = pasteboard
            self.clock = clock
            self.store = store
            self.cleaner = cleaner
            self.missingSetup = missingSetup
        }
    }

    public struct Settings: Sendable {
        /// Where each dictation's FLAC file goes.
        public var audioDirectory: URL
        public var language: Locale.Language
        /// Keyterms for the request and find-and-replace rules for the transcript.
        public var dictionary: PersonalDictionary
        /// A chord released sooner is a tap (toggle mode); a longer hold is push-to-talk.
        public var tapThreshold: Duration
        public var longRecordingWarning: Duration
        /// Slow apps read the pasteboard late; restoring sooner can paste the old clipboard.
        public var restoreDelay: Duration
        /// How long Undo can resume a recording after Esc.
        public var undoWindow: Duration

        /// The request for one recording, with the language and dictionary from these settings.
        func request(for audio: RecordedAudio) -> TranscriptionRequest {
            TranscriptionRequest(audio: audio.file, language: language, dictionaryTerms: dictionary.keyterms)
        }

        public init(
            audioDirectory: URL,
            language: Locale.Language = Locale.Language(identifier: "en"),
            dictionary: PersonalDictionary = PersonalDictionary(),
            tapThreshold: Duration = .milliseconds(400),
            longRecordingWarning: Duration = .seconds(600),
            restoreDelay: Duration = .seconds(1),
            undoWindow: Duration = .seconds(5)
        ) {
            self.audioDirectory = audioDirectory
            self.language = language
            self.dictionary = dictionary
            self.tapThreshold = tapThreshold
            self.longRecordingWarning = longRecordingWarning
            self.restoreDelay = restoreDelay
            self.undoWindow = undoWindow
        }
    }
}

/// Which kept dictations a retry sends again.
public enum RetrySelection: Sendable, Equatable {
    /// The menu's Retry: every queued dictation.
    case all
    /// Launch without a key: dictations that wait for a key stay waiting.
    case exceptNeedsSetup
    /// The owner saved a key: only the dictations that waited for one, once each.
    case onlyNeedsSetup

    func includes(_ record: DictationRecord) -> Bool {
        switch self {
        case .all: true
        case .exceptNeedsSetup: record.needsSetup == nil
        case .onlyNeedsSetup: record.needsSetup != nil
        }
    }

    /// Two requests in one: anything that covers both.
    func merged(with other: Self) -> Self {
        self == other ? self : .all
    }
}

/// What a dictation does with its transcript, decided when the dictation is announced (tap release
/// or hold threshold): cleanup if the cleanup modifier was down at any moment before.
public enum DictationMode: String, Sendable, Equatable {
    /// Paste the transcript (after dictionary replacements).
    case transcript
    /// Clean the transcript with `TextCleaner` first; paste the raw transcript if that fails.
    case cleanup
}
