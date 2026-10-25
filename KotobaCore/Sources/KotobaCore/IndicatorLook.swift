/// What the indicator pill shows for a dictation state (docs/research/ui-redesign.md, "Pill"): its shape and the facts
/// that change it. One glass capsule changes shape; words show only when the owner must know something or can act. The
/// App adds the words and the buttons.
public enum IndicatorLook: Sendable, Equatable {
    /// Nothing on screen: idle with "Show indicator: While Dictating".
    case hidden
    /// The idle bar ("Show indicator: Always").
    case idle
    case recording(IndicatorRecording)
    /// Text is on its way (transcription, cleanup, rewrite): the loading dots.
    case processing
    /// The dictation was pasted and nothing else is on its way: a check, then idle.
    case done
    /// Words with an optional button: a notice, or Undo after Esc.
    case message

    /// `showsIdleBar`: "Show indicator: Always". `isSecureInputOn`: another app turned on Secure Input, so a paste can
    /// fail; the recording pill says so.
    public init(_ state: DictationState, showsIdleBar: Bool, isSecureInputOn: Bool) {
        // A notice shows in place of the phase, and the check in place of the idle under it.
        if state.notice != nil {
            self = .message
            return
        }
        if state.isPasted {
            self = .done
            return
        }
        self =
            switch state.phase {
            case .idle: showsIdleBar ? .idle : .hidden
            case .recording(let isLong, let isSilent, let isCleaned, let isPushToTalk):
                .recording(
                    IndicatorRecording(
                        isHandsFree: !isPushToTalk, isCleaned: isCleaned, isSilent: isSilent, isLong: isLong,
                        isSecureInputOn: isSecureInputOn))
            case .transcribing, .cleaning, .polishing: .processing
            case .undoable: .message
            }
    }
}

/// The recording pill's facts.
public struct IndicatorRecording: Sendable, Equatable {
    /// Cancel and Stop show; push to talk shows the bars only.
    public var isHandsFree: Bool
    /// The dictation will be cleaned up: a small wand before the bars.
    public var isCleaned: Bool
    /// The mic gives no sound: orange bars, the words and the fix.
    public var isSilent: Bool
    /// Past `Settings.longRecordingWarning`: the time recorded shows.
    public var isLong: Bool
    /// The words say so, unless a silent mic's words show.
    public var isSecureInputOn: Bool

    public init(
        isHandsFree: Bool, isCleaned: Bool = false, isSilent: Bool = false, isLong: Bool = false,
        isSecureInputOn: Bool = false
    ) {
        self.isHandsFree = isHandsFree
        self.isCleaned = isCleaned
        self.isSilent = isSilent
        self.isLong = isLong
        self.isSecureInputOn = isSecureInputOn
    }
}
