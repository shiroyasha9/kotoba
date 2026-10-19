import Foundation
import Testing

@testable import KotobaCore

/// The Opus upload copy of a recording (`RecordedAudio.upload`): the first request carries it next to the FLAC, and a
/// recording without one (the recorder's encoder failed) sends the FLAC only. The route picks which file it sends
/// (`TranscriptionRoute.takesOggOpus` in KotobaProviders).
struct PipelineUploadCopyTests {
    @Test func theRequestCarriesTheRecordingsOpusCopyNextToTheFLAC() async throws {
        let world = FakeWorld(transcript: "hello")
        await world.audio.writeUploadCopies()
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let request = try #require(await world.provider.requests.first)
        let flac = try #require(await world.audio.files.first)
        #expect(request.audio == flac)
        #expect(request.upload == flac.deletingPathExtension().appendingPathExtension("ogg"))
        #expect(await world.paster.pasted == ["hello"])
    }

    @Test func aRecordingWithNoOpusCopySendsTheFLACOnly() async throws {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let request = try #require(await world.provider.requests.first)
        #expect(request.audio == (try #require(await world.audio.files.first)))
        #expect(request.upload == nil)
        #expect(await world.paster.pasted == ["hello"])
    }
}
