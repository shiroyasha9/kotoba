import Foundation

/// A key event from the owner's hands-free, push-to-talk, cleanup, Paste Last, Copy Last or Polish Last chord, Esc or
/// Return, as `HotkeyClassifier` reports it.
public enum HotkeyEvent: Sendable, Equatable {
    /// A press began; `ChordGesture` says what its release does.
    case chordDown(ChordGesture)
    /// A chord with more keys than the one that began this press is now held (⌥ for push to talk, then ⌃⌘ for
    /// hands-free ⌃⌥⌘): the press follows it. A dictation not yet announced takes the new gesture; later, it is ignored.
    case gestureChanged(ChordGesture)
    /// The whole cleanup chord (the dictation chord plus Shift by default) was down at some moment of this
    /// press. A dictation not yet announced becomes a cleanup dictation; later, it is ignored.
    case cleanupModifier
    case chordUp
    case escape
    /// A non-modifier key went down while the chord was held: the chord was part of another
    /// app's shortcut, not a dictation.
    case chordInterrupted
    /// Return with no modifier while recording: stop, and send Return after the paste (submit after paste).
    case submit
    /// The Paste Last chord was pressed and every modifier is up again: paste the last dictation again, as the menu's
    /// "Paste Last Dictation" does.
    case pasteLast
    /// The Copy Last chord was pressed: put the last dictation on the clipboard, as the menu's "Copy Last Dictation"
    /// does.
    case copyLast
    /// The Polish Last chord was pressed and every modifier is up again (it posts ⌘V, as Paste Last): polish the last
    /// dictation, as the menu's "Polish Last Dictation" does.
    case polishLast
}

/// What the release of the press that starts a dictation does (spec "Hotkey state machine").
public enum ChordGesture: Sendable, Equatable {
    /// The hands-free and push-to-talk chords are one chord: a tap toggles, a hold over the threshold is push to talk.
    /// The cleanup chord works so too.
    case tapOrHold
    /// The hands-free chord: a press starts, the next press stops. A long hold does not stop at its release.
    case toggle
    /// The push-to-talk chord: the release stops. A release under the threshold drops the press, as a shortcut's.
    case hold
}

/// What the indicator shows.
public enum DictationState: Sendable, Equatable {
    case idle
    /// `isLong` turns on after `Settings.longRecordingWarning`; recording never stops on its own.
    /// `isSilent` is on while the mic gives no sound (`NoSoundPolicy`); it clears when sound arrives.
    /// `isCleaned`: the dictation will be cleaned up, by the cleanup chord or by the mode of the app in front at
    /// key-down; the app in front at the stop decides in the end.
    case recording(isLong: Bool, isSilent: Bool = false, isCleaned: Bool = false)
    case transcribing
    /// The transcript is with the cleaner (LLM cleanup, 1.6 s p50 in kotoba-bench-v1); the paste follows.
    case cleaning
    /// Esc cancelled the recording and the mic is off. Undo (or a chord tap) resumes it until
    /// `Settings.undoWindow` passes; then the cancel is final.
    case undoable
    /// Transcription failed. The audio is kept and queued for retry.
    case failed(DictationID)
    /// The route did not answer in time (`ProviderError.timedOut`). The audio is kept and queued for retry.
    case timedOut(DictationID)
    /// The network blocked the secure connection (`ProviderError.connectionBlocked`). The audio is kept and queued.
    case connectionBlocked(DictationID)
    /// The route refused the request; a retry cannot help. The audio is kept.
    case rejected(DictationID, RejectReason)
    /// The route needs an API key. The audio is kept and retried when the owner saves one.
    case needsSetup(DictationID, SetupItem)
    /// The cleanup failed, so the raw transcript was pasted.
    case cleanupFailed(DictationID)
    /// The cleaner did not answer within `Settings.cleanupDeadline`, so the raw transcript was pasted.
    case cleanupTooSlow(DictationID)
    /// Pasted, but the submit Return was not sent: another app came to the front after the stop.
    case returnSkipped(DictationID)
    /// The transcript is on the clipboard, not pasted: paste was not allowed, or another app came to the front after
    /// the stop.
    case copied(DictationID)
    /// A retry transcribed a queued dictation; the menu lists it under Recovered.
    case recovered(DictationID)
    /// Capture did not start: no microphone access or no input device.
    case captureFailed
    /// The stop found no capture running (the audio source had lost it): nothing was recorded, kept or sent.
    case nothingRecorded
    /// The recording file took too little audio to send (`RecordedAudio.loss`): nothing was kept or sent.
    case audioNotSaved(AudioLoss)
    /// Pasted, but the file stopped taking audio during the recording: the text has only the part saved.
    case audioCut(DictationID, AudioLoss)
    /// Pasted, but the clipboard before it was too large to keep (`PasteboardSnapshot.byteLimit`): it is not restored.
    case clipboardNotKept(DictationID)
    /// Polish sent the last dictation to the LLM; the paste follows.
    case polishing
    /// Polish replaced the old text with its own (`isReplaced`, Undo can bring it back), or left it on the clipboard
    /// because it could not replace it safely.
    case polished(DictationID, isReplaced: Bool)
    /// Polish pasted nothing and changed nothing.
    case polishFailed(PolishFailure)

