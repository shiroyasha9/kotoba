import Foundation
import KotobaCore
import KotobaProviders

/// Status lines that belong to no `DictationState`, and the text helpers the menu and panes share.
enum StatusText {
    /// The owner's dictation chord; every text that names it uses this, so it follows a new recording.
    @MainActor static var dictationChord: String { HotkeyChords.shared.dictation.title }
    @MainActor static var ready: String { "Tap \(dictationChord) to dictate" }
    /// The chord with its keys in words when it has symbols: "⌃⌥⌘ (Control-Option-Command)", or "fn".
    @MainActor static var dictationChordNamed: String {
        let chord = HotkeyChords.shared.dictation
        return chord.hasSymbols ? "\(chord.title) (\(chord.spokenTitle))" : chord.title
    }
    static let historyUnavailable = "History unavailable. Quit and reopen kotoba."
    /// A development build while the release app runs (`InstallYield`): the menu status line and the pill.
    static let yieldsToRelease = "Quit kotoba to dictate with \(Install.displayName)"
    /// The idle pill's help tag ("Show indicator: Always").
    static let idlePillHelp = "Click to start dictating"
    /// The help tag of a recording pill whose dictation will be cleaned up (the cleanup chord, or the app's mode).
    static let cleanupHelp = "kotoba cleans up this dictation before it pastes."

    /// The recording pill while the mic gives no sound. It leaves out the mic's name to fit next to the button; the
    /// menu's Microphone item and the pill's help tag name it.
    static let noSound = "No sound from the mic"

    /// The silent recording pill's help tag; `microphone` is the device's name.
    static func noSoundHelp(_ microphone: String?) -> String {
        "kotoba hears nothing from \(microphone ?? "the mic"). Check that it is on and not muted."
    }

    /// The Microphone menu and pane warning while a Bluetooth mic is in use (`MicrophoneWarning`).
    static func title(_ warning: MicrophoneWarning) -> String {
        switch warning {
        case .bluetoothMic: "Bluetooth mic: call-quality audio"
        }
    }

    /// The note on a Bluetooth mic that is not in use, in the Microphone pane's rows and Add menu: the same
    /// phrase as `title(_:)`.
    static let bluetoothMicNote = "Bluetooth: call-quality audio"

    /// The second line under `title(_:)`.
    static func detail(_ warning: MicrophoneWarning) -> String {
        switch warning {
        case .bluetoothMic(interruptsPlayback: true):
            "Playback drops to call quality. Start and stop are slower, and kotoba can miss the first word."
        case .bluetoothMic(interruptsPlayback: false):
            "Start and stop are slower, and kotoba can miss the first word."
        }
    }

    /// The pill after auto-learn added a word to the dictionary.
    static func learned(_ word: String) -> String {
        "Added \(word)"
    }

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
    /// The mic capture opened, named in the no-sound warning.
    var microphoneName: String?
    var longRecordingMinutes = 10
    /// How long Undo can resume after Esc; the Undo pill's bar runs over it.
    var undoWindow = Duration.seconds(5)
    /// A development build gives way to the release app (`InstallYield`): its idle pill starts nothing.
    var isYielding = false
}

/// The words for each `DictationState`, shared by the menu and the indicator pill, so the two
/// always say the same thing (copy deck: docs/research/ux-polish.md, 4.2).
extension DictationState {
    static let secureInputHelp = "Another app turned on Secure Input. kotoba still records."

    /// The pill message and the menu status line; nil when idle, where the menu shows readiness instead.
    func statusText(_ context: StatusContext) -> String? {
        switch self {
        case .idle: nil
        case .recording(_, isSilent: true, _): StatusText.noSound
        case .recording(isLong: true, _, _): "Still listening · \(context.longRecordingMinutes) min"
        case .recording: context.isSecureInputOn ? "Listening · Secure Input on" : "Listening"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
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
        case .captureFailed: context.microphone == .denied ? "Microphone access is off" : "No microphone found"
        default: deliveredText
        }
    }

    /// The text reached the owner, with a note on how.
    private var deliveredText: String? {
        switch self {
        case .cleanupFailed: "Pasted without cleanup"
        case .cleanupTooSlow: "Cleanup too slow: pasted as spoken"
        case .returnSkipped: "Didn’t press Return: app changed"
        case .recovered: "Saved dictation recovered"
        case .copied: "Copied. Press ⌘V to paste."
        case .idle, .recording, .transcribing, .cleaning, .undoable, .failed, .needsSetup, .rejected, .captureFailed:
            nil
        }
    }

    /// The one button the pill shows for this state, or nil.
    func pillAction(_ context: StatusContext) -> PillAction? {
        switch self {
        case .undoable: .undo
        case .recording(_, isSilent: true, _): .chooseMicrophone
        case .failed: .retry
        case .needsSetup(_, .key): .addKey
        case .needsSetup(_, .endpoint): .openSpeechSettings
        case .needsSetup(_, .credit): .addCredit
        case .recovered: .copy
        case .copied: context.isPasteAllowed ? nil : .allowPasting
        case .captureFailed: context.microphone == .denied ? .openMicrophoneSettings : nil
        case .idle, .recording, .transcribing, .cleaning, .rejected, .cleanupFailed, .cleanupTooSlow, .returnSkipped:
            nil
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

    /// Home's line under “Not ready to dictate”: what the missing item leaves undone.
    var problemText: String {
        switch self {
        case .microphone: "kotoba can’t use the microphone yet."
        case .accessibility: "kotoba can’t hear your shortcut or paste yet."
        case .setup(.key, let account): "kotoba has no \(account.title) key yet."
        case .setup(.endpoint, let account): "kotoba has no \(account.title) endpoint yet."
        case .setup(.credit, let account): "\(account.title) is out of credit."
        }
    }
}
