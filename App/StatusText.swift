import Foundation
import KotobaCore
import KotobaProviders

/// Status lines that belong to no `DictationState`, and the text helpers the menu and panes share.
enum StatusText {
    /// How to dictate with the owner's chords: "Press ⌃⌥⌘ to dictate", or "Press ⌃⌥⌘ or hold ⌥ to dictate" while push to
    /// talk has a chord of its own. Every text that names the chords reads them, so it follows a new recording.
    @MainActor static var ready: String { howToDictate(.shared) }

    @MainActor static func howToDictate(_ chords: HotkeyChords) -> String {
        guard let pushToTalk = chords.separatePushToTalk else { return "Press \(chords.handsFree.title) to dictate" }
        return "Press \(chords.handsFree.title) or hold \(pushToTalk.title) to dictate"
    }

    /// The dictation chords as a list: "⌃⌥⌘", or "⌃⌥⌘ and ⌥" while push to talk has a chord of its own.
    @MainActor static func dictationChords(_ chords: HotkeyChords) -> String {
        guard let pushToTalk = chords.separatePushToTalk else { return chords.handsFree.title }
        return "\(chords.handsFree.title) and \(pushToTalk.title)"
    }

    /// The history database cannot be read: the panes' failure state (title and message) and the menu status line.
    static let historyReadFailedTitle = "Couldn’t Read History"
    static let historyReadFailedMessage = "Quit and reopen kotoba."
    static let historyUnavailable = "Couldn’t read history. \(historyReadFailedMessage)"
    /// A development build while the release app runs (`InstallYield`): the menu status line and the pill.
    static let yieldsToRelease = "Quit kotoba to dictate with \(Install.displayName)"
    /// The idle pill's help tag ("Show indicator: Always").
    static let idlePillHelp = "Click to start dictating"
    /// What VoiceOver calls the pill's click, a button beside the pill's text and its action button.
    static func pillClickLabel(_ click: PillClick) -> String {
        switch click {
        case .startsDictation: "Start Dictating"
        case .stopsDictation: "Stop Dictating"
        }
    }
    /// The help tag of a recording pill whose dictation will be cleaned up (the cleanup chord, or the app's mode).
    static let cleanupHelp = "kotoba cleans up this dictation before it pastes."

    /// The recording pill while the mic gives no sound. It leaves out the mic's name to fit next to the button; the
    /// menu's Microphone item and the pill's help tag name it.
    static let noSound = "No sound from the mic"

    /// The silent recording pill's help tag; `microphone` is the device's name.
    static func noSoundHelp(_ microphone: String?) -> String {
        "kotoba hears nothing from \(microphone ?? "the microphone"). Check that it’s on and not muted."
    }

    /// About the longest pill message that fits beside its button in the 360 pt pill (CODING_STANDARDS.md, "User-facing
    /// text" 7); the snapshot run checks the samples.
    static let pillCharacters = 34

    /// The pill when the owner's endpoint does not resolve: it names the host's first label, the resource name the
    /// owner typed, so a typo in it shows; a name too long for the pill is left out.
    static func hostNotFound(_ host: String) -> String {
        let named = "Can’t find \(host.prefix { $0 != "." }). Will retry."
        return named.count <= pillCharacters ? named : "Endpoint not found. Will retry."
    }

    /// The idle pill's hover, before the hands-free chord's keys: a chord never shows alone (owner, 2026-10-25).
    static let dictate = "Dictate"
    /// The recording pill while another app has Secure Input on: it explains why a paste can fail (owner, 2026-10-24).
    static let secureInputOn = "Secure Input is on"

    /// What VoiceOver reads for the recording pill: "Recording, hands-free, with cleanup, 10 minutes 12 seconds".
    static func recordingLabel(isHandsFree: Bool, isCleaned: Bool, elapsed: Duration?, words: String?) -> String {
        var parts = [isHandsFree ? "Recording, hands-free" : "Recording"]
        if isCleaned { parts.append("with cleanup") }
        if let elapsed { parts.append(elapsed.formatted(.units(allowed: [.minutes, .seconds], width: .wide))) }
        if let words { parts.append(words) }
        return parts.joined(separator: ", ")
    }
    /// What VoiceOver reads for the pill while text is on its way, and once it is pasted.
    static func processingLabel(_ step: PillStep) -> String {
        switch step {
        case .transcribing: "Transcribing"
        case .cleaningUp: "Cleaning up"
        case .rewriting: "Rewriting"
        }
    }
    static let pastedLabel = "Pasted"
    /// The hands-free pill's buttons, as VoiceOver reads them.
    static let cancelLabel = "Cancel"
    static let stopLabel = "Stop"

