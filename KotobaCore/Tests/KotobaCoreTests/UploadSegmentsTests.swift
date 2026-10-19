import Foundation
import Testing

@testable import KotobaCore

/// The upload copy cut into segments as the capture writes it (`UploadSegments`, docs/research/latency-pass-2.md
/// section 7, rule s15p0.4): where a pause cuts, which writer each chunk goes to, and which files stay. A fake writer
/// keeps the chunks it got; chunks are 100 ms at 16 kHz, as the capture writer converts them.
struct UploadSegmentsTests {
    final class FakeWriter: UploadSegmentWriter {
        let file: URL
        private(set) var chunks: [Int] = []
        private(set) var isClosed = false

        init(file: URL) {
            self.file = file
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }

        func write(_ chunk: Int) throws {
            chunks.append(chunk)
        }

        func close() throws -> URL {
            isClosed = true
            return file
        }
    }

    /// The segments under test, the writers they opened, and the chunks written so far.
    final class Copy {
        let folder = URL.temporaryDirectory.appending(path: "kotoba-segments-test-\(UUID().uuidString)")
        var first: URL { folder.appending(path: "copy.ogg") }
        private(set) var writers: [FakeWriter] = []
        private(set) var chunk = 0
        lazy var segments = UploadSegments(first: first, sampleRate: 16_000) { [weak self] file in
            let writer = FakeWriter(file: file)
            self?.writers.append(writer)
            return writer
        }

        private static let loud = (0..<1_600).map { Int16(8_000 * sin(Double($0) * 0.3)) }
        private static let quiet = [Int16](repeating: 3, count: 1_600)

        /// Writes `seconds` of sound or silence, and returns the segments that closed.
        @discardableResult
        func write(loud: Bool, seconds: Double) throws -> [UploadSegment] {
            try write(loud ? Self.loud : Self.quiet, seconds: seconds)
        }

        func write(_ samples: [Int16], seconds: Double) throws -> [UploadSegment] {
            var closed: [UploadSegment] = []
            for _ in 0..<Int((seconds * 10).rounded()) {
                chunk += 1
                let segment = try samples.withUnsafeBufferPointer {
                    try segments.write(chunk, samples: $0, endingAt: Int64(chunk) * 1_600)
                }
                closed += segment.map { [$0] } ?? []
            }
            return closed
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func aPauseOf04SecondsAfter15SecondsClosesTheFirstSegment() throws {
        let copy = Copy()

        #expect(try copy.write(loud: true, seconds: 15).isEmpty)
        let closed = try copy.write(loud: false, seconds: 0.5)
        try copy.write(loud: true, seconds: 3)
        let tail = try #require(try copy.segments.close())

        let segment = try #require(closed.first)
        #expect(closed.count == 1)
        #expect(segment.index == 0)
        #expect(segment.file == copy.first)
        #expect(segment.start == .zero)
        #expect(segment.duration == .milliseconds(15_400))
        #expect(copy.writers.map(\.file.lastPathComponent) == ["copy.ogg", "copy-1.ogg"])
        // Chunks 153 and 154 (15.2-15.4 s, silence) went to both.
        #expect(copy.writers[0].chunks == Array(1...154))
        #expect(copy.writers[1].chunks == Array(153...185))
        #expect(tail.file.lastPathComponent == "copy-1.ogg")
        #expect(tail.start == .milliseconds(15_200))
        #expect(copy.writers.allSatisfy { $0.isClosed })
    }

    @Test func noCutBefore15Seconds() throws {
        let copy = Copy()

        try copy.write(loud: true, seconds: 14)
        let closed = try copy.write(loud: false, seconds: 0.9)

        #expect(closed.isEmpty)
        #expect(copy.writers.count == 1)
    }

    /// The pause must start 15 s or more after the last cut, not only reach past it.
    @Test func aPauseThatStartsBefore15SecondsDoesNotCut() throws {
        let copy = Copy()

        try copy.write(loud: true, seconds: 14.9)
        let closed = try copy.write(loud: false, seconds: 1)

        #expect(closed.isEmpty)
    }

    @Test func speechBeforeTheEndOfThePauseDropsTheNextSegmentsFile() throws {
        let copy = Copy()

        try copy.write(loud: true, seconds: 15)
        try copy.write(loud: false, seconds: 0.3)
        try copy.write(loud: true, seconds: 1)
        let tail = try #require(try copy.segments.close())

        #expect(copy.writers.count == 2)
        #expect(!FileManager.default.fileExists(atPath: copy.writers[1].file.path))
        #expect(tail.file == copy.first)
        #expect(tail.start == .zero)
        #expect(copy.writers[0].chunks.count == 163)
    }

    /// The next segment counts its 15 s from the cut, 0.2 s into the pause: a pause 14.8 s after it does not cut.
    @Test func theNextCutComes15SecondsAfterTheLastOne() throws {
        let copy = Copy()
        try copy.write(loud: true, seconds: 15)
        try copy.write(loud: false, seconds: 0.5)
        try copy.write(loud: true, seconds: 14.5)
        #expect(try copy.write(loud: false, seconds: 0.5).isEmpty)

        try copy.write(loud: true, seconds: 1)
        let closed = try copy.write(loud: false, seconds: 0.5)

        #expect(closed.map(\.index) == [1])
        #expect(closed.first?.start == .milliseconds(15_200))
        #expect(closed.first?.duration == .milliseconds(16_700))
    }

    @Test func aLongPauseCutsOnce() throws {
        let copy = Copy()
        try copy.write(loud: true, seconds: 15)

        let closed = try copy.write(loud: false, seconds: 5)

        #expect(closed.count == 1)
        #expect(copy.writers.count == 2)
    }

    /// Quiet speech is not a pause: the threshold is -40 dBFS RMS per 10 ms.
    @Test func soundAboveMinus40DBFSIsNoPause() throws {
        let copy = Copy()
        try copy.write(loud: true, seconds: 15)
        let quiet = (0..<1_600).map { Int16(600 * sin(Double($0) * 0.3)) }  // About -38 dBFS RMS.

        let closed = try copy.write(quiet, seconds: 1)

        #expect(closed.isEmpty)
        #expect(copy.writers.count == 1)
    }

    @Test func aStopDuringAPauseDropsTheNextSegment() throws {
        let copy = Copy()
        try copy.write(loud: true, seconds: 15)
        try copy.write(loud: false, seconds: 0.3)

        let tail = try #require(try copy.segments.close())

        #expect(tail.file == copy.first)
        #expect(!FileManager.default.fileExists(atPath: copy.writers[1].file.path))
    }

    /// A failure drops the open segments' files; a closed one belongs to its request and stays.
    @Test func aDropDeletesTheOpenSegmentsOnly() throws {
        let copy = Copy()
        try copy.write(loud: true, seconds: 15)
        let closed = try copy.write(loud: false, seconds: 0.5)

        copy.segments.drop()

        #expect(closed.count == 1)
        #expect(FileManager.default.fileExists(atPath: copy.first.path))
        #expect(!FileManager.default.fileExists(atPath: copy.writers[1].file.path))
        #expect(try copy.segments.close() == nil)
    }

    @Test func noChunkNoCopy() throws {
        let copy = Copy()

        #expect(try copy.segments.close() == nil)
    }
}
