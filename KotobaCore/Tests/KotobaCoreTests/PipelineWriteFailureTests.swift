import Foundation
import Testing

@testable import KotobaCore

/// The recording file stopped taking audio (a full disk): the pill says so instead of the double tap's silent discard,
/// and the part that was written is still sent and pasted.
struct PipelineWriteFailureTests {
    @Test(arguments: [Duration.zero, .milliseconds(499)])
    func aRecordingWithTooLittleSavedSaysTheAudioWasNotSaved(written: Duration) async {
        let world = FakeWorld(transcript: "never heard")
        let pipeline = world.makePipeline()
        await world.audio.failWrites(after: written)

        await pipeline.dictate(world)

        #expect(await world.provider.requests.isEmpty)
        #expect(await world.store.records.isEmpty)
        #expect(await world.audio.discarded == (await world.audio.files))
        #expect(await world.paster.pasteCount == 0)
        #expect(await pipeline.state == .audioNotSaved)
    }

    @Test func thePartThatWasSavedIsPastedWithAWarning() async throws {
        let world = FakeWorld(transcript: "the first half")
        let pipeline = world.makePipeline()
        await world.audio.failWrites(after: .seconds(3))

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(await world.provider.requests.map(\.duration) == [.seconds(3)])
        #expect(await world.paster.pasted == ["the first half"])
        #expect(record.status == .pasted)
        #expect(await pipeline.state == .audioCut(record.id))
    }

    /// A failure to reach the provider says more than the cut: the audio is saved and waits for a retry.
    @Test func aFailedTranscriptionShowsItsOwnError() async throws {
        let world = FakeWorld(transcript: "the first half")
        await world.provider.fail(with: ProviderError.offline)
        let pipeline = world.makePipeline()
        await world.audio.failWrites(after: .seconds(3))

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(await pipeline.state == .failed(record.id))
    }
}
