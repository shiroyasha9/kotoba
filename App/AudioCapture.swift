import AVFAudio
import Foundation
import KotobaCore
import Synchronization
import os

/// Microphone capture through a `HALInput` on one device. The input is prepared while idle and runs
/// only from `beginCapture` to the end or cancel call, so the mic (and its orange dot) is on only
/// while recording. Audio goes to a 16 kHz mono FLAC file from the first buffer.
///
/// Audio arrives one hardware cycle (about 10 ms) at a time, so stop waits at most about one cycle
/// for the audio that holds the stop moment. An AVAudioEngine input tap delivered 100 ms buffers,
/// which made stop wait up to 100 ms (docs/research/memory-spike.md).
actor AudioCapture: AudioSource {
    enum CaptureError: Error {
        case noInputDevice
        case notCapturing
    }

    /// Mic level 0...1, about ten updates a second while recording, for the indicator.
    nonisolated let levels: AsyncStream<Float>
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let ring = SampleRing()
    private var input: HALInput?
    private(set) var writer: CaptureWriter?
    /// In the Undo window after Esc: the input is stopped, the writer and its file stay open.
    private var isPaused = false
    /// Route changes arrive from two sources and can overlap; one rebuild runs at a time and a
    /// request during it causes one more pass.
    private var isRebuilding = false
    private var isRebuildRequested = false
    /// The chosen mic did not open in the middle of a change; its next change builds the input again.
    private var settling: SettlingInput?
    /// An Undo that waits for the rebuild in progress, so the new input starts after the writer switched its rate.
    private var rebuildWaiters: [CheckedContinuation<Void, Never>] = []
    private let preferences: MicrophonePreferences
    /// The mic the input records from; a device change rebuilds only when this changes. Kept under a
    /// lock too, so the menu and Settings can read it without waiting on the actor.
    private(set) var currentInput: AudioDevice? {
        didSet {
            inputInUseValue.withLock { $0 = currentInput }
            if currentInput?.uid != oldValue?.uid {
                Task { @MainActor in NotificationCenter.default.post(name: Self.inputDidChange, object: nil) }
            }
        }
    }
    /// Posted on the main actor when the mic in use (`inputInUse`) changes, for the Microphone pane.
    static let inputDidChange = Notification.Name("AudioCapture.inputDidChange")
    private nonisolated let inputInUseValue = Mutex<AudioDevice?>(nil)
    /// Device and default changes, observed from `prepare` for the app's whole life.
    private var deviceObservation: AudioDeviceObservation?
    /// A device burst (connect, then default change) is handled once: one check queued, not one per event.
    private var isDeviceCheckQueued = false
    /// A mic change that arrived during a capture; it applies when the capture ends.
    private var isInputChangeDeferred = false
    /// The Settings mic test's level stream, while a test records into a throwaway file (MicrophoneTest.swift).
    var testLevels: AsyncStream<Float>.Continuation?
    var testTimer: Task<Void, Never>?

    init(preferences: MicrophonePreferences) {
        self.preferences = preferences
        (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// The mic kotoba records from (or will, at the next dictation), for the menu and Settings.
    nonisolated var inputInUse: AudioDevice? {
        inputInUseValue.withLock { $0 }
    }

    /// Builds the input and initializes it, so key-down only starts it. Call after microphone access
    /// is granted. An input that a chord press built while the prompt waited is kept.
    func prepare() {
        if input == nil {
            input = makeInput()
        }
        guard deviceObservation == nil else { return }
        deviceObservation = AudioDevices.observe { [weak self] change in
            Task { await self?.devicesChanged(change) }
        }
    }

    private func devicesChanged(_ change: AudioDevices.Change) async {
        // The prepared unit and its device listeners belong to the service that is gone: build them again at once, so
        // the next press does not fail first.
        if change == .serviceRestarted {
            await requestRebuild(reason: "audio service restarted")
            return
        }
        guard !isDeviceCheckQueued else { return }
        isDeviceCheckQueued = true
        await Task.yield()
        isDeviceCheckQueued = false
        await inputMayHaveChanged()
    }

    /// Devices connected or disconnected, the default changed, or the owner reordered the mics.
    /// During a capture only the loss of the mic in use switches at once; any other change waits for
    /// the next dictation, so the voice never changes mic mid-sentence.
    func inputMayHaveChanged() async {
        let devices = AudioDevices.all()
        guard preferences.preferredInput(among: devices)?.uid != currentInput?.uid else { return }
        if writer != nil, devices.contains(where: { $0.uid == currentInput?.uid }) {
            isInputChangeDeferred = true
            return
        }
        await requestRebuild(reason: "microphone choice changed")
    }

    private func applyDeferredInputChange() async {
        guard isInputChangeDeferred, writer == nil else { return }
        isInputChangeDeferred = false
        await inputMayHaveChanged()
    }

    func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent> {
        // A dictation ends a mic test; this costs one input restart, only when a test runs.
        await endTest()
        return try startCapture(into: file, levels: levelContinuation)
    }

    func startCapture(
        into file: URL, levels: AsyncStream<Float>.Continuation
    ) throws -> AsyncStream<CaptureEvent> {
        // The input starts first; audio waits in the ring while the file and converter are made
        // (about 0.2 ms, or about 11 ms the first time in a process).
        let readPosition = ring.beginCapture()
        let input = try startInput()
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let writer: CaptureWriter
        do {
            writer = try CaptureWriter(
                file: file,
                sampleRate: input.sampleRate,
                ring: ring,
                readingFrom: readPosition,
                events: continuation,
                levels: levels
            )
        } catch {
            stopInput()
            throw error
        }
        writer.start()
        self.writer = writer
        return events
    }

    /// Starts the prepared input, or builds one when none is prepared. A unit that does not start stays broken (the
    /// audio service restarted, the device went away), so it is dropped and one new input is tried in the same press;
    /// when that fails too, the error goes to the pipeline and the next press builds again. The rebuild costs one
    /// input build, only after a failure.
    private func startInput() throws -> HALInput {
        if let input {
            do {
                try input.start()
                return input
            } catch {
                Log.audio.error("The mic did not start; building a new input: \(error)")
                self.input = nil
            }
        }
        guard let rebuilt = makeInput() else { throw CaptureError.noInputDevice }
        input = rebuilt
        do {
            try rebuilt.start()
        } catch {
            input = nil
            throw error
        }
        return rebuilt
    }

    func endCapture() async -> RecordedAudio? {
        guard let writer else { return nil }
        self.writer = nil
        // Keep the hardware cycle that holds the stop moment, so the last word is not cut. With no input running (none
        // opened, or a rebuild in progress) that cycle never comes: what arrived is written at once, not after the
        // writer's 300 ms guard.
        let isInputRunning = input != nil && !isRebuilding
        let audio = await isInputRunning ? writer.stop(after: mach_absolute_time()) : writer.stopNow()
        // Stopping the input runs after the audio goes to upload.
        Task {
            self.stopInputIfIdle()
            await self.applyDeferredInputChange()
        }
        return audio
    }

    func pauseCapture() async {
        guard writer != nil else { return }
        isPaused = true
        stopInput()
    }

    func resumeCapture() async throws {
        // A rebuild during the Undo window leaves the new input stopped (paused) once the writer switched its rate.
        while isRebuilding {
            await withCheckedContinuation { rebuildWaiters.append($0) }
        }
        guard let writer, let input else { throw CaptureError.notCapturing }
        do {
            try input.start()
            isPaused = false
        } catch {
            // As at a press (`startInput`): a unit that does not start is built again once. Not paused, the rebuild
            // starts the new input after the writer has switched to its sample rate.
            Log.audio.error("The mic did not resume; building a new input: \(error)")
            isPaused = false
            await requestRebuild(reason: "the mic did not resume")
            guard self.writer === writer, self.input != nil else { throw error }
        }
    }

    func cancelCapture() async -> RecordedAudio? {
        guard let writer else { return nil }
        self.writer = nil
        isPaused = false
        stopInput()
        let audio = await writer.stopNow()
        await applyDeferredInputChange()
        return audio
    }

    /// A capture that began in the meantime keeps the input running.
    private func stopInputIfIdle() {
        guard writer == nil else { return }
        stopInput()
    }

    private func stopInput() {
        input?.stop()
        levelContinuation.yield(0)
    }

    /// A new input on the mic chosen by `InputDevicePolicy`, feeding the ring; nil when no mic opens.
    /// A mic that fails is retried or left out as `InputFormatPolicy.recovery` decides, and the policy
    /// then chooses among the rest, so a failure never opens a Bluetooth default the rule avoids.
    private func makeInput() -> HALInput? {
        settling = nil
        var devices = AudioDevices.all()
        var attempt = 1
        while let device = preferences.preferredInput(among: devices), devices.contains(device) {
            do {
                let input = try HALInput(device: device.id, ring: ring) { [weak self] in
                    Task { await self?.requestRebuild(reason: "audio route changed") }
                }
                currentInput = device
                Log.audio.info("Recording from \(device.name, privacy: .public)")
                return input
            } catch {
                Log.audio.error("Cannot record from \(device.name, privacy: .public): \(String(describing: error))")
                var rejection: InputFormatPolicy.Rejection?
                if case .format(let format) = error as? HALInput.Failure {
                    rejection = format
                }
                switch InputFormatPolicy.recovery(after: rejection, attempt: attempt) {
                case .retry:
                    attempt += 1
                case .chooseAnother:
                    devices.removeAll { $0.uid == device.uid }
                    attempt = 1
                case .waitForDevice:
                    devices = []
                    settling = SettlingInput(device: device.id) { [weak self] in
                        Task { await self?.requestRebuild(reason: "the mic finished its change") }
                    }
                }
            }
        }
        currentInput = nil
        return nil
    }

    private func requestRebuild(reason: String) async {
        Log.audio.info("Rebuilding the mic input: \(reason, privacy: .public)")
        isRebuildRequested = true
        guard !isRebuilding else { return }
        isRebuilding = true
        while isRebuildRequested {
            isRebuildRequested = false
            await rebuildInput()
        }
        isRebuilding = false
        let waiting = rebuildWaiters
        rebuildWaiters = []
        for waiter in waiting { waiter.resume() }
    }

    private func rebuildInput() async {
        input?.stop()
        let rebuilt = makeInput()
        input = rebuilt
        guard let writer else { return }
        guard let rebuilt else {
            // No mic opened during a capture: no more audio comes until a mic does.
            writer.inputLost()
            return
        }
        await writer.switchSampleRate(to: rebuilt.sampleRate)
        // The capture may have ended, paused or been rebuilt again during the await. Start the
        // input only for the same capture, still live, on the input built here.
        guard self.writer === writer, input === rebuilt, !isPaused, !isRebuildRequested else {
            return
        }
        do {
            try rebuilt.start()
        } catch {
            Log.audio.error("Capture could not continue after the route change: \(error)")
            writer.inputLost()
        }
    }
}

// MARK: - Discarded recordings

extension AudioCapture {
    @discardableResult
    func discardCapture() async -> Bool {
        guard let audio = await cancelCapture() else { return true }
        return await discard(audio)
    }

    @discardableResult
    func discard(_ audio: RecordedAudio) async -> Bool {
        do {
            try FileManager.default.removeItem(at: audio.file)
            return true
        } catch {
            Log.audio.error("Cannot delete discarded audio: \(error)")
            return false
        }
    }
}
