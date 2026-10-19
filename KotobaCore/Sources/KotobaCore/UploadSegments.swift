import Foundation

/// What writes one segment of a recording's upload copy (the app's `OpusUploadWriter`; a fake in tests).
public protocol UploadSegmentWriter: AnyObject {
    /// One chunk of the capture, as the writer encodes it.
    associatedtype Chunk
    func write(_ chunk: Chunk) throws
    /// Writes the end and returns the file.
    func close() throws -> URL
}

/// The upload copy of a live recording, cut into segments at pauses as the capture writes it, on the capture writer's
/// thread, so the stop waits only for the last one (docs/research/latency-pass-2.md section 7, rule s15p0.4: WER 8.00%
/// against 7.96% whole on 56 clips, within the noise). A segment ends at the first pause of 0.4 s (every 10 ms frame
/// under -40 dBFS RMS) that starts 15 s or more after the last cut. The next segment opens 0.2 s into the pause, and
/// each chunk goes to both until the pause reaches 0.4 s (the earlier one closes) or sound comes first (the next one
/// goes); so each side of a cut keeps silence, and no word is in two segments. A closed segment comes back from `write`
/// for the capture to report (`CaptureEvent.segment`); its file then belongs to its request.
///
/// The cutter decides at the end of each chunk the writer converts (100 ms), as a cut must fall between chunks: a pause
/// of 0.4-0.5 s that ends inside a chunk may not cut; one of 0.5 s or more always does.
///
/// The bench rule also keeps the last 2 s before the stop uncut. A live capture cannot know the stop is near, so a
/// cut just before it leaves a short copy after it, which the stop sends as usual.
public struct UploadSegments<Writer: UploadSegmentWriter> {
    private struct Open {
        let writer: Writer
        let file: URL
        /// Where it starts in the recording, in frames.
        let start: Int64
    }

    private let first: URL
    private let sampleRate: Double
    private let makeWriter: (URL) throws -> Writer
    private var current: Open?
    private var next: Open?
    /// The current segment's, from 0.
    private var index = 0
    private var cutter: PauseCutter

    /// `first` names the first segment; later ones add `-1`, `-2`… to its name. `makeWriter` opens a segment's file. The
    /// first segment's writer opens at the first chunk, so the key-down does not wait for it.
    public init(first: URL, sampleRate: Double, makeWriter: @escaping (URL) throws -> Writer) {
        self.first = first
        self.sampleRate = sampleRate
        self.makeWriter = makeWriter
        cutter = PauseCutter(sampleRate: sampleRate)
    }

