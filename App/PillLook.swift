import Foundation
import KotobaCore

/// What the pill draws (docs/research/ui-redesign.md, "Pill"): `IndicatorLook`'s shape with its words and buttons.
enum PillLook: Equatable {
    /// "Show indicator: Always" at idle: a still bar.
    case idle
    /// The pointer is on the idle bar: "Dictate" and the hands-free chord's keys ("⌃", "⌥", "⌘"); words, so horizontal
    /// at every anchor.
    case hover(keys: [String])
    case recording(PillRecording)
    /// Text is on its way: the bars sweep.
    case processing
    /// The text is pasted: a check, then idle.
    case done
    /// Words with an optional fix button: a notice, Undo, an added word.
    case message(PillMessage)
    /// Under the pointer while the owner drags the pill to another anchor: an empty circle.
    case dragged

    /// A look with no words stands vertical at a side edge; words keep the pill horizontal at every anchor.
    var canStandVertical: Bool {
        switch self {
        case .idle, .processing, .done, .dragged: true
        case .hover, .message: false
        case .recording(let recording): recording.words == nil && recording.timedFrom == nil
        }
    }

    /// What VoiceOver reads for the pill; the elapsed time as of `now`.
    func accessibilityLabel(at now: ContinuousClock.Instant) -> String {
        switch self {
        case .idle, .hover, .dragged: StatusText.pillClickLabel(.startsDictation)
        case .recording(let recording):
            StatusText.recordingLabel(
                isHandsFree: recording.isHandsFree, isCleaned: recording.isCleaned,
                elapsed: recording.timedFrom.map { now - $0 }, words: recording.words?.text)
        case .processing: StatusText.processingLabel
        case .done: StatusText.pastedLabel
        case .message(let message): message.text
        }
    }

    /// The buttons the look shows, in order, as VoiceOver reads them.
    var buttonLabels: [String] {
        switch self {
        case .idle, .hover, .processing, .done, .dragged: []
        case .recording(let recording):
            (recording.showsCancel ? [StatusText.cancelLabel] : [])
                + (recording.words?.action.map { [$0.title] } ?? [])
                + (recording.isHandsFree ? [StatusText.stopLabel] : [])
        case .message(let message): message.action.map { [$0.title] } ?? []
        }
    }
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
