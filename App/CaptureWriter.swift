import AVFAudio
import Accelerate
import Foundation
import KotobaCore
import Synchronization
import os

/// Single-producer, single-consumer ring of mono samples. The IO thread pushes; the writer thread
/// reads. `written` publishes frames with release/acquire ordering, so neither side locks.
final class SampleRing: Sendable {
    /// About 1.4 s at 48 kHz; the writer drains it every hardware cycle (about 10 ms).
    static let capacity = 1 << 16

    /// Total frames pushed since launch; the writer keeps its own read position.
    let written = Atomic<Int>(0)
    /// Host time of the first sample pushed after `beginCapture`, 0 until then.
    let firstHostTime = Atomic<UInt64>(0)
    /// Host time just after the last pushed sample.
    let lastEndHostTime = Atomic<UInt64>(0)
    /// Signalled once per push, and by stop requests.
    let wake = DispatchSemaphore(value: 0)
    // Only the IO thread writes slots, only past `written`; the writer reads only before it.
    nonisolated(unsafe) private let storage: UnsafeMutablePointer<Float>

    /// Not zero-filled: a slot is read only after `push` wrote it, and untouched pages stay out of
    /// the footprint (2 MiB less idle than the zero-filled 1 << 19 ring, measured with `footprint`).
    init() {
        storage = .allocate(capacity: Self.capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Clears the first-sample time and returns the position a new writer starts reading from.
    func beginCapture() -> Int {
        firstHostTime.store(0, ordering: .relaxed)
        return written.load(ordering: .acquiring)
    }

    func push(_ samples: UnsafePointer<Float>, count: Int, startHostTime: UInt64, endHostTime: UInt64) {
        let start = written.load(ordering: .relaxed)
        let slot = start & (Self.capacity - 1)
        let head = min(count, Self.capacity - slot)
        (storage + slot).update(from: samples, count: head)
        storage.update(from: samples + head, count: count - head)
        _ = firstHostTime.compareExchange(expected: 0, desired: startHostTime, ordering: .relaxed)
        lastEndHostTime.store(endHostTime, ordering: .relaxed)
        written.store(start + count, ordering: .releasing)
        wake.signal()
    }

    func copy(from position: Int, count: Int, into destination: UnsafeMutablePointer<Float>) {
        let slot = position & (Self.capacity - 1)
        let head = min(count, Self.capacity - slot)
        destination.update(from: storage + slot, count: head)
        (destination + head).update(from: storage, count: count - head)
    }
}

/// Drains the ring on its own thread, converts to 16 kHz mono Int16 and writes FLAC.
/// The file, converter and read position are used only on that thread; `control` is the only
/// state shared with the actor.
final class CaptureWriter: @unchecked Sendable {
    private struct Control {
        var stopHostTime: UInt64?
        var stopsNow = false
        var pendingSampleRate: Double?
        var hasReportedInputLoss = false
        var rateSwitched: CheckedContinuation<Void, Never>?
        var finished: CheckedContinuation<RecordedAudio, Never>?
        /// Ends a stop that waits for audio from a vanished device; cancelled when the file closes.
        var fallback: Task<Void, Never>?
    }

    private static let chunkFrames = 4_800
    static let outputFormat: AVAudioFormat = {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)
        else { preconditionFailure("16 kHz mono Int16 is a valid format") }
        return format
    }()

    private let fileURL: URL
    private let file: AVAudioFile
    private let ring: SampleRing
    private let events: AsyncStream<CaptureEvent>.Continuation
    private let levels: AsyncStream<Float>.Continuation
    private let control = Mutex(Control())
    /// The input chunk, the reused output buffer (one full chunk after resampling) and the
    /// converter between them; replaced when the input sample rate changes.
    private struct Conversion {
        let input: AVAudioPCMBuffer
        let output: AVAudioPCMBuffer
        let converter: AVAudioConverter
    }

    private var conversion: Conversion
    private var readPosition: Int
    private var framesWritten: AVAudioFramePosition = 0
    private var hasReportedFirstBuffer = false
    private var levelSum: Float = 0
    private var levelFrames = 0

    init(
        file url: URL,
        sampleRate: Double,
        ring: SampleRing,
        readingFrom readPosition: Int,
        events: AsyncStream<CaptureEvent>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fileURL = url
        file = try Self.makeFile(at: url)
        conversion = try Self.makeConversion(sampleRate: sampleRate)
        self.ring = ring
        self.events = events
        self.levels = levels
        self.readPosition = readPosition
    }

    /// The FLAC file of a recording, in `outputFormat`. Orphan recovery writes the same file (`OrphanAudioRecovery`).
    static func makeFile(at url: URL) throws -> AVAudioFile {
        try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: outputFormat.sampleRate,
                AVNumberOfChannelsKey: outputFormat.channelCount,
            ],
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
    }