    /// The pill when the mic gives nothing because Microphone access was turned off (at a press, or while recording).
    static let microphoneOff = "Microphone access is off"
    /// The pill's words for `microphoneOff`: beside the fix and Stop, the long form does not fit the 360 pt pill.
    static let micAccessOff = "Mic access is off"
    /// The silent recording pill's help tag when Microphone access is off.
    static let microphoneOffHelp = "Turn on kotoba in System Settings > Privacy & Security > Microphone."

    /// The Microphone menu and pane warning while a Bluetooth mic is in use (`MicrophoneWarning`).
    static func title(_ warning: MicrophoneWarning) -> String {
        switch warning {
        case .bluetoothMic: "Bluetooth microphone: lower quality"
        }
    }

    /// The note on a Bluetooth mic that is not in use, in the Microphone pane's rows and Add menu: the same
    /// phrase as `title(_:)`.
    static let bluetoothMicNote = "Bluetooth: lower quality"

    /// The pill and menu when the Microphone page's switch kept out the only mic, a Bluetooth one outside the list.
    /// The reason first, so a long name is what the pill cuts.
    static func notListed(_ mic: String) -> String {
        "Not in mic list: \(mic)"
    }

    /// The second line under `title(_:)`.
    static func detail(_ warning: MicrophoneWarning) -> String {
        switch warning {
        case .bluetoothMic(interruptsPlayback: true):
            "Playback drops to call quality, and this microphone can miss your first word."
        case .bluetoothMic(interruptsPlayback: false):
            "This microphone can start late and miss your first word."
        }
    }

    /// The pill after auto-learn added a word to the dictionary.
    static func learned(_ word: String) -> String {
        "Added “\(word)”"
    }

    /// What the owner adds for a dictation that waits: "Add your OpenRouter key".
    static func add(_ item: SetupItem, for account: ProviderAccount) -> String {
        switch item {
        case .key: "Add your \(account.title) key"
        case .endpoint: "Add your \(account.title) endpoint"
        case .credit: "Add credit at \(account.title)"
        }
    }

    /// A shortcut's name, as the Shortcuts page, Home and onboarding label it.
    static func shortcutTitle(_ role: ChordRole) -> String {
        switch role {
        case .handsFree: "Hands-free"
        case .pushToTalk: "Push to talk"
        case .cleanup: "Dictate with cleanup"
        case .pasteLast: "Paste last dictation"
        case .copyLast: "Copy last dictation"
        case .polishLast: "Rewrite last dictation"
        }
    }

    /// What a shortcut does: the line under its name. "Press" and "hold", as Apple writes keys (plan, Copy).
    static func shortcutHelp(_ role: ChordRole) -> String {
        switch role {
        case .handsFree: "Press to start. Press again to stop and paste."
        case .pushToTalk: "Hold while you speak. Let go to paste."
        case .cleanup:
            "Press or hold to dictate. Removes filler words and fixes punctuation; the paste comes 1 to 2 seconds "
                + "later."
        case .pasteLast: "Pastes your last dictation again."
        case .copyLast: "Puts your last dictation on the clipboard."
        case .polishLast: "Makes your last dictation shorter and clearer."
        }
    }

    /// Push to talk's line. A double press records hands-free only while push to talk is its own chord: with one chord
    /// for both, a press already does.
    @MainActor static func pushToTalkHelp(_ chords: HotkeyChords) -> String {
        let help = shortcutHelp(.pushToTalk)
        return chords.separatePushToTalk == nil ? help : help + " Press it twice for hands-free."
    }

    /// The line under `cancelLabel` on the Shortcuts page, by the Esc keycap.
    static let cancelHelp = "Press while you dictate. Nothing is pasted."

    /// "10 minutes", in the system's words (plan, Copy: durations).
    static func minutes(_ count: Int) -> String {
        Duration.seconds(count * 60).formatted(.units(allowed: [.minutes], width: .wide))
    }

