import Foundation
import KotobaCore
import KotobaProviders

/// Status lines that belong to no `DictationState`, and the text helpers the menu and panes share.
enum StatusText {
    /// The dictation chord, fixed in v1 (spec); every text that names it uses this.
    static let dictationChord = "⌃⌥⌘"
    static let ready = "Tap \(dictationChord) to dictate"
    static let historyUnavailable = "History unavailable. Quit and reopen kotoba."

    /// What the owner adds for a dictation that waits: "Add your OpenRouter key".
    static func add(_ item: SetupItem, for account: ProviderAccount) -> String {
        switch item {
        case .key: "Add your \(account.title) key"
        case .endpoint: "Add your \(account.title) endpoint"
        case .credit: "Add credit at \(account.title)"
        }
    }

    /// "1 Saved Dictation", "2 Saved Dictations": Foundation's grammar agreement picks the plural.
    static func counted(_ count: Int, _ noun: String) -> String {
        String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
    }
}

/// What the App knows at render time that a `DictationState` does not carry.
struct StatusContext {
    /// The current speech model's provider, named in the error texts.
    var provider: ProviderAccount
    var microphone = Readiness.Microphone.allowed
    /// Accessibility: without it kotoba copies the text instead of pasting.
    var isPasteAllowed = true
    var isSecureInputOn = false
    var longRecordingMinutes = 10
}

/// The words for each `DictationState`, shared by the menu and the indicator pill, so the two
/// always say the same thing (copy deck: docs/research/ux-polish.md, 4.2).
extension DictationState {
    static let secureInputHelp = "Another app turned on Secure Input. kotoba still records."

    /// The pill message and the menu status line; nil when idle, where the menu shows readiness instead.
    func statusText(_ context: StatusContext) -> String? {
        switch self {
        case .idle: nil
        case .recording(isLong: true): "Still listening · \(context.longRecordingMinutes) min"
        case .recording: context.isSecureInputOn ? "Listening · Secure Input on" : "Listening"
        case .transcribing: "Transcribing"
        case .undoable: "Cancelled"
        default: outcomeText(context)
        }
    }

    private func outcomeText(_ context: StatusContext) -> String? {
        let provider = context.provider.title
        return switch self {
        case .failed: "Couldn’t reach \(provider). Saved."
        case .needsSetup(_, .credit): "\(provider) is out of credit. Saved."
        case .needsSetup(_, let item): StatusText.add(item, for: context.provider)
        case .rejected(_, let reason): reason.text(provider: provider)
        case .cleanupFailed: "Pasted without cleanup"
        case .recovered: "Saved dictation recovered"
        case .copied: "Copied. Press ⌘V to paste."
        case .captureFailed: context.microphone == .denied ? "Microphone access is off" : "No microphone found"
        case .idle, .recording, .transcribing, .undoable: nil
        }
    }

    /// The one button the pill shows for this state, or nil.
    func pillAction(_ context: StatusContext) -> PillAction? {
        switch self {
        case .undoable: .undo
        case .failed: .retry
        case .needsSetup(_, .key): .addKey
        case .needsSetup(_, .endpoint): .openSpeechSettings
        case .needsSetup(_, .credit): .addCredit
        case .recovered: .copy
        case .copied: context.isPasteAllowed ? nil : .allowPasting
        case .captureFailed: context.microphone == .denied ? .openMicrophoneSettings : nil
        case .idle, .recording, .transcribing, .rejected, .cleanupFailed: nil
        }
    }

    /// Recovered and copied are good news; the other outcomes ask the owner to act.
    var isGoodOutcome: Bool {
        switch self {
        case .recovered, .copied: true
        default: false
        }
    }
}

extension RejectReason {
    func text(provider: String) -> String {
        switch self {
        case .emptyTranscript: "No speech heard"
        case .other: "\(provider) refused the audio. Saved."
        }
    }
}

extension Readiness.Missing {
    /// The subtitle of "Finish Setting Up kotoba…": the first thing to do.
    var setupText: String {
        switch self {
        case .microphone: "Allow the microphone"
        case .accessibility: "Allow Accessibility"
        case .setup(let item, let account): StatusText.add(item, for: account)
        }
    }
}
