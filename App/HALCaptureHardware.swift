import Foundation
import KotobaCore

/// `AudioCapture`'s hardware on CoreAudio: the device list (`AudioDevices`), an input through the HAL output unit
/// (`HALInput`), the settling watch of a mic in the middle of a change (`SettlingInput`) and the FLAC writer
/// (`CaptureWriter`), all on one sample ring. It runs what the capture asks and decides nothing; the lifecycle rules
/// live in `AudioCapture` (KotobaCore), where tests drive them through a fake.
///
/// Audio arrives one hardware cycle (about 10 ms) at a time, so stop waits at most about one cycle for the audio that
/// holds the stop moment. An AVAudioEngine input tap delivered 100 ms buffers, which made stop wait up to 100 ms
/// (docs/research/memory-spike.md).
final class HALCaptureHardware: CaptureHardware {
    private let ring = SampleRing()
    private let preferences: MicrophonePreferences

    init(preferences: MicrophonePreferences) {
        self.preferences = preferences
    }

    func devices() -> [AudioDevice] {
        AudioDevices.all()
    }

    func defaultInput() -> AudioDevice? {
        AudioDevices.defaultInput()
    }

    func microphoneOrder() -> [String] {
        preferences.order
    }

    func observeDevices(_ onChange: @escaping @Sendable (AudioDeviceChange) -> Void) -> AnyObject {
        AudioDevices.observe(onChange)
    }

    func openInput(on device: AudioDevice, onRouteChange: @escaping @Sendable () -> Void) throws -> any CaptureInput {
        try HALInput(device: device.id, ring: ring, onChange: onRouteChange)
    }

    func watchSettling(of device: AudioDevice, onChange: @escaping @Sendable () -> Void) -> AnyObject {
        SettlingInput(device: device.id, onChange: onChange)
    }

    func markCaptureStart() -> Int {
        ring.beginCapture()
    }

    func makeRecorder(
        files: CaptureFiles,
        sampleRate: Double,
        readingFrom position: Int,
        events: AsyncStream<CaptureEvent>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) throws -> any CaptureRecorder {
        try CaptureWriter(
            file: files.recording, upload: files.upload, sampleRate: sampleRate, ring: ring, readingFrom: position,
            events: events, levels: levels)
    }
}

extension AudioCapture {
    /// Posted on the main actor when the mic in use (`inputInUse`) changes, for the Microphone pane.
    static let inputDidChange = Notification.Name("AudioCapture.inputDidChange")

    init(preferences: MicrophonePreferences) {
        self.init(hardware: HALCaptureHardware(preferences: preferences)) {
            Task { @MainActor in NotificationCenter.default.post(name: Self.inputDidChange, object: nil) }
        }
    }

    /// The Settings mic test (`beginTest`). It does not start when the mic is not allowed, so Settings never prompts.
    nonisolated func test(for duration: Duration) async -> MicrophoneTest {
        guard Readiness.Microphone.current == .allowed else {
            Log.audio.notice("The mic test did not start: the mic is not allowed")
            return .blocked(.notAllowed)
        }
        return await beginTest(for: duration)
    }
}