    /// "1 Saved Dictation", "2 Saved Dictations": Foundation's grammar agreement picks the plural.
    static func counted(_ count: Int, _ noun: String) -> String {
        String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
    }
}

/// The words for each `DictationState`, shared by the menu and the indicator pill, so the two
/// always say the same thing (copy deck: docs/research/ux-polish.md, 4.2). A notice shows in place of the phase.
extension DictationState {
    static let secureInputHelp = "Another app turned on Secure Input. kotoba still records."

    /// The pill message and the menu status line; nil when idle, where the menu shows readiness instead.
    func statusText(_ context: StatusContext) -> String? {
        notice.map { $0.statusText(context) } ?? phase.statusText(context)
    }

    /// The pill's words: only where the owner must know something or can act (a notice, Undo, a silent mic, Secure
    /// Input). Nil for a live phase, which shows its shape only; the menu's status line reads `statusText`.
    func pillText(_ context: StatusContext) -> String? {
        if context.isMicrophoneOff, notice?.isNoMic == true || notice == nil && phase.isSilentRecording {
            return StatusText.micAccessOff
        }
        if let notice { return notice.statusText(context) }
        return switch phase {
        case .recording(_, isSilent: true, _, _): phase.statusText(context)
        case .recording: context.isSecureInputOn ? StatusText.secureInputOn : nil
        case .undoable: phase.statusText(context)
        case .idle, .transcribing, .cleaning, .polishing: nil
        }
    }

    /// The one button the pill shows for this state, or nil.
    func pillAction(_ context: StatusContext) -> PillAction? {
        notice.map { $0.pillAction(context) } ?? phase.pillAction(context)
    }
}

extension DictationPhase {
    var isSilentRecording: Bool {
        if case .recording(_, isSilent: true, _, _) = self { true } else { false }
    }

    func statusText(_ context: StatusContext) -> String? {
        switch self {
        case .idle: nil
        case .recording(_, isSilent: true, _, _):
            context.isMicrophoneOff ? StatusText.microphoneOff : StatusText.noSound
        case .recording(isLong: true, _, _, _): "Still recording · \(StatusText.minutes(context.longRecordingMinutes))"
        case .recording: context.isSecureInputOn ? "Recording · Secure Input on" : "Recording"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
        case .polishing: "Rewriting"
        case .undoable: "Canceled"
        }
    }

    func pillAction(_ context: StatusContext) -> PillAction? {
        switch self {
        case .undoable: .undo
        case .recording(_, isSilent: true, _, _):
            context.isMicrophoneOff ? .openMicrophoneSettings : .chooseMicrophone
        case .idle, .recording, .transcribing, .cleaning, .polishing: nil
        }
    }
}

extension DictationNotice {
    /// A press that found no mic to record from; with Microphone access off, both say so instead.
    var isNoMic: Bool {
        switch self {
        case .captureFailed, .bluetoothMicNotListed: true
        default: false
        }
    }

    func statusText(_ context: StatusContext) -> String {
        let provider = context.provider.title
        return switch self {
        case .failed, .timedOut, .connectionBlocked, .hostNotFound, .retriesUsedUp: queuedText(provider)
        case .needsSetup(_, let item):
            item == .credit ? "No \(provider) credit. Will retry." : StatusText.add(item, for: context.provider)
        case .rejected(_, let reason): reason.text(provider: provider)
        case .captureFailed: context.isMicrophoneOff ? StatusText.microphoneOff : "No microphone found"
        case .bluetoothMicNotListed(let name):
            context.isMicrophoneOff ? StatusText.microphoneOff : StatusText.notListed(name)
        case .nothingRecorded: "Nothing was recorded. Try again."
        case .audioNotSaved(let loss):
            loss == .diskFull ? "Couldn’t save audio. Disk full?" : "Couldn’t save audio. Try again."
        case .polishFailed(let failure): failure.text
        case .cleanupFailed, .cleanupTooSlow, .returnSkipped, .recovered, .copied, .audioCut, .clipboardNotKept,
            .polished:
            deliveredText
        }
    }

    /// The dictation is kept and queued: why it was not transcribed.
    private func queuedText(_ provider: String) -> String {
        if case .retriesUsedUp = self { return "No text after \(RetrySelection.automaticAttempts) tries. Audio kept." }
        if case .timedOut = self { return "\(provider) timed out. Will retry." }
        if case .connectionBlocked = self { return "Connection blocked. Will retry." }
        if case .hostNotFound(_, let host) = self { return StatusText.hostNotFound(host) }
        return "Can’t reach \(provider). Will retry."
    }