    /// What the indicator shows once a dictation reaches `record.status`.
    static func outcome(of record: DictationRecord) -> Self {
        switch record.status {
        case .recovered: .recovered(record.id)
        case .rejected: .rejected(record.id, record.rejectReason ?? .other)
        case .copied: .copied(record.id)
        case .failed where record.needsSetup != nil: .needsSetup(record.id, record.needsSetup ?? .key)
        // "Offline" would send the owner to check a network that works.
        case .failed where record.hasTimedOut: .timedOut(record.id)
        case .failed where record.isConnectionBlocked: .connectionBlocked(record.id)
        case .failed, .pending: .failed(record.id)
        case .pasted, .cancelled: .idle
        }
    }
}

extension DictationPipeline {
    public struct Ports: Sendable {
        public let audio: any AudioSource
        /// The pipeline wraps it so it knows when the route last answered (`RouteWarmth`).
        public internal(set) var provider: any TranscriptionProvider
        public let paster: any Paster
        public let pasteboard: any Pasteboard
        public let clock: any PipelineClock
        /// The pipeline wraps it so each write is announced on `historyChanges`.
        public internal(set) var store: any Store
        /// Cleans the transcript of a cleanup dictation; nil pastes the raw transcript.
        public let cleaner: (any TextCleaner)?
        /// What the current route still needs before it can send (a key or an endpoint); nil when ready.
        public let missingSetup: @Sendable () async -> SetupItem?
        /// Follows the field after each paste for the owner's edits; nil learns nothing.
        public let readback: EditReadback?
        /// The front app, kept current by app activation events; nil when unknown. A submit Return goes only to the
        /// app that was in front at the stop, and the history keeps that app.
        public let frontApp: @Sendable () -> FrontApp?
        /// Rewrites the last dictation on the owner's request; nil leaves Polish off.
        public let polisher: (any TextPolisher)?
        /// Selects the text Polish replaces; nil leaves only the replace by Backspace.
        public let selector: (any PastedTextSelector)?
        /// The front app and window and the owner's input count now; nil when unknown. Polish replaces by Backspace only
        /// when it did not change since kotoba's paste (`PolishPlacement`).
        public let inputMark: @Sendable () -> InputMark?

        public init(
            audio: any AudioSource,
            provider: any TranscriptionProvider,
            paster: any Paster,
            pasteboard: any Pasteboard,
            clock: any PipelineClock,
            store: any Store,
            cleaner: (any TextCleaner)? = nil,
            missingSetup: @escaping @Sendable () async -> SetupItem? = { nil },
            readback: EditReadback? = nil,
            frontApp: @escaping @Sendable () -> FrontApp? = { nil },
            polisher: (any TextPolisher)? = nil,
            selector: (any PastedTextSelector)? = nil,
            inputMark: @escaping @Sendable () -> InputMark? = { nil }
        ) {
            self.audio = audio
            self.provider = provider
            self.paster = paster
            self.pasteboard = pasteboard
            self.clock = clock
            self.store = store
            self.cleaner = cleaner
            self.missingSetup = missingSetup
            self.readback = readback
            self.frontApp = frontApp
            self.polisher = polisher
            self.selector = selector
            self.inputMark = inputMark
        }
    }

