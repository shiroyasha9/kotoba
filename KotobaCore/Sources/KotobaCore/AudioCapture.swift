import Foundation
import Synchronization
import os

/// Microphone capture and the mic input's lifecycle: which mic records, when its input is built again (a device
/// change, a route change, an audio service restart, a mic that did not start), and what waits for the end of a
/// capture. The input is prepared while idle and runs only from `beginCapture` to the end or cancel call, so the mic
/// (and its orange dot) is on only while recording. The platform work goes through `CaptureHardware`; the render
/// callback, the ring and the recorder's thread sit below that seam, so nothing here runs per buffer.
public actor AudioCapture: AudioSource {
    public enum CaptureError: Error {
        case noInputDevice
        case notCapturing
    }

    /// One capture from its start to its end or cancel: a dictation, or the Settings mic test.
    struct Capture {
        let recorder: any CaptureRecorder
        let events: AsyncStream<CaptureEvent>.Continuation
        /// No mic is open: `.inputLost` went out once, and goes out again only after a new input opened.
        var isInputLossReported = false
    }

    /// The Settings mic test: its level stream and the timer that ends it (MicrophoneTest.swift).
    struct MicTest {
        let levels: AsyncStream<Float>.Continuation
        let timer: Task<Void, Never>
    }

    /// Mic level 0...1, about ten updates a second while recording, for the indicator.
    public nonisolated let levels: AsyncStream<Float>
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let hardware: any CaptureHardware
    let clock: any PipelineClock
    private let inputDidChange: @Sendable () -> Void
    private var input: (any CaptureInput)?
    private(set) var capture: Capture?
    /// Where the recorders write the upload copies (`RecordedAudio.upload`); emptied at the first `prepare`, so a copy
    /// left by a quit or a crash goes at the next launch.
    let uploads: URL
    var micTest: MicTest?
    /// In the Undo window after Esc: the input is stopped, the recorder and its file stay open.
    private var isPaused = false
    /// Route changes arrive from two sources and can overlap; one rebuild runs at a time and a request during it
    /// causes one more pass.
    private var isRebuilding = false
    private var isRebuildRequested = false
    /// The chosen mic did not open in the middle of a change; its next change builds the input again.
    private var settling: AnyObject?
    /// An Undo that waits for the rebuild in progress, so the new input starts after the recorder switched its rate.
    private var rebuildWaiters = Waiters()
    /// The mic the input records from; a device change rebuilds only when this changes. Kept under a lock too, so the
    /// menu and Settings can read it without waiting on the actor.
    private(set) var currentInput: AudioDevice? {
        didSet {
            inputInUseValue.withLock { $0 = currentInput }
            if currentInput?.uid != oldValue?.uid {
                inputDidChange()
            }
        }
    }
    private nonisolated let inputInUseValue = Mutex<AudioDevice?>(nil)
    /// Device and default changes, observed from `prepare` for the app's whole life.
    private var deviceObservation: AnyObject?
    /// A device burst (connect, then default change) is handled once: one check queued, not one per event.
    private var isDeviceCheckQueued = false
    /// A mic change that arrived during a capture; it applies when the capture ends.
    private var isInputChangeDeferred = false

    /// `inputDidChange` is called when the mic in use (`inputInUse`) changes, for the Microphone pane. `clock` times
    /// the mic test.
    public init(
        hardware: any CaptureHardware, clock: any PipelineClock = SystemClock(),
        uploads: URL = URL.temporaryDirectory.appending(path: "\(Log.subsystem).upload-copies"),
        inputDidChange: @escaping @Sendable () -> Void = {}
    ) {
        self.hardware = hardware
        self.uploads = uploads
        self.clock = clock
        self.inputDidChange = inputDidChange
        (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// The mic kotoba records from (or will, at the next dictation), for the menu and Settings.
    public nonisolated var inputInUse: AudioDevice? {
        inputInUseValue.withLock { $0 }
    }

    /// Builds the input and initializes it, so key-down only starts it. Call after microphone access is granted. An
    /// input that a chord press built while the prompt waited is kept.
    public func prepare() {
        if input == nil {
            input = makeInput()
        }
        guard deviceObservation == nil else { return }
        Self.removeUploadCopies(in: uploads)
        deviceObservation = hardware.observeDevices { [weak self] change in
            Task { await self?.devicesChanged(change) }
        }
    }

    private func devicesChanged(_ change: AudioDeviceChange) async {
        // The prepared input and its device listeners belong to the service that is gone: build them again at once, so
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

    /// Devices connected or disconnected, the default changed, or the owner reordered the mics. During a capture only
    /// the loss of the mic in use switches at once; any other change waits for the next dictation, so the voice never
    /// changes mic mid-sentence.
    public func inputMayHaveChanged() async {
        let devices = hardware.devices()
        guard micInUse(among: devices)?.uid != currentInput?.uid else { return }
        if capture != nil, devices.contains(where: { $0.uid == currentInput?.uid }) {
            isInputChangeDeferred = true
            return
        }
        await requestRebuild(reason: "microphone choice changed")
    }

    private func applyDeferredInputChange() async {
        guard isInputChangeDeferred, capture == nil else { return }
        isInputChangeDeferred = false
        await inputMayHaveChanged()
    }

    public func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent> {
        // A dictation ends a mic test; this costs one input restart, only when a test runs.
        await endTest()
        return try startCapture(into: file, levels: levelContinuation)
    }

    func startCapture(
        into file: URL, levels: AsyncStream<Float>.Continuation
    ) throws -> AsyncStream<CaptureEvent> {
        // The input starts first; audio waits in the ring while the file and converter are made (about 0.2 ms, or
        // about 11 ms the first time in a process).
        let position = hardware.markCaptureStart()
        let input = try startInput()
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let recorder: any CaptureRecorder
        do {
            recorder = try hardware.makeRecorder(
                files: files(for: file), sampleRate: input.sampleRate, readingFrom: position, events: continuation,
                levels: levels)
        } catch {
            stopInput()
            throw error
        }
        recorder.start()
        capture = Capture(recorder: recorder, events: continuation)
        return events
    }

    /// Starts the prepared input, or builds one when none is prepared. An input that does not start stays broken (the
    /// audio service restarted, the device went away), so it is dropped and one new input is tried in the same press;
    /// when that fails too, the error goes to the pipeline and the next press builds again. The rebuild costs one
    /// input build, only after a failure.
    private func startInput() throws -> any CaptureInput {
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

    public func endCapture() async -> RecordedAudio? {
        guard let capture else { return nil }
        self.capture = nil
        // Keep the hardware cycle that holds the stop moment, so the last word is not cut. With no input running (none
        // opened, or a rebuild in progress) that cycle never comes: what arrived is written at once, not after the
        // recorder's guard.
        let isInputRunning = input != nil && !isRebuilding
        let audio = await isInputRunning ? capture.recorder.stop() : capture.recorder.stopNow()
        // Stopping the input runs after the audio goes to upload.
        Task {
            self.stopInputIfIdle()
            await self.applyDeferredInputChange()
        }
        return audio
    }

    public func pauseCapture() async {
        guard capture != nil else { return }
        isPaused = true
        stopInput()
    }

    public func resumeCapture() async throws {
        // A rebuild during the Undo window leaves the new input stopped (paused) once the recorder switched its rate.
        while isRebuilding {
            await withCheckedContinuation { rebuildWaiters.add($0) }
        }
        guard let recorder = capture?.recorder, let input else { throw CaptureError.notCapturing }
        do {
            try input.start()
            isPaused = false
        } catch {
            // As at a press (`startInput`): an input that does not start is built again once. Not paused, the rebuild
            // starts the new input after the recorder has switched to its sample rate.
            Log.audio.error("The mic did not resume; building a new input: \(error)")
            isPaused = false
            await requestRebuild(reason: "the mic did not resume")
            guard capture?.recorder === recorder, self.input != nil else { throw error }
        }
    }

    public func cancelCapture() async -> RecordedAudio? {
        guard let capture else { return nil }
        self.capture = nil
        isPaused = false
        stopInput()
        var audio = await capture.recorder.stopNow()
        // A cancelled recording is never sent at once (Esc keeps it for History, a discard deletes it): its copy goes.
        Self.removeUploadCopy(audio.upload)
        audio.upload = nil
        await applyDeferredInputChange()
        return audio
    }

    /// A capture that began in the meantime keeps the input running.
    private func stopInputIfIdle() {
        guard capture == nil else { return }
        stopInput()
    }

    private func stopInput() {
        input?.stop()
        levelContinuation.yield(0)
    }

    /// A new input on the mic chosen by `InputDevicePolicy`; nil when no mic opens. A mic that fails is retried or left
    /// out as `InputFormatPolicy.recovery` decides, and the policy then chooses among the rest, so a failure never
    /// opens a Bluetooth default the rule avoids.
    private func makeInput() -> (any CaptureInput)? {
        settling = nil
        let devices = hardware.devices()
        var leftOut: Set<String> = []
        var attempt = 1
        while let device = micInUse(among: devices, leftOut: leftOut) {
            do {
                let input = try hardware.openInput(on: device) { [weak self] in
                    Task { await self?.requestRebuild(reason: "audio route changed") }
                }
                currentInput = device
                Log.audio.info("Recording from \(device.name, privacy: .public)")
                return input
            } catch {
                Log.audio.error("Cannot record from \(device.name, privacy: .public): \(String(describing: error))")
                switch InputFormatPolicy.recovery(after: error as? InputFormatPolicy.Rejection, attempt: attempt) {
                case .retry:
                    attempt += 1
                case .chooseAnother:
                    leftOut.insert(device.uid)
                    attempt = 1
                case .waitForDevice:
                    settling = hardware.watchSettling(of: device) { [weak self] in
                        Task { await self?.requestRebuild(reason: "the mic finished its change") }
                    }
                    currentInput = nil
                    return nil
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
        rebuildWaiters.resumeAll()
    }

    private func rebuildInput() async {
        input?.stop()
        let rebuilt = makeInput()
        input = rebuilt
        guard let recorder = capture?.recorder else { return }
        guard let rebuilt else {
            // No mic opened during a capture: no more audio comes until a mic does.
            reportInputLost()
            return
        }
        capture?.isInputLossReported = false
        await recorder.switchSampleRate(to: rebuilt.sampleRate)
        // The capture may have ended, paused or been rebuilt again during the await. Start the input only for the same
        // capture, still live, on the input built here.
        guard capture?.recorder === recorder, input === rebuilt, !isPaused, !isRebuildRequested else { return }
        do {
            try rebuilt.start()
        } catch {
            Log.audio.error("Capture could not continue after the route change: \(error)")
            reportInputLost()
        }
    }

    /// No mic is open during the capture; its events say so once (`CaptureEvent.inputLost`).
    private func reportInputLost() {
        guard let events = capture?.events, capture?.isInputLossReported == false else { return }
        capture?.isInputLossReported = true
        events.yield(.inputLost)
    }
}

// MARK: - Mic choice

extension AudioCapture {
    /// The mic to record from among `devices`, without the ones in `leftOut`: the first one in the owner's order, else
    /// the system default (a Bluetooth default replaced by the built-in mic, `InputDevicePolicy`).
    private func micInUse(among devices: [AudioDevice], leftOut: Set<String> = []) -> AudioDevice? {
        InputDevicePolicy.micInUse(
            defaultInput: hardware.defaultInput(), devices: devices, order: hardware.microphoneOrder(),
            leftOut: leftOut)
    }
}

// MARK: - Discarded recordings and upload copies

extension AudioCapture {
    /// A capture's files: `file`, and its upload copy of the same name in the copies' folder.
    func files(for file: URL) -> CaptureFiles {
        CaptureFiles(
            recording: file, upload: uploads.appending(path: file.deletingPathExtension().lastPathComponent + ".ogg"))
    }

    /// Deletes an upload copy nothing sends any more; one that stays goes at the next launch.
    nonisolated static func removeUploadCopy(_ upload: URL?) {
        guard let upload else { return }
        do {
            try FileManager.default.removeItem(at: upload)
        } catch {
            Log.audio.error("Cannot delete an upload copy: \(error)")
        }
    }

    private nonisolated static func removeUploadCopies(in folder: URL) {
        let copies = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for copy in copies { removeUploadCopy(copy) }
    }

    @discardableResult
    public func discardCapture() async -> Bool {
        guard let audio = await cancelCapture() else { return true }
        return await discard(audio)
    }

    @discardableResult
    public func discard(_ audio: RecordedAudio) async -> Bool {
        // The copy goes too; the result is the recording's own, as only the FLAC can be sent again.
        Self.removeUploadCopy(audio.upload)
        do {
            try FileManager.default.removeItem(at: audio.file)
            return true
        } catch {
            Log.audio.error("Cannot delete discarded audio: \(error)")
            return false
        }
    }
}
