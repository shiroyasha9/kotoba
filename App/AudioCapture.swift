import AVFAudio
import AudioToolbox
import Foundation
import KotobaCore
import Synchronization
import os

/// Microphone capture with AVAudioEngine. The engine is prepared while idle and runs only from
/// `beginCapture` to the end or cancel call, so the mic (and its orange dot) is on only while
/// recording. Audio goes to a 16 kHz mono FLAC file from the first buffer.
///
/// Audio arrives through an `AVAudioSinkNode`, one hardware cycle (about 10 ms) at a time, so stop
/// waits at most about one cycle for the audio that holds the stop moment. An input tap delivers
/// 100 ms buffers, which made stop wait up to 100 ms (docs/research/memory-spike.md).
actor AudioCapture: AudioSource {
    enum CaptureError: Error {
        case noInputDevice
        case notCapturing
    }

    private struct Graph {
        let engine: AVAudioEngine
        let format: AVAudioFormat
    }

    /// Mic level 0...1, about ten updates a second while recording, for the indicator.
    nonisolated let levels: AsyncStream<Float>
    private let levelContinuation: AsyncStream<Float>.Continuation
    private let ring = SampleRing()
    private var graph: Graph?
    private var writer: CaptureWriter?
    /// In the Undo window after Esc: the engine is stopped, the writer and its file stay open.
    private var isPaused = false
    private var configurationObserver: (any NSObjectProtocol)?
    /// Route changes arrive from two sources and can overlap; one rebuild runs at a time and a
    /// request during it causes one more pass.
    private var isRebuilding = false
    private var isRebuildRequested = false
    private let preferences: MicrophonePreferences
    /// The mic the graph records from; a device change rebuilds only when this changes. Kept under a
    /// lock too, so the menu and Settings can read it without waiting on the actor.
    private var currentInput: AudioDevice? {
        didSet { inputInUseValue.withLock { $0 = currentInput } }
    }
    private nonisolated let inputInUseValue = Mutex<AudioDevice?>(nil)
    private var isListeningToDevices = false
    /// A device burst (connect, then default change) is handled once: one check queued, not one per event.
    private var isDeviceCheckQueued = false
    /// A mic change that arrived during a capture; it applies when the capture ends.
    private var isInputChangeDeferred = false

    init(preferences: MicrophonePreferences) {
        self.preferences = preferences
        (levels, levelContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// The mic kotoba records from (or will, at the next dictation), for the menu and Settings.
    nonisolated var inputInUse: AudioDevice? {
        inputInUseValue.withLock { $0 }
    }

    /// Builds the graph and prepares it, so key-down only starts it. Call after microphone access is
    /// granted. A graph that a chord press built while the prompt waited is kept.
    func prepare() {
        if graph == nil {
            graph = makeGraph()
        }
        guard !isListeningToDevices else { return }
        isListeningToDevices = true
        AudioDevices.observeChanges { [weak self] in
            Task { await self?.devicesChanged() }
        }
    }

    private func devicesChanged() async {
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
        if graph == nil {
            graph = makeGraph()
        }
        guard let graph else { throw CaptureError.noInputDevice }
        // The engine starts first; audio waits in the ring while the file and converter are made
        // (about 0.2 ms, or about 11 ms the first time in a process).
        let readPosition = ring.beginCapture()
        try graph.engine.start()
        let (events, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        let writer: CaptureWriter
        do {
            writer = try CaptureWriter(
                file: file,
                sampleRate: graph.format.sampleRate,
                ring: ring,
                readingFrom: readPosition,
                events: continuation,
                levels: levelContinuation
            )
        } catch {
            stopEngine()
            throw error
        }
        writer.start()
        self.writer = writer
        return events
    }

    func endCapture() async throws -> RecordedAudio {
        guard let writer else { throw CaptureError.notCapturing }
        self.writer = nil
        // Keep the hardware cycle that holds the stop moment, so the last word is not cut.
        let audio = await writer.stop(after: mach_absolute_time())
        // engine.stop() and prepare() take about 15 + 8 ms; they run after the audio goes to upload.
        Task {
            self.stopEngineIfIdle()
            await self.applyDeferredInputChange()
        }
        return audio
    }

    func pauseCapture() async {
        guard writer != nil else { return }
        isPaused = true
        stopEngine()
    }

    func resumeCapture() async throws {
        guard writer != nil, let graph else { throw CaptureError.notCapturing }
        try graph.engine.start()
        isPaused = false
    }

    func cancelCapture() async -> RecordedAudio? {
        guard let writer else { return nil }
        self.writer = nil
        isPaused = false
        stopEngine()
        let audio = await writer.stopNow()
        await applyDeferredInputChange()
        return audio
    }

    func discardCapture() async {
        guard let audio = await cancelCapture() else { return }
        do {
            try FileManager.default.removeItem(at: audio.file)
        } catch {
            Log.audio.error("Cannot delete discarded audio: \(error)")
        }
    }

    /// A capture that began in the meantime keeps the engine running.
    private func stopEngineIfIdle() {
        guard writer == nil else { return }
        stopEngine()
    }

    private func stopEngine() {
        graph?.engine.stop()
        graph?.engine.prepare()
        levelContinuation.yield(0)
    }

    /// A new engine with the input chosen by `InputDevicePolicy` and a sink node feeding the ring.
    private func makeGraph() -> Graph? {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        selectPreferredDevice(for: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        let sink = AVAudioSinkNode(receiverBlock: Self.sinkBlock(feeding: ring, sampleRate: format.sampleRate))
        engine.attach(sink)
        engine.connect(input, to: sink, format: format)
        engine.prepare()
        observeConfigurationChanges(of: engine)
        return Graph(engine: engine, format: format)
    }

    /// Points the input at the preferred mic; if that fails, the input follows the system default.
    private func selectPreferredDevice(for input: AVAudioInputNode) {
        currentInput = preferences.preferredInput(among: AudioDevices.all())
        guard let choice = currentInput else { return }
        do {
            try input.auAudioUnit.setDeviceID(AUAudioObjectID(choice.id))
            Log.audio.info("Recording from \(choice.name, privacy: .public)")
        } catch {
            Log.audio.error("Cannot switch to \(choice.name, privacy: .public), using the default input: \(error)")
            currentInput = AudioDevices.defaultInput()
        }
    }

    /// Runs on the real-time IO thread: copy, publish, signal. No allocation, no lock, no log, no
    /// Objective-C call. Built outside the actor, so the closure carries no actor isolation to assert.
    private nonisolated static func sinkBlock(
        feeding ring: SampleRing,
        sampleRate: Double
    ) -> AVAudioSinkNodeReceiverBlock {
        let ticksPerFrame = Double(AVAudioTime.hostTime(forSeconds: 1)) / sampleRate
        return { timestamp, frames, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
            guard let samples = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let start = timestamp.pointee.mHostTime
            let end = start + UInt64(Double(frames) * ticksPerFrame)
            ring.push(samples, count: Int(frames), startHostTime: start, endHostTime: end)
            return noErr
        }
    }

    /// A route change stops the engine and can change its format. A new engine is the reliable
    /// fix; a capture in progress continues into the same file.
    private func observeConfigurationChanges(of engine: AVAudioEngine) {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { await self?.requestRebuild(reason: "audio route changed") }
        }
    }

    private func requestRebuild(reason: String) async {
        Log.audio.info("Rebuilding the audio engine: \(reason, privacy: .public)")
        isRebuildRequested = true
        guard !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        while isRebuildRequested {
            isRebuildRequested = false
            await rebuildGraph()
        }
    }

    private func rebuildGraph() async {
        graph?.engine.stop()
        let rebuilt = makeGraph()
        graph = rebuilt
        guard let writer, let rebuilt else { return }
        await writer.switchSampleRate(to: rebuilt.format.sampleRate)
        // The capture may have ended, paused or been rebuilt again during the await. Start the
        // engine only for the same capture, still live, on the graph built here.
        guard self.writer === writer, graph?.engine === rebuilt.engine, !isPaused, !isRebuildRequested else {
            return
        }
        do {
            try rebuilt.engine.start()
        } catch {
            Log.audio.error("Capture could not continue after the route change: \(error)")
        }
    }
}