    /// The text reached the owner, with a note on how.
    private var deliveredText: String {
        switch self {
        case .cleanupFailed: "Pasted without cleanup"
        case .cleanupTooSlow: "Pasted without cleanup: too slow"
        case .returnSkipped: "Return not pressed: app changed"
        case .recovered: "Saved dictation recovered"
        case .copied: "Copied. Press ⌘V to paste."
        case .audioCut(_, let loss):
            loss == .diskFull ? "Pasted what was saved. Disk full?" : "Pasted what was saved. Some audio was lost."
        case .clipboardNotKept: "Pasted. Old clipboard too large to keep."
        case .polished(_, let isReplaced): isReplaced ? "Rewritten" : "Rewritten and copied. Press ⌘V."
        // `statusText` says these.
        case .failed, .timedOut, .connectionBlocked, .hostNotFound, .retriesUsedUp, .needsSetup, .rejected,
            .captureFailed, .bluetoothMicNotListed, .nothingRecorded, .audioNotSaved, .polishFailed:
            ""
        }
    }

    /// A press with no mic: System Settings when access is off, else the Microphone page, where Add puts a connected mic
    /// in the list (a Bluetooth mic kept out of it, or any other; the menu's mic pick does too).
    private func micFix(_ context: StatusContext) -> PillAction {
        context.isMicrophoneOff ? .openMicrophoneSettings : .chooseMicrophone
    }

    func pillAction(_ context: StatusContext) -> PillAction? {
        switch self {
        case .failed, .timedOut, .connectionBlocked, .hostNotFound, .retriesUsedUp: .retry
        case .needsSetup(_, let item): item.pillAction
        case .recovered(let id): .copy(id)
        case .copied: context.isPasteAllowed ? nil : .allowPasting
        case .captureFailed, .bluetoothMicNotListed: micFix(context)
        case .polished(let id, isReplaced: true): .undoPolish(id)
        case .polishFailed(.needsSetup(.credit)): .addOpenRouterCredit
        case .polishFailed(.needsSetup): .addKey
        case .polishFailed(.failed), .polishFailed(.tooSlow): .retryPolish
        case .polished(_, isReplaced: false), .polishFailed(.nothingToPolish), .polishFailed(.cutOff), .rejected,
            .cleanupFailed, .cleanupTooSlow, .returnSkipped, .nothingRecorded, .audioNotSaved, .audioCut,
            .clipboardNotKept:
            nil
        }
    }
}

extension ShellStatus.MenuStatus where Missing == Readiness.Missing {
    /// The menu's first line in words.
    @MainActor func line(_ context: StatusContext) -> MenuModel.Status {
        switch self {
        case .historyUnavailable: .text(StatusText.historyUnavailable)
        case .yieldsToRelease: .text(StatusText.yieldsToRelease)
        case .dictation(let state): .text(state.statusText(context) ?? "")
        case .finishSetup(let missing): .finishSetup(missing.setupText)
        case .ready: .ready
        }
    }
}

extension SetupItem {
    /// The button that sets it: the key on the Speech page, the endpoint in its "Advanced…" sheet, credit on the
    /// provider's site.
    var pillAction: PillAction {
        switch self {
        case .key: .addKey
        case .endpoint: .addEndpoint
        case .credit: .addCredit
        }
    }
}

extension PolishFailure {
    /// Polish runs on OpenRouter whatever the speech model, so its texts name OpenRouter.
    var text: String {
        switch self {
        case .nothingToPolish: "Nothing to rewrite yet"
        case .cutOff: "Rewrite cut off. Nothing changed."
        case .tooSlow: "Rewrite too slow. Nothing changed."
        case .needsSetup(.credit): "\(ProviderAccount.openRouter.title) is out of credit"
        case .needsSetup(let item): StatusText.add(item, for: .openRouter)
        case .failed: "Couldn’t rewrite. Nothing changed."
        }
    }
}

extension RejectReason {
    func text(provider: String) -> String {
        switch self {
        case .emptyTranscript: "No speech heard"
        case .audioMissing: "Audio file is missing. Can’t retry."
        case .other: "Refused by \(provider). Audio kept."
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
