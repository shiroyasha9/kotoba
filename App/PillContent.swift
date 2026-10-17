import AppKit
import KotobaCore

/// A message the pill shows for `duration`: an optional SF Symbol in place of the state dot, the text,
/// and one button. With a button the pill shows a bar that empties over `duration`; hover holds the
/// timer and the bar.
struct PillNotice: Equatable {
    var text: String
    /// An SF Symbol name, such as "sparkles".
    var symbol: String?
    var action: PillAction?
    var duration: Duration

    init(text: String, symbol: String? = nil, action: PillAction? = nil, duration: Duration? = nil) {
        self.text = text
        self.symbol = symbol
        self.action = action
        // A pill with a button gives the owner time to reach it.
        self.duration = duration ?? (action == nil ? .seconds(4) : .seconds(8))
    }
}

extension PillNotice {
    /// Auto-learn added the words that `label` names ("Kubernetes", "2 words"); Undo removes the learn `id`.
    static func learned(_ label: String, id: UUID) -> Self {
        PillNotice(text: StatusText.learned(label), symbol: "sparkles", action: .undoLearned(id))
    }
    /// A development build while the release app runs (`InstallYield`).
    static let yieldsToRelease = PillNotice(text: StatusText.yieldsToRelease)
}

extension IndicatorPillView.Content {
    /// The small round pill at idle with "Show indicator: Always". A click on it starts a dictation; where it does not
    /// (`IndicatorPlacement.click`), a development build gives way to the release app and the help tag says why.
    static func idle(click: PillClick?) -> Self {
        Self(toolTip: click == nil ? StatusText.yieldsToRelease : StatusText.idlePillHelp, isRound: true, click: click)
    }

    init(_ notice: PillNotice, color: NSColor = .controlAccentColor) {
        self.init(
            text: notice.text, color: color, symbol: notice.symbol, action: notice.action,
            timer: .init(duration: notice.duration))
    }
}

/// What the pill shows for each dictation state, for the panel and the snapshots.
extension IndicatorPanel {
    /// In place of the state dot while a dictation will be cleaned up and while it is: the one fact the owner acts on
    /// (a short wait, and words that may change). Not the learned word's "sparkles".
    static let cleanupSymbol = "wand.and.sparkles"
    /// While Polish rewrites the last dictation: a rewrite, not a cleanup.
    nonisolated static let polishSymbol = "text.badge.star"

    /// What the pill shows for `state`; nil hides it.
    static func content(
        for state: DictationState, context: StatusContext, visibility: IndicatorVisibility
    ) -> IndicatorPillView.Content? {
        let text = state.statusText(context) ?? ""
        let action = state.pillAction(context)
        let isAlways = visibility == .always
        let click = IndicatorPlacement.click(
            in: state, showsIdlePill: isAlways, isYielding: context.isYielding)
        switch state {
        case .idle:
            return isAlways ? .idle(click: click) : nil
        case .recording(let isLong, let isSilent, let isCleaned):
            // Only a plain "Listening" pill stands vertical at an edge; the others carry more words.
            let isPlain = !isLong && !isSilent && !context.isSecureInputOn
            let toolTip = recordingHelp(isSilent: isSilent, isCleaned: isCleaned, context: context)
            // No sound is a warning with its fix on the button; it clears when sound arrives, so no timer. With
            // Microphone access off there is nothing to meter, and the button's words need the room.
            let isAccessOff = isSilent && context.isMicrophoneOff
            return .init(
                text: text, color: isSilent ? .systemOrange : .systemRed, symbol: isCleaned ? cleanupSymbol : nil,
                toolTip: toolTip, showsMeter: !isAccessOff, isCompact: isPlain, click: click, action: action)
        case .transcribing:
            return .init(text: text, color: .systemBlue, showsSpinner: true, isCompact: true)
        case .cleaning:
            return .init(text: text, color: .systemBlue, symbol: cleanupSymbol, showsSpinner: true, isCompact: true)
        case .polishing:
            return .init(text: text, color: .systemBlue, symbol: polishSymbol, showsSpinner: true, isCompact: true)
        case .undoable:
            // The pipeline ends the Undo window itself; the bar follows it.
            return .init(
                text: text, color: .secondaryLabelColor, action: action,
                timer: .init(duration: context.undoWindow, kind: .followsUndoWindow))
        case .failed, .timedOut, .needsSetup, .rejected, .cleanupFailed, .cleanupTooSlow, .returnSkipped, .recovered,
            .copied, .captureFailed, .nothingRecorded, .audioNotSaved, .audioCut, .clipboardNotKept, .polished,
            .polishFailed:
            return .init(
                PillNotice(text: text, action: action), color: state.isGoodOutcome ? .systemGreen : .systemOrange)
        }
    }

    /// The recording pill's help tag: why it is silent, Secure Input, or the cleanup to come.
    private static func recordingHelp(isSilent: Bool, isCleaned: Bool, context: StatusContext) -> String? {
        if isSilent && context.isMicrophoneOff { return StatusText.microphoneOffHelp }
        if isSilent { return StatusText.noSoundHelp(context.microphoneName) }
        if context.isSecureInputOn { return DictationState.secureInputHelp }
        return isCleaned ? StatusText.cleanupHelp : nil
    }
}
