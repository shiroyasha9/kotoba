import Foundation
import Testing

@testable import KotobaCore

/// The recorder's Opus upload copy (`RecordedAudio.upload`) on disk: it goes in the capture's upload folder, the
/// first `prepare` empties that folder (a copy a quit or a crash left), and a cancelled or discarded recording (an Esc,
/// a discard, a mic test) leaves none. Copies are real files the fake recorder writes at the close.
struct AudioCaptureUploadCopyTests {
    private let folder = URL.temporaryDirectory.appending(path: "kotoba-upload-copy-test-\(UUID().uuidString)")
    private var uploads: URL { folder.appending(path: "uploads") }

    private func recording(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "\(name).flac")
        FileManager.default.createFile(atPath: file.path, contents: Data("fLaC".utf8))
        return file
    }

    private func exists(_ file: URL?) -> Bool {
        file.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    @Test func theCopyGoesInTheUploadFolder() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware, uploads: uploads)
        defer { try? FileManager.default.removeItem(at: folder) }

        _ = try await capture.beginCapture(into: try recording("kept"))
        let copy = try #require(await capture.endCapture()?.upload)

        #expect(copy == uploads.appending(path: "kept.ogg"))
        #expect(exists(copy))
    }

    @Test func theFirstPrepareDeletesCopiesAnEarlierRunLeft() async throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: uploads, withIntermediateDirectories: true)
        let left = uploads.appending(path: "left.ogg")
        FileManager.default.createFile(atPath: left.path, contents: Data("OggS".utf8))
        let capture = AudioCapture(hardware: FakeCaptureHardware(), uploads: uploads)

        await capture.prepare()

        #expect(!exists(left))
    }

    @Test func aDiscardedRecordingLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware, uploads: uploads)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = try recording("discarded")

        _ = try await capture.beginCapture(into: file)
        #expect(await capture.discardCapture())

        #expect(!exists(file))
        #expect(!exists(try #require(hardware.recorders.first?.upload)))
    }

    /// An Esc whose Undo window ends keeps the FLAC for History and sends nothing (`DictationPipeline.cancel`).
    @Test func aCancelledRecordingKeepsItsFLACAndLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let capture = AudioCapture(hardware: hardware, uploads: uploads)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try await capture.beginCapture(into: try recording("cancelled"))

        let audio = try #require(await capture.cancelCapture())

        #expect(exists(audio.file))
        #expect(audio.upload == nil)
        #expect(!exists(try #require(hardware.recorders.first?.upload)))
    }

    @Test func theMicTestLeavesNoCopy() async throws {
        let hardware = FakeCaptureHardware()
        hardware.writeUploadCopies()
        let clock = ManualClock()
        let capture = AudioCapture(hardware: hardware, clock: clock, uploads: uploads)
        defer { try? FileManager.default.removeItem(at: folder) }
        let start = clock.now
        guard case .running(let levels) = await capture.beginTest(for: .seconds(5)) else {
            Issue.record("The mic test did not start")
            return
        }
        await clock.waitForTimer(at: start + .seconds(5))

        clock.advance(by: .seconds(5))

        #expect(await finished(levels) != nil)
        let copy = try #require(hardware.recorders.first?.upload)
        #expect(await eventually { !exists(copy) })
    }
}
