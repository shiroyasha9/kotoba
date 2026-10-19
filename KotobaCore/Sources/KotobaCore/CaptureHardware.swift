import Foundation

/// The platform side of `AudioCapture`: the device list, a mic input on one device, and the recorder that writes a
/// capture's file. It does what it is told and reports device events; every choice (which mic, when to rebuild, when a
/// change waits for the end of a capture) is `AudioCapture`'s. The app's adapter is CoreAudio (`HALCaptureHardware`);
/// tests drive a fake. Every method runs on `AudioCapture`'s actor; the callbacks come from any thread.
public protocol CaptureHardware: Sendable {
    /// Every audio device now, inputs and outputs; empty when the list cannot be read.
    func devices() -> [AudioDevice]
    /// The system default input, nil when there is none.
    func defaultInput() -> AudioDevice?
    /// The owner's microphone order by UID, first choice first (`InputDevicePolicy`).
    func microphoneOrder() -> [String]
    /// Calls `onChange` on each device connect, disconnect and default change, and on a restart of the audio service,
    /// until the returned value is released.
    func observeDevices(_ onChange: @escaping @Sendable (AudioDeviceChange) -> Void) -> AnyObject
    /// An input on `device`, ready to start (the mic stays off until `start`), that feeds the ring the recorders read.
    /// Throws an `InputFormatPolicy.Rejection` when the device's format is not safe to record, another error when the
    /// input does not open. `onRouteChange` is called when the device's sample rate changes or it dies, until the
    /// input is released.
    func openInput(on device: AudioDevice, onRouteChange: @escaping @Sendable () -> Void) throws -> any CaptureInput
    /// Calls `onChange` once, at the next change of `device`'s rate, life, input channels or input stream formats,
    /// unless the returned value is released first (`InputRecovery.waitForDevice`).
    func watchSettling(of device: AudioDevice, onChange: @escaping @Sendable () -> Void) -> AnyObject
    /// Marks the start of a capture: the recorder made next reads the audio from this ring position on.
    func markCaptureStart() -> Int
    /// A recorder that writes the audio from ring `position` on, at `sampleRate`, into `file`. It reports the first
    /// buffer and the levels on `events`, the levels also on `levels`, and finishes `events` when the file closes.
    func makeRecorder(
        file: URL,
        sampleRate: Double,
        readingFrom position: Int,
        events: AsyncStream<CaptureEvent>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) throws -> any CaptureRecorder
}

/// A mic input on one device. Releasing it closes it.
public protocol CaptureInput: AnyObject {
    /// The device's sample rate, the rate of the audio it gives the ring.
    var sampleRate: Double { get }
    /// Turns the mic on. Throws when the device does not start (it went away, or the audio service restarted).
    func start() throws
    /// Turns the mic off; the input stays ready to start again.
    func stop()
}

/// Writes one capture's audio file from the ring, on its own thread.
public protocol CaptureRecorder: AnyObject, Sendable {
    func start()
    /// Returns once the audio up to the hardware cycle that holds this moment is written and the file is closed. A
    /// device that stops delivering ends the wait after a short guard. Nonsending, so it reads the moment on the
    /// caller's executor, before any hop: a hop could push the stop past one more hardware cycle.
    nonisolated(nonsending) func stop() async -> RecordedAudio
    /// Writes what has arrived and closes the file.
    func stopNow() async -> RecordedAudio
    /// The input was rebuilt at `sampleRate`. Returns once the audio at the old rate is written, or at once when the
    /// file is closed already.
    func switchSampleRate(to sampleRate: Double) async
}

public enum AudioDeviceChange: Sendable {
    /// The default input or output changed (the output feeds the Bluetooth mic warning), or a device connected or
    /// disconnected.
    case devices
    /// The audio service (coreaudiod) restarted, after a crash or `killall coreaudiod`: every device id, input and
    /// listener from before is stale (AudioHardware.h).
    case serviceRestarted
}
