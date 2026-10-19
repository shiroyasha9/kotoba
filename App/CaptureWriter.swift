import AVFAudio
import Accelerate
import Foundation
import KotobaCore
import Synchronization
import os

/// Drains the ring on its own thread, converts to 16 kHz mono Int16 and writes FLAC.
/// The file, converter and read position are used only on that thread; `control` is the only
/// state shared with the actor.
final class CaptureWriter: CaptureRecorder, @unchecked Sendable {
    private struct Control {
        var stopHostTime: UInt64?
        var stopsNow = false
        var pendingSampleRate: Double?
        var rateSwitched: CheckedContinuation<Void, Never>?
        var finished: CheckedContinuation<RecordedAudio, Never>?
        /// Ends a stop that waits for audio from a vanished device; cancelled when the file closes.
        var fallback: Task<Void, Never>?
        /// The file closed and the thread ended: a rate switch that comes now has nothing to wait for.
        var isClosed = false
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
    /// The first chunk lost, and why: the file did not take it or the converter failed. Logged once; the stop
    /// reports it (`RecordedAudio.loss`).
    private var loss: AudioLoss?
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

    func start() {
        // Signals left from the last capture (or pushes with no writer) would wake this one early.
        while ring.wake.wait(timeout: .now()) == .success {}
        let thread = Thread { [self] in run() }
        thread.name = "kotoba.capture-writer"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Returns once the audio up to now is written and the file is closed. A device that stops
    /// delivering ends the wait after 300 ms. The moment is read on the caller's executor
    /// (`CaptureRecorder.stop`).
    nonisolated(nonsending) func stop() async -> RecordedAudio {
        let hostTime = mach_absolute_time()
        return await withCheckedContinuation { continuation in
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

    /// The mic input was rebuilt at a new sample rate. Returns once audio at the old rate is written, or at once when
    /// the capture has ended: a cancel can close the file while the rebuild waits here (`AudioCapture.rebuildInput`).
    func switchSampleRate(to sampleRate: Double) async {
        await withCheckedContinuation { continuation in
            let isClosed = control.withLock { control in
                guard !control.isClosed else { return true }
                control.pendingSampleRate = sampleRate
                control.rateSwitched = continuation
                return false
            }
            if isClosed {
                continuation.resume()
            } else {
                ring.wake.signal()
            }
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
        guard status != .error else {
            lostAudio(.other, "The converter dropped a chunk", error)
            return
        }
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
            // AVAudioFile reports a full disk as code -40 (`writErr`) with no underlying error; the failed write leaves
            // ENOSPC in errno (probe on a full 5 MB disk image, 2026-10-17). Read first, before another call sets it.
            let code = errno
            lostAudio(code == ENOSPC ? .diskFull : .other, "FLAC write failed (errno \(code))", error)
        }
    }

    /// Once per capture: a full disk fails every chunk after the first failure, ten a second.
    private func lostAudio(_ cause: AudioLoss, _ what: String, _ error: (any Error)?) {
        guard loss == nil else { return }
        loss = cause
        Log.audio.error("\(what, privacy: .public): \(String(describing: error))")
    }

    private func switchConversion(to sampleRate: Double) {
        flushConverter()
        do {
            conversion = try Self.makeConversion(sampleRate: sampleRate)
        } catch {
            Log.audio.error("No converter for \(sampleRate) Hz")
        }
    }

    /// A rate switch that came after this iteration's check is resumed here; without it the rebuild that asked would
    /// wait for ever and no later route change would rebuild the input.
    private func close() -> RecordedAudio {
        let (fallback, rateSwitched) = control.withLock { control in
            control.isClosed = true
            defer { (control.pendingSampleRate, control.rateSwitched) = (nil, nil) }
            return (control.fallback, control.rateSwitched)
        }
        fallback?.cancel()
        drain()
        flushConverter()
        file.close()
        events.finish()
        rateSwitched?.resume()
        return RecordedAudio(
            file: fileURL, duration: Self.duration(ofFrames: framesWritten), loss: loss)
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
}

// MARK: - File, conversion and time

extension CaptureWriter {
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
