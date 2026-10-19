import Foundation
import Testing

@testable import KotobaCore

/// The Opus upload copy of a recording (`RecordedAudio.upload`): the first request carries it next to the FLAC and
/// deletes it when it ends, so a retry sends the FLAC; a recording without one (the recorder's encoder failed) sends
/// the FLAC only. The route picks which file it sends (`TranscriptionRoute.takesOggOpus` in KotobaProviders).
struct PipelineUploadCopyTests {
    private let folder = URL.temporaryDirectory.appending(path: "kotoba-pipeline-upload-test-\(UUID().uuidString)")

    @Test func theFirstRequestCarriesTheCopyAndDeletesItWhenItEnds() async throws {
        let world = FakeWorld(transcript: "hello")
        await world.audio.writeUploadCopies(in: folder)
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: folder) }

        await pipeline.dictate(world)

        let request = try #require(await world.provider.requests.first)
        let flac = try #require(await world.audio.files.first)
        let copy = try #require(request.upload)
        #expect(request.audio == flac)
        #expect(copy.path.hasPrefix(folder.path + "/"))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(await world.paster.pasted == ["hello"])
    }

    @Test func aRetrySendsTheFLAC() async throws {
        let world = FakeWorld(transcript: "hello")
        await world.audio.writeUploadCopies(in: folder)
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: folder) }
        await world.provider.fail(with: ProviderError.offline)
        await pipeline.dictate(world)
        let first = try #require(await world.provider.requests.first?.upload)
        #expect(!FileManager.default.fileExists(atPath: first.path))

        await world.provider.fail(with: nil)
        await pipeline.retryPending()

        let retry = try #require(await world.provider.requests.last)
        #expect(await world.provider.requests.count == 2)
        #expect(retry.upload == nil)
        #expect(retry.audio == (try #require(await world.audio.files.first)))
    }

    @Test func aRecordingWithNoCopySendsTheFLACOnly() async throws {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let request = try #require(await world.provider.requests.first)
        #expect(request.audio == (try #require(await world.audio.files.first)))
        #expect(request.upload == nil)
        #expect(await world.paster.pasted == ["hello"])
    }
}
