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
        /// Microphone access is on now. Read only at the stop of a recording that heard no sound.
        public let isMicrophoneAllowed: @Sendable () -> Bool

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
            inputMark: @escaping @Sendable () -> InputMark? = { nil },
            isMicrophoneAllowed: @escaping @Sendable () -> Bool = { true }
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
            self.isMicrophoneAllowed = isMicrophoneAllowed
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
        /// kotoba-bench-v1; DeepSeek's p90 of 1.2 s plus one try on the fallback model, Gemini's p90 of 2.2 s, fits too:
        /// docs/research/real-usage-pass.md). A late answer is dropped and its cost still goes to the ledger. A retry has no paste
        /// waiting, so it has no deadline.
        public var cleanupDeadline: Duration
        /// The longest Polish waits for its answer (bench p90 1.3 s, plus one try on the fallback model); then it pastes
        /// nothing. A late answer's cost still goes to the ledger.
        public var polishDeadline: Duration
        /// A transcript that ends with a submit phrase ("press enter", "press return") is pasted without it, then Return.
        public var isSubmitPhraseOn: Bool
        /// Spoken "new line" and "new paragraph" become line breaks in the text (`LineBreakPhrase`). Off by default.
        public var isLineBreakPhraseOn: Bool
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
                audio: audio.file, upload: audio.upload, duration: audio.duration, language: language,
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
            isLineBreakPhraseOn: Bool = false,
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
            self.isLineBreakPhraseOn = isLineBreakPhraseOn
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
