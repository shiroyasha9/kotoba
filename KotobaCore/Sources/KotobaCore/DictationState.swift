/// What the pipeline shows after each change: the phase, and the notice the indicator and the menu show over it.
public struct DictationState: Sendable, Equatable {
    /// What is live now, under a notice too: one dictation's notice can show while the next is in flight.
    public var phase: DictationPhase
    /// The outcome of what ended last (a dictation, a retry, Polish, Paste Last). It shows in place of the phase until
    /// the next phase change; nil shows the phase.
    public var notice: DictationNotice?

    public static let idle = Self(.idle)

    public init(_ phase: DictationPhase, notice: DictationNotice? = nil) {
        self.phase = phase
        self.notice = notice
    }
}

/// A one-shot outcome: what ended, and how. A new outcome is a case here with its two facts below, and its words and
/// button in App/StatusText.swift; the compiler names each place.
public enum DictationNotice: Sendable, Equatable {
    /// Transcription failed. The audio is kept and queued for retry.
    case failed(DictationID)
    /// The route did not answer in time (`ProviderError.timedOut`). The audio is kept and queued for retry.
    case timedOut(DictationID)
    /// The network blocked the secure connection (`ProviderError.connectionBlocked`). The audio is kept and queued.
    case connectionBlocked(DictationID)
    /// The owner's endpoint `host` does not resolve (`ProviderError.hostNotFound`). The audio is kept and queued.
    case hostNotFound(DictationID, host: String)
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
    /// Polish replaced the old text with its own (`isReplaced`, Undo can bring it back), or left it on the clipboard
    /// because it could not replace it safely.
    case polished(DictationID, isReplaced: Bool)
    /// Polish pasted nothing and changed nothing.
    case polishFailed(PolishFailure)

    /// Good news, drawn in green; the other notices ask the owner to act, drawn in orange.
    public var isGood: Bool {
        switch self {
        case .recovered, .copied, .polished: true
        case .failed, .timedOut, .connectionBlocked, .hostNotFound, .rejected, .needsSetup, .cleanupFailed,
            .cleanupTooSlow, .returnSkipped, .captureFailed, .nothingRecorded, .audioNotSaved, .audioCut,
            .clipboardNotKept, .polishFailed:
            false
        }
    }

    /// Its words and button depend on the microphone and Accessibility grants now, so the shell reads them again (I2).
    public var dependsOnGrants: Bool {
        switch self {
        case .captureFailed, .copied: true
        case .failed, .timedOut, .connectionBlocked, .hostNotFound, .rejected, .needsSetup, .cleanupFailed,
            .cleanupTooSlow, .returnSkipped, .recovered, .nothingRecorded, .audioNotSaved, .audioCut, .clipboardNotKept,
            .polished, .polishFailed:
            false
        }
    }

    /// What the indicator shows once a dictation reaches `record.status`; nil shows nothing.
    static func outcome(of record: DictationRecord) -> Self? {
        switch record.status {
        case .recovered: .recovered(record.id)
        case .rejected: .rejected(record.id, record.rejectReason ?? .other)
        case .copied: .copied(record.id)
        case .failed where record.needsSetup != nil: .needsSetup(record.id, record.needsSetup ?? .key)
        case .failed: queued(record)
        case .pending: .failed(record.id)
        // A row saved during a quit shows nothing: the app is going.
        case .pasted, .notPasted, .cancelled: nil
        }
    }

    /// A queued dictation, by why its last send failed. "Offline" would send the owner to check a network that works.
    private static func queued(_ record: DictationRecord) -> Self {
        switch record.lastError {
        case .timedOut: .timedOut(record.id)
        case .connectionBlocked: .connectionBlocked(record.id)
        case .hostNotFound(let host): .hostNotFound(record.id, host: host)
        default: .failed(record.id)
        }
    }
}