    public struct Settings: Sendable {
        /// Where each dictation's FLAC file goes.
        public var audioDirectory: URL
        public var language: Locale.Language
        /// Keyterms for the request and find-and-replace rules for the transcript.
        public var dictionary: PersonalDictionary
        /// How the owner uses each keyterm, by `TermUse.key(for:)`: over `PersonalDictionary.maxKeyterms`, the request
        /// sends the terms `TermRanking` puts first.
        public var termUse: [String: TermUse] = [:]
        /// A chord released sooner is a tap (`ChordGesture`); a longer hold is push to talk. Push to talk drops a
        /// shorter press, and the indicator and cue of every press wait for the tap's release or for this threshold.
        public var tapThreshold: Duration
        /// A push-to-talk press that starts this soon after the release of a dropped push-to-talk tap records
        /// hands-free: a double tap locks push to talk on, as in Wispr Flow.
        public var doubleTapGap: Duration
        public var longRecordingWarning: Duration
        /// The mic gave no sound this long: the indicator warns (`NoSoundPolicy`).
        public var noSoundWarning: Duration
        /// A stop with less audio than this (an accidental double tap) discards the dictation: no request, no file,
        /// no history row and no error. Measured on the audio written, Undo's resumed part included, not on the key
        /// times. Wispr Flow discards under about 0.5 s.
        public var minimumRecording: Duration
        /// The longest the clipboard waits for the paste target to read the transcript. The restore follows the
        /// read, never a fixed time, because a busy app reads late and would paste the old clipboard (Handy #502). An
        /// app that read nothing by then never got the paste: the transcript stays on the clipboard.
        public var readWait: Duration
        /// The longest a paste waits for the release of the press that stopped the dictation (a Cmd-V with the chord
        /// held reaches the app as ⌃⌥⌘V). A release after a stop tap comes within `tapThreshold`; the tap repairs a
        /// lost release only at the next key event, which does not come while the owner waits for the text, so the
        /// wait needs its own bound. A later press (the next dictation's) holds the paste until its release.
        public var chordReleaseWait: Duration
        /// How long Undo can resume a recording after Esc.
        public var undoWindow: Duration
        /// The longest a live cleanup may take; then the raw transcript pastes (about 2x the cleanup p90 of 2.3 s in
        /// kotoba-bench-v1). A late answer is dropped and its cost still goes to the ledger. A retry has no paste
        /// waiting, so it has no deadline.
        public var cleanupDeadline: Duration
        /// The longest Polish waits for its answer (bench p90 1.3 s, plus one try on the fallback model); then it pastes
        /// nothing. A late answer's cost still goes to the ledger.
        public var polishDeadline: Duration
        /// A transcript that ends with a submit phrase ("press enter", "press return") is pasted without it, then Return.
        public var isSubmitPhraseOn: Bool
        /// How long a transcribed dictation keeps its audio.
        public var audioRetention: AudioRetention
        /// The per-app modes: how the app in front at the stop has its dictations cleaned up.
        public var modes: ModeRules
        /// A live recording sends the route's primer again this long after the last one, so the answer at the stop
        /// still finds the route warm. Warm was measured 45 s after a primer (docs/research/latency-pass.md); 5 s less
        /// is the margin. At most 90 primers per hour of continuous recording.
        public var primerInterval: Duration

        /// The longest a transcription may take before it fails as `ProviderError.timedOut`: 75 s for the upload and
        /// the route's answer (upstreams time out after about 60 s), plus half the audio's length for a slow uplink (a
        /// minute of FLAC is about 1.3 MB as base64; at 64 KB/s it uploads in about 21 s), at most
        /// `longestTranscription`. A real timeout on the pipeline clock, so a long recording is never cut at a fixed
        /// time.
        public static func transcriptionTimeout(for audio: Duration) -> Duration {
            min(.seconds(75) + audio / 2, longestTranscription)
        }

        /// The bound on `transcriptionTimeout(for:)`; the providers' connections allow a little more, so this one
        /// decides.
        public static let longestTranscription = Duration.seconds(30 * 60)

        /// The request for one recording, with the language and the keyterms ranked at `now` from these settings.
        func request(for audio: RecordedAudio, at now: Date) -> TranscriptionRequest {
            TranscriptionRequest(
                audio: audio.file, duration: audio.duration, language: language,
                dictionaryTerms: TermRanking.keyterms(of: dictionary, use: termUse, at: now))
        }

        public init(
            audioDirectory: URL,
            language: Locale.Language = Locale.Language(identifier: "en"),
            dictionary: PersonalDictionary = PersonalDictionary(),
            tapThreshold: Duration = .milliseconds(400),
            doubleTapGap: Duration = .milliseconds(300),
            longRecordingWarning: Duration = .seconds(600),
            noSoundWarning: Duration = .seconds(2),
            minimumRecording: Duration = .milliseconds(500),
            readWait: Duration = .seconds(10),
            chordReleaseWait: Duration = .seconds(2),
            undoWindow: Duration = .seconds(5),
            cleanupDeadline: Duration = .seconds(5),
            polishDeadline: Duration = .seconds(10),
            isSubmitPhraseOn: Bool = true,
            audioRetention: AudioRetention = .standard,
            modes: ModeRules = ModeRules(),
            primerInterval: Duration = .seconds(40)
        ) {
            self.audioDirectory = audioDirectory
            self.language = language
            self.dictionary = dictionary
            self.tapThreshold = tapThreshold
            self.doubleTapGap = doubleTapGap
            self.longRecordingWarning = longRecordingWarning
            self.noSoundWarning = noSoundWarning
            self.minimumRecording = minimumRecording
            self.readWait = readWait
            self.chordReleaseWait = chordReleaseWait
            self.undoWindow = undoWindow
            self.cleanupDeadline = cleanupDeadline
            self.polishDeadline = polishDeadline
            self.isSubmitPhraseOn = isSubmitPhraseOn
            self.audioRetention = audioRetention
            self.modes = modes
            self.primerInterval = primerInterval
        }
    }
}

