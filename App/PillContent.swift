import AppKit
import KotobaCore

/// What the pill shows, and how it behaves: its look, its click and its timer.
struct PillContent: Equatable {
    var look: PillLook
    /// What a click on the pill (not its button) does, as a chord tap; nil: nothing.
    var click: PillClick?
    var timer: PillTimer?
    var toolTip: String?
}

/// The pill's own timer: a pill with a message goes when it runs out; hover holds it.
struct PillTimer: Equatable {
    enum Kind {
        /// The pill goes quiet when the time runs out: a message, the check.
        case hidesPill
        /// The pipeline owns the time (the Esc Undo window): hover holds it there too, and the pipeline ends the pill.
        case followsUndoWindow
    }

    var duration: Duration
    var kind = Kind.hidesPill

    /// The check shows this long after a paste, then the pill goes quiet.
    static let done = Self(duration: .milliseconds(900))
}

/// A message the App shows on the pill, outside a dictation's state: a learned word, a development build that gives
/// way. It shows for `duration`; hover holds it.
struct PillNotice: Equatable {
    var text: String
    var action: PillAction?
    var duration: Duration

    init(text: String, action: PillAction? = nil, duration: Duration? = nil) {
        self.text = text
        self.action = action
        // A pill with a button gives the owner time to reach it.
        self.duration = duration ?? (action == nil ? .seconds(4) : .seconds(8))
    }

    /// Auto-learn added the words that `label` names ("Kubernetes", "2 words"); Undo removes the learn `id`.
    static func learned(_ label: String, id: UUID) -> Self {
        Self(text: StatusText.learned(label), action: .undoLearned(id))
    }
    /// A development build while the release app runs (`InstallYield`).
    static let yieldsToRelease = Self(text: StatusText.yieldsToRelease)
}

extension PillContent {
    init(_ notice: PillNotice) {
        self.init(
            look: .message(PillMessage(text: notice.text, action: notice.action)),
            timer: PillTimer(duration: notice.duration))
    }

    /// The idle bar with "Show indicator: Always". A click on it starts a dictation; where it does not
    /// (`IndicatorPlacement.click`), a development build gives way to the release app and the help tag says why.
    static func idle(click: PillClick?) -> Self {
        PillContent(
            look: .idle, click: click, toolTip: click == nil ? StatusText.yieldsToRelease : StatusText.idlePillHelp)
    }
}

/// What the pill shows for each dictation state, for the panel and the snapshots.
extension IndicatorPanel {
    /// In place of a dictation's symbol while Polish rewrites the last dictation (History's row reads it too).
    nonisolated static let polishSymbol = "text.badge.star"

    /// What the pill shows for `state`; nil hides it. `timedFrom`: the instant the recording's time counts from, read
    /// once it passes the 10-minute mark.
    static func content(
        for state: DictationState, context: StatusContext, visibility: IndicatorVisibility,
        timedFrom: ContinuousClock.Instant? = nil
    ) -> PillContent? {
        let isAlways = visibility == .always
        let click = IndicatorPlacement.click(in: state, showsIdlePill: isAlways, isYielding: context.isYielding)
        let words = state.pillText(context).map { PillMessage(text: $0, action: state.pillAction(context)) }
        switch IndicatorLook(state, showsIdleBar: isAlways, isSecureInputOn: context.isSecureInputOn) {
        case .hidden:
            return nil
        case .idle:
            return .idle(click: click)
        case .recording(let recording):
            let look = PillRecording(
                isHandsFree: recording.isHandsFree, isCleaned: recording.isCleaned, isSilent: recording.isSilent,
                showsBars: !(recording.isSilent && context.isMicrophoneOff), words: words,
                timedFrom: recording.isLong ? timedFrom : nil)
            return PillContent(
                look: .recording(look), click: click,
                toolTip: recordingHelp(recording, context: context))
        case .processing:
            return PillContent(look: .processing)
        case .done:
            return PillContent(look: .done, timer: .done)
        case .message:
            var message = words ?? PillMessage(text: "")
            message.isProblem = state.notice.map { !$0.isGood } ?? false
            // The pipeline ends the Undo window itself.
            let timer =
                state.phase == .undoable && state.notice == nil
                ? PillTimer(duration: context.undoWindow, kind: .followsUndoWindow)
                : PillTimer(duration: PillNotice(text: message.text, action: message.action).duration)
            return PillContent(look: .message(message), timer: timer)
        }
    }

    /// The recording pill's help tag: why it is silent, Secure Input, or the cleanup to come.
    private static func recordingHelp(_ recording: IndicatorRecording, context: StatusContext) -> String? {
        if recording.isSilent && context.isMicrophoneOff { return StatusText.microphoneOffHelp }
        if recording.isSilent { return StatusText.noSoundHelp(context.microphoneName) }
        if recording.isSecureInputOn { return DictationState.secureInputHelp }
        return recording.isCleaned ? StatusText.cleanupHelp : nil
    }
}
