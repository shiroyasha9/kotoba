import Foundation

// The 0.5.0 pill prototype's states (docs/research/ui-redesign.md, "Pill"), drawn by `PillPrototypeView`.

/// What the prototype pill shows.
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
    /// Words with an optional fix button: an error, Undo, an added word.
    case message(PillMessage)

    /// What the hover's chord starts, before its keys (owner, 2026-10-25).
    static let dictate = "Dictate"

    /// A look with no words stands vertical at a side edge; words keep the pill horizontal at every anchor.
    var canStandVertical: Bool {
        switch self {
        case .idle, .processing, .done: true
        case .hover: false
        case .recording(let recording): !recording.isSilent && !recording.isSecureInputOn && recording.elapsed == nil
        case .message: false
        }
    }

    /// What VoiceOver reads for the pill.
    var accessibilityLabel: String {
        switch self {
        case .idle, .hover: StatusText.pillClickLabel(.startsDictation)
        case .recording(let recording): recording.accessibilityLabel
        case .processing: "Transcribing"
        case .done: "Pasted"
        case .message(let message): message.text
        }
    }
}

struct PillRecording: Equatable {
    /// Hands-free: wider, with Cancel and Stop. Push to talk: bars only.
    var isHandsFree = false
    /// The dictation will be cleaned up: a small wand before the bars.
    var isCleaned = false
    /// The mic gives no sound: orange bars, the words and Choose Mic….
    var isSilent = false
    /// The time recorded, shown from the 10-minute mark; nil before it.
    var elapsed: Duration?
    /// Another app turned on Secure Input: the words say so, since a paste can fail (owner, 2026-10-24). A silent mic's
    /// words win over them.
    var isSecureInputOn = false

    /// Sample copy until the copy pass.
    static let secureInput = "Secure Input is on"

    var accessibilityLabel: String {
        var parts = [isHandsFree ? "Recording, hands-free" : "Recording"]
        if isCleaned { parts.append("with cleanup") }
        if let elapsed { parts.append(elapsed.formatted(.units(allowed: [.minutes, .seconds], width: .wide))) }
        if isSilent { parts.append(StatusText.noSound) } else if isSecureInputOn { parts.append(Self.secureInput) }
        return parts.joined(separator: ", ")
    }
}

struct PillMessage: Equatable {
    var text: String
    /// A problem: an orange warning symbol before the words.
    var isProblem = false
    /// The fix or Undo button's title.
    var button: String?
}

extension PillLook {
    var isHover: Bool {
        if case .hover = self { return true }
        return false
    }
}
