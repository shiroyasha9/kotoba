import KotobaProviders

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
    /// How long Undo can resume after Esc; the Undo pill stays as long, or while the pointer holds it.
    var undoWindow = Duration.seconds(5)
    /// A development build gives way to the release app (`InstallYield`): its idle pill starts nothing.
    var isYielding = false

    /// Microphone access is off: the mic gives nothing, and the fix is in System Settings.
    var isMicrophoneOff: Bool { microphone == .denied }
}
