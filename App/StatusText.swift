import KotobaCore

/// The words for each `DictationState`, shared by the menu and the indicator pill, so the two
/// always say the same thing.
extension DictationState {
    /// The message of a dictation that ended without a plain paste; nil for the other states.
    /// `provider` names the current route's provider (OpenRouter, xAI, Azure).
    func outcomeMessage(provider: String) -> String? {
        switch self {
        case .failed: "Failed - retry from the menu"
        case .needsSetup(_, .key): "Set your \(provider) key"
        case .needsSetup(_, .endpoint): "Set the \(provider) endpoint in Settings"
        case .rejected: "Refused - check the key or credits"
        case .cleanupFailed: "Cleanup failed - pasted the raw text"
        case .recovered: "Recovered - see the menu"
        case .copied: "Copied - press Cmd-V"
        case .captureFailed: "Microphone unavailable"
        case .idle, .recording, .transcribing, .undoable: nil
        }
    }

    /// Recovered and copied are good news; the other outcomes ask the owner to act.
    var isGoodOutcome: Bool {
        switch self {
        case .recovered, .copied: true
        default: false
        }
    }

    /// The first line of the menu.
    func menuText(provider: String) -> String {
        switch self {
        case .idle: "Ready - tap Ctrl+Opt+Cmd"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .undoable: "Cancelled - Undo available"
        default: outcomeMessage(provider: provider) ?? ""
        }
    }
}