    /// Writes `chunk`, whose `samples` (16-bit mono) end the recording's first `frames` frames. Returns the segment
    /// that a pause closed with this chunk, or nil. A throw leaves the copy unusable: `drop` it.
    public mutating func write(
        _ chunk: Writer.Chunk, samples: UnsafeBufferPointer<Int16>, endingAt frames: Int64
    ) throws -> UploadSegment? {
        if current == nil {
            try FileManager.default.createDirectory(
                at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
            current = Open(writer: try makeWriter(first), file: first, start: 0)
        }
        guard let open = current else { return nil }
        try open.writer.write(chunk)
        try next?.writer.write(chunk)
        switch cutter.cut(after: samples) {
        case .openNext:
            let file = first.deletingLastPathComponent().appending(
                path: "\(first.deletingPathExtension().lastPathComponent)-\(index + 1).\(first.pathExtension)")
            next = Open(writer: try makeWriter(file), file: file, start: frames)
            return nil
        case .closePrevious:
            guard let following = next else { return nil }
            let segment = UploadSegment(
                index: index, file: try open.writer.close(), start: duration(of: open.start),
                duration: duration(of: frames - open.start))
            (current, next) = (following, nil)
            index += 1
            return segment
        case .dropNext:
            next.map(Self.remove)
            next = nil
            return nil
        case nil:
            return nil
        }
    }

    /// The copy after the last cut, and where it starts; nil when no chunk came. A next segment still open (a pause
    /// that ran into the stop) is dropped: the current one holds its audio too.
    public mutating func close() throws -> (file: URL, start: Duration)? {
        next.map(Self.remove)
        next = nil
        guard let open = current else { return nil }
        current = nil
        return (try open.writer.close(), duration(of: open.start))
    }

    /// Deletes the open segments' files after a failure. The segments already closed belong to their requests.
    public mutating func drop() {
        // No segment open yet: the first writer's init may have made its file before it failed.
        if current == nil, index == 0 { try? FileManager.default.removeItem(at: first) }
        [current, next].compactMap(\.self).forEach(Self.remove)
        (current, next) = (nil, nil)
    }

    /// Whole nanoseconds, so a segment's length is exact for the latency log and the tests.
    private func duration(of frames: Int64) -> Duration {
        .nanoseconds(frames * 1_000_000_000 / Int64(sampleRate))
    }

    private static func remove(_ open: Open) {
        _ = try? open.writer.close()
        try? FileManager.default.removeItem(at: open.file)
    }
}

/// Where the rule cuts, from the samples alone: RMS per 10 ms frame, counted across chunks. Pure arithmetic over the
/// chunk the capture already converted, no allocation.
private struct PauseCutter {
    enum Action {
        /// 0.2 s into a pause that starts 15 s or more after the last cut: the next segment starts here.
        case openNext
        /// The pause reached 0.4 s: the earlier segment is complete.
        case closePrevious
        /// Sound came back before 0.4 s: the next segment goes, and the earlier one goes on.
        case dropNext
    }

    /// -40 dBFS RMS, the `silencedetect` threshold of the bench.
    private static let silentRMS = 32_768 * 0.01
    private static let frameSeconds = 0.01
    private static let minSegment = Duration.seconds(15)
    private static let opensAfter = Duration.milliseconds(200)
    private static let minPause = Duration.milliseconds(400)

    private let frameLength: Int
    private var frameFill = 0
    private var frameSquares = 0.0
    /// Silent frames in a row, up to now.
    private var silentFrames = 0
    /// Frames since the current segment starts.
    private var segmentFrames = 0
    /// Frames since the next segment opened, while it is open.
    private var nextFrames: Int?
    private var isSoundSinceOpen = false

    init(sampleRate: Double) {
        frameLength = Int(sampleRate * Self.frameSeconds)
    }

    private static func frames(_ duration: Duration) -> Int {
        Int((duration / .seconds(frameSeconds)).rounded())
    }

    /// The action after the chunk `samples` (16-bit mono at the init's rate), or nil.
    mutating func cut(after samples: UnsafeBufferPointer<Int16>) -> Action? {
        for sample in samples {
            frameSquares += Double(sample) * Double(sample)
            frameFill += 1
            if frameFill == frameLength { endFrame() }
        }
        if let next = nextFrames {
            if isSoundSinceOpen {
                nextFrames = nil
                return .dropNext
            }
            guard silentFrames >= Self.frames(Self.minPause) else { return nil }
            segmentFrames = next
            nextFrames = nil
            return .closePrevious
        }
        let pauseStart = segmentFrames - silentFrames
        guard pauseStart >= Self.frames(Self.minSegment), silentFrames >= Self.frames(Self.opensAfter) else {
            return nil
        }
        nextFrames = 0
        isSoundSinceOpen = false
        return .openNext
    }

    private mutating func endFrame() {
        let isSilent = (frameSquares / Double(frameLength)).squareRoot() < Self.silentRMS
        frameSquares = 0
        frameFill = 0
        segmentFrames += 1
        nextFrames = nextFrames.map { $0 + 1 }
        if isSilent {
            silentFrames += 1
        } else {
            silentFrames = 0
            if nextFrames != nil { isSoundSinceOpen = true }
        }
    }
}
