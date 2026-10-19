import Foundation
import Testing

@testable import KotobaCore

/// The recorder's Opus upload copy (`RecordedAudio.upload`) on disk: only the last recording's copy stays, and a
/// discarded recording (a cancel, an Esc that ends in a discard, a mic test) leaves none. Copies are real files the
/// fake recorder writes at the close.
struct AudioCaptureUploadCopyTests {
    private let folder = URL.temporaryDirectory.appending(path: "kotoba-upload-copy-test-\(UUID().uuidString)")

    private func recording(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name).flac")
        FileManager.default.createFile(atPath: file.path, contents: Data("fLaC".utf8))
        return file
    }

    private func exists(_ file: URL?) -> Bool {
        file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    @Test func theNextRecordingDeletesTheLastOnesCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware)
        defer { try? FileManager.default.removeItem(at: folder) }

        _ = try await capture.beginCapture(into: try recording("first"))
        let first = try #require(await capture.endCapture()?.upload)
        #expect(exists(first))
        _ = try await capture.beginCapture(into: try recording("second"))
        let second = try #require(await capture.endCapture()?.upload)

        #expect(await eventually { !exists(first) })
        #expect(exists(second))
    }

    @Test func aDiscardedRecordingLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try recording("discarded")

        _ = try await capture.beginCapture(into: file)
        #expect(await capture.discardCapture())

        #expect(!exists(file))
        #expect(!exists(try #require(hardware.recorders.first?.upload)))
    }

    /// Esc keeps the file for the Undo window; when the window ends the pipeline discards it.
    @Test func aCancelledRecordingThatIsDiscardedLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await capture.beginCapture(into: try recording("cancelled"))
        let audio = try #require(await capture.cancelCapture())
        #expect(exists(audio.upload))

        #expect(await capture.discard(audio))

        #expect(!exists(audio.file))
        #expect(!exists(audio.upload))
    }

    @Test func theMicTestLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let clock = ManualClock()
        let capture = AudioCapture(hardware: hardware, clock: clock)
        guard case .running(let levels) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not start")
            return
        }
        #expect(await eventually { !clock.deadlines.isEmpty })

        clock.advance(by: .seconds(5))

        #expect(await finished(levels) != nil)
        let copy = try #require(hardware.recorders.first?.upload)
        #expect(await eventually { !exists(copy) })
    }
}