    static func duration(ofFrames frames: AVAudioFramePosition) -> Duration {
        .seconds(Double(frames) / outputFormat.sampleRate)
    }

    func start() {
        // Signals left from the last capture (or pushes with no writer) would wake this one early.
        while ring.wake.wait(timeout: .now()) == .success {}
        let thread = Thread { [self] in run() }
        thread.name = "kotoba.capture-writer"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Returns once the audio up to `hostTime` is written and the file is closed. A device that
    /// stops delivering ends the wait after 300 ms.
    func stop(after hostTime: UInt64) async -> RecordedAudio {
        await withCheckedContinuation { continuation in
            control.withLock { control in
                control.stopHostTime = hostTime
                control.finished = continuation
            }
            // A guard against a vanished device, not a pacing delay.
            let fallback = Task {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                } catch {
                    return
                }
                self.control.withLock { $0.stopsNow = true }
                self.ring.wake.signal()
            }
            control.withLock { $0.fallback = fallback }
            ring.wake.signal()
        }
    }

    /// Writes what has arrived and closes the file.
    func stopNow() async -> RecordedAudio {
        await withCheckedContinuation { continuation in
            control.withLock { control in
                control.stopsNow = true
                control.finished = continuation
            }
            ring.wake.signal()
        }
    }

    /// No mic is open during the capture; the events report it once (`CaptureEvent.inputLost`).
    func inputLost() {
        let isFirst = control.withLock { control in
            defer { control.hasReportedInputLoss = true }
            return !control.hasReportedInputLoss
        }
        if isFirst {
            events.yield(.inputLost)
        }
    }

    /// The mic input was rebuilt at a new sample rate. Returns once audio at the old rate is written.
    func switchSampleRate(to sampleRate: Double) async {
        await withCheckedContinuation { continuation in
            control.withLock { control in
                control.pendingSampleRate = sampleRate
                control.rateSwitched = continuation
                // A new mic is open: its loss is reported again.
                control.hasReportedInputLoss = false
            }
            ring.wake.signal()
        }
    }

    private func run() {
        while true {
            ring.wake.wait()
            // The ring signals every hardware cycle (about 94 a second); convert and write once a
            // whole chunk waits, or at once when a stop, rate switch or close needs everything written.
            let mustDrain = control.withLock { $0.stopHostTime != nil || $0.stopsNow || $0.pendingSampleRate != nil }
            reportFirstBuffer()
            if mustDrain || ring.written.load(ordering: .acquiring) - readPosition >= Self.chunkFrames {
                drain()
            }
            let (rate, rateSwitched) = control.withLock { control in
                defer { (control.pendingSampleRate, control.rateSwitched) = (nil, nil) }
                return (control.pendingSampleRate, control.rateSwitched)
            }
            if let rate {
                switchConversion(to: rate)
                rateSwitched?.resume()
            }
            let finished: CheckedContinuation<RecordedAudio, Never>? = control.withLock { control in
                let reachedStop = control.stopHostTime.map { ring.lastEndHostTime.load(ordering: .relaxed) >= $0 }
                guard control.stopsNow || reachedStop == true, let finished = control.finished else { return nil }
                control.finished = nil
                return finished
            }
            if let finished {
                finished.resume(returning: close())
                return
            }
        }
    }

