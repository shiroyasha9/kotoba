/// What to do when the chosen mic does not open (`InputFormatPolicy.recovery`).
public enum InputRecovery: Sendable, Equatable {
    /// Open the same mic once more: its format was read in the middle of a change.
    case retry
    /// Leave this mic out and let `InputDevicePolicy` choose again, so the Bluetooth rule still applies.
    case chooseAnother
    /// No input until the next device event or dictation. No other mic is opened, so a rate change on
    /// the chosen mic never pulls AirPods (the system default) into the call profile.
    case stop
}

/// Whether the mic input's format is safe to record. The input unit converts sample format and
/// channel count but not sample rate, so a hardware format that disagrees with its device (read in
/// the middle of a rate or device change) would record at the wrong rate; 0 Hz or 0 channels
/// records nothing. A rejected format fails the capture instead. (Crash of 2026-10-16: AVAudioEngine
/// stopped the app with an Objective-C exception on such a format.)
public enum InputFormatPolicy {
    public enum Rejection: Error, Sendable, Equatable {
        /// No rate or no channels: no input device, or a device in the middle of a change.
        case noAudio
        /// The input's hardware format and its device's nominal rate disagree: the device is in the
        /// middle of a rate change.
        case deviceChanged(inputRate: Double, deviceRate: Double)
        /// The device's rate cannot be read: it went away.
        case deviceGone
    }

    /// `sampleRate` and `channelCount` are the input's hardware format; `deviceSampleRate` is the
    /// nominal rate CoreAudio reports for the device the input uses now, nil when it cannot be read.
    public static func rejection(
        sampleRate: Double,
        channelCount: UInt32,
        deviceSampleRate: Double?
    ) -> Rejection? {
        guard sampleRate > 0, channelCount > 0 else { return .noAudio }
        guard let deviceSampleRate else { return .deviceGone }
        guard deviceSampleRate == sampleRate else {
            return .deviceChanged(inputRate: sampleRate, deviceRate: deviceSampleRate)
        }
        return nil
    }

    /// After the chosen mic failed to open on `attempt` (1 for the first try). `rejection` is nil
    /// when the input unit itself failed, not the format check.
    public static func recovery(after rejection: Rejection?, attempt: Int) -> InputRecovery {
        switch rejection {
        case .noAudio, .deviceChanged: attempt < 2 ? .retry : .stop
        case .deviceGone, nil: .chooseAnother
        }
    }
}