/// What is live in the pipeline, for the History pane.
public struct PipelineActivity: Sendable, Equatable {
    /// No recording, no Undo window and no dictation in flight: "Paste Again" can paste.
    public var isQuiet: Bool
    /// The dictations being sent now: their rows say so and cannot be deleted.
    public var inFlight: Set<DictationID>
    /// The dictations with text being sent again by History's "Transcribe Again"; nothing is pasted, so they do not
    /// make the pipeline busy, but their rows say so and cannot be deleted or sent again.
    public var transcribingAgain: Set<DictationID>

    public init(isQuiet: Bool, inFlight: Set<DictationID>, transcribingAgain: Set<DictationID> = []) {
        self.isQuiet = isQuiet
        self.inFlight = inFlight
        self.transcribingAgain = transcribingAgain
    }
}

/// The app in front, as app activation events report it.
public struct FrontApp: Sendable, Equatable {
    /// The submit rule compares it: a process, not an app, so a relaunched app is another one.
    public var processID: Int32
    /// Nil for a process with no bundle id.
    public var app: DictationApp?

    public init(processID: Int32, app: DictationApp? = nil) {
        self.processID = processID
        self.app = app
    }
}

/// Which kept dictations a retry sends again: the ones a rule picks, and the ones the owner chose.
public struct RetrySelection: Sendable, Equatable {
    enum Rule: Sendable, Equatable {
        case all
        case exceptNeedsSetup
        case onlyNeedsSetup

        func includes(_ record: DictationRecord) -> Bool {
            switch self {
            case .all: true
            case .exceptNeedsSetup: record.needsSetup == nil
            case .onlyNeedsSetup: record.needsSetup != nil
            }
        }
    }

    /// A dictation is sent at most this many times in all, live and retried, without the owner: each failed send
    /// that reached the route may have been billed (`DictationRecord.attempts`). Launch and a returning network skip
    /// it then; the owner's Retry (the menu, History) still sends it.
    public static let automaticAttempts = 3

    var rule: Rule?
    var ids: Set<DictationID> = []
    /// Launch or a returning network, not the owner: the rule skips dictations that used their automatic attempts.
    var isAutomatic = false

    /// The menu's Retry: every queued dictation.
    public static let all = Self(rule: .all)
    /// Launch without a key: dictations that wait for a key stay waiting.
    public static let exceptNeedsSetup = Self(rule: .exceptNeedsSetup)
    /// The owner saved a key: only the dictations that waited for one, once each.
    public static let onlyNeedsSetup = Self(rule: .onlyNeedsSetup)

    /// The History pane's Retry: the chosen queued dictations.
    public static func only(_ ids: Set<DictationID>) -> Self {
        Self(rule: nil, ids: ids)
    }

    func includes(_ record: DictationRecord) -> Bool {
        if ids.contains(record.id) { return true }
        guard rule?.includes(record) == true else { return false }
        return !isAutomatic || record.attempts < Self.automaticAttempts
    }

    /// Two requests in one: the dictations of each. Two different rules cover both only as `.all`; the rule is capped
    /// only when every request with a rule was automatic.
    func merged(with other: Self) -> Self {
        let (merged, isAutomatic): (Rule?, Bool) =
            switch (rule, other.rule) {
            case (nil, _): (other.rule, other.isAutomatic)
            case (_, nil): (rule, self.isAutomatic)
            case (let one?, let two?): (one == two ? one : .all, self.isAutomatic && other.isAutomatic)
            }
        return Self(rule: merged, ids: ids.union(other.ids), isAutomatic: isAutomatic)
    }
}

/// What a dictation does with its transcript, decided at the stop (`ModeRules.output(for:isCleanupChord:)`): cleanup in
/// the mode of the app in front then, when the cleanup modifier was down before the announcement (tap release or hold
/// threshold) or that mode cleans every dictation.
public enum DictationOutput: Sendable, Equatable {
    /// Paste the transcript (after dictionary replacements).
    case transcript
    /// Clean the transcript with `TextCleaner` in this mode first; paste the raw transcript if that fails.
    case cleanup(AppMode)

    /// The mode the cleaner writes in; nil for a plain transcript.
    public var cleanupMode: AppMode? {
        if case .cleanup(let mode) = self { mode } else { nil }
    }
}
