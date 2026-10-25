import Foundation
import KotobaCore

/// What the pill draws (docs/research/ui-redesign.md, "Pill"): `IndicatorLook`'s shape with its words and buttons.
indirect enum PillLook: Equatable {
    /// "Show indicator: Always" at idle: a still bar.
    case idle
    /// The pointer is on the idle bar: "Dictate" and the hands-free chord's keys ("⌃", "⌥", "⌘"); words, so horizontal
    /// at every anchor.
    case hover(keys: [String])
    case recording(PillRecording)
    /// Text is on its way: the loading dots.
    case processing(PillStep)
    /// The text is pasted: a check, then idle.
    case done
    /// Words with an optional fix button: a notice, Undo, an added word.
    case message(PillMessage)

    /// Words, keys or the time show, so the pill stays horizontal at every anchor (`IndicatorPlacement.isVertical`).
    var hasWords: Bool {
        switch self {
        case .idle, .processing, .done: false
        case .hover, .message: true
        case .recording(let recording): recording.words != nil || recording.timedFrom != nil
        }
    }

    /// What VoiceOver reads for the pill; the elapsed time as of `now`. `isClickable`: a click on the idle bar starts a
    /// dictation; without it a development build gives way to the release app, and the label says so.
    func accessibilityLabel(at now: ContinuousClock.Instant, isClickable: Bool) -> String {
        switch self {
        case .idle, .hover: isClickable ? StatusText.pillClickLabel(.startsDictation) : StatusText.yieldsToRelease
        case .recording(let recording):
            StatusText.recordingLabel(
                isHandsFree: recording.isHandsFree, isCleaned: recording.isCleaned,
                elapsed: recording.timedFrom.map { now - $0 }, words: recording.words?.text)
        case .processing(let step): StatusText.processingLabel(step)
        case .done: StatusText.pastedLabel
        case .message(let message): message.text
        }
    }

    /// The buttons the look shows, in order, as VoiceOver reads them.
    var buttonLabels: [String] {
        switch self {
        case .idle, .hover, .processing, .done: []
        case .recording(let recording):
            (recording.showsCancel ? [StatusText.cancelLabel] : [])
                + (recording.words?.action.map { [$0.title] } ?? [])
                + (recording.isHandsFree ? [StatusText.stopLabel] : [])
        case .message(let message): message.action.map { [$0.title] } ?? []
        }
    }
}

/// What the loading dots wait on, for VoiceOver.
enum PillStep: Equatable {
    case transcribing
    case cleaningUp
    case rewriting
}

struct PillRecording: Equatable {
    /// Hands-free: wider, with Cancel and Stop. Push to talk: bars only.
    var isHandsFree: Bool
    /// The dictation will be cleaned up: a small wand before the bars.
    var isCleaned = false
    /// The mic gives no sound: orange bars.
    var isSilent = false
    /// Off while Microphone access is off: there is nothing to meter, and the words need the room.
    var showsBars = true
    /// A silent mic's words and fix, or Secure Input's words; nil: no words.
    var words: PillMessage?
    /// The time recorded shows, counted from this instant; nil before the 10-minute mark.
    var timedFrom: ContinuousClock.Instant?

    /// Silent and hands-free, the words and the fix need Cancel's room; Esc still cancels (chief of staff,
    /// 2026-10-24).
    var showsCancel: Bool { isHandsFree && !isSilent }
}

struct PillMessage: Equatable {
    var text: String
    /// A problem: an orange warning symbol before the words.
    var isProblem = false
    /// The fix or Undo button.
    var action: PillAction?
}

extension PillLook {
    /// The button's action: a message's fix or Undo, or a silent mic's fix.
    var action: PillAction? {
        switch self {
        case .message(let message): message.action
        case .recording(let recording): recording.words?.action
        case .idle, .hover, .processing, .done: nil
        }
    }
}