    private func drain() {
        reportFirstBuffer()
        let available = ring.written.load(ordering: .acquiring) - readPosition
        if available > SampleRing.capacity {
            Log.audio.error("Capture ring overflowed")
            readPosition += available - SampleRing.capacity
        }
        while readPosition < ring.written.load(ordering: .acquiring) {
            let count = min(Self.chunkFrames, ring.written.load(ordering: .acquiring) - readPosition)
            guard let samples = conversion.input.floatChannelData?[0] else { return }
            ring.copy(from: readPosition, count: count, into: samples)
            conversion.input.frameLength = AVAudioFrameCount(count)
            readPosition += count
            measureLevel(samples, count: count)
            convertAndWrite(conversion.input)
        }
    }

    private func reportFirstBuffer() {
        guard !hasReportedFirstBuffer else { return }
        let hostTime = ring.firstHostTime.load(ordering: .relaxed)
        guard hostTime != 0 else { return }
        hasReportedFirstBuffer = true
        events.yield(.firstBuffer(at: Self.instant(ofHostTime: hostTime)))
    }

    private func convertAndWrite(_ buffer: AVAudioPCMBuffer) {
        var isFed = false
        var error: NSError?
        let status = conversion.converter.convert(to: conversion.output, error: &error) { _, inputStatus in
            if isFed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            isFed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error else { return }
        write(conversion.output)
    }

    /// Drains the resampler's last few frames.
    private func flushConverter() {
        var error: NSError?
        _ = conversion.converter.convert(to: conversion.output, error: &error) { _, inputStatus in
            inputStatus.pointee = .endOfStream
            return nil
        }
        write(conversion.output)
    }

    private func write(_ output: AVAudioPCMBuffer) {
        guard output.frameLength > 0 else { return }
        do {
            try file.write(from: output)
            framesWritten += AVAudioFramePosition(output.frameLength)
        } catch {
            Log.audio.error("FLAC write failed: \(error)")
        }
    }

    private func switchConversion(to sampleRate: Double) {
        flushConverter()
        do {
            conversion = try Self.makeConversion(sampleRate: sampleRate)
        } catch {
            Log.audio.error("No converter for \(sampleRate) Hz")
        }
    }

    private func close() -> RecordedAudio {
        control.withLock { $0.fallback }?.cancel()
        drain()
        flushConverter()
        file.close()
        events.finish()
        return RecordedAudio(file: fileURL, duration: Self.duration(ofFrames: framesWritten))
    }

    /// RMS over 4,800 input frames (100 ms at 48 kHz), scaled so speech fills most of the range. The
    /// capture events carry it too, for the no-sound warning (`NoSoundPolicy`). Two streams on purpose:
    /// the indicator meter reads `levels` without a hop through the pipeline actor.
    private func measureLevel(_ samples: UnsafePointer<Float>, count: Int) {
        levelSum += vDSP.sumOfSquares(UnsafeBufferPointer(start: samples, count: count))
        levelFrames += count
        guard levelFrames >= Self.chunkFrames else { return }
        let level = min(1, (levelSum / Float(levelFrames)).squareRoot() * 8)
        levels.yield(level)
        events.yield(.level(level))
        levelSum = 0
        levelFrames = 0
    }

    private static func makeConversion(sampleRate: Double) throws -> Conversion {
        let resampled = (Double(chunkFrames) * outputFormat.sampleRate / sampleRate).rounded(.up)
        let outputFrames = AVAudioFrameCount(resampled) + 64
        guard
            let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let input = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(chunkFrames)),
            let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames),
            let converter = AVAudioConverter(from: mono, to: outputFormat)
        else { throw AudioCapture.CaptureError.noInputDevice }
        return Conversion(input: input, output: output, converter: converter)
    }

    /// Host time (mach absolute) to the pipeline's clock.
    private static func instant(ofHostTime hostTime: UInt64) -> ContinuousClock.Instant {
        let now = mach_absolute_time()
        let age = now >= hostTime ? AVAudioTime.seconds(forHostTime: now - hostTime) : 0
        return .now - .seconds(age)
    }
}
