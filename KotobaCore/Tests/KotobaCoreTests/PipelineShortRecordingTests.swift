import Foundation
import Testing

@testable import KotobaCore

/// A stop with less audio than `Settings.minimumRecording` (an accidental double tap) is discarded: no request, no
/// file, no history row, no paste and no error. The audio written decides, not the key times.
struct PipelineShortRecordingTests {
    @Test(arguments: [Duration.zero, .milliseconds(499)])
    func aRecordingUnderTheMinimumIsDiscarded(length: Duration) async {
        let world = FakeWorld(transcript: "never heard")
        let pipeline = world.makePipeline()
        await world.audio.record(length)

        await pipeline.dictate(world)

        #expect(await world.provider.requests.isEmpty)
        #expect(await world.store.records.isEmpty)
        #expect(await world.store.ledger.isEmpty)
        #expect(await world.audio.discarded == (await world.audio.files))
        #expect(await world.paster.pasteCount == 0)
        #expect(await pipeline.state == .idle)
        #expect(await pipeline.isQuiet)
    }

    @Test(arguments: [Duration.milliseconds(500), .milliseconds(510)])
    func aRecordingOfTheMinimumOrMoreIsSent(length: Duration) async throws {
        let world = FakeWorld(transcript: "short")
        let pipeline = world.makePipeline()
        await world.audio.record(length)

        await pipeline.dictate(world)

        #expect(await world.provider.requests.map(\.duration) == [length])
        #expect(await world.paster.pasted == ["short"])
        #expect(try #require(await world.store.records.first).status == .pasted)
        #expect(await world.audio.discarded.isEmpty)
    }

    /// Undo resumes the same file: its whole audio counts, not the moments since the resume (300 ms here) nor the
    /// key times with the Undo window in them (3.7 s).
    @Test(arguments: [(Duration.milliseconds(700), true), (.milliseconds(400), false)])
    func aResumedRecordingCountsItsWholeAudio(audio: Duration, isSent: Bool) async throws {
        let world = FakeWorld(transcript: "resumed")
        let pipeline = world.makePipeline()
        await world.audio.record(audio)

        await pipeline.tap(world)
        world.clock.advance(by: .milliseconds(400))
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(3))
        await pipeline.undo()
        world.clock.advance(by: .milliseconds(300))
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.requests.count == (isSent ? 1 : 0))
        #expect(await world.paster.pasted == (isSent ? ["resumed"] : []))
        #expect(await world.store.records.count == (isSent ? 1 : 0))
        #expect(await world.audio.discarded.count == (isSent ? 0 : 1))
    }

    /// A file the audio folder will not give up is remembered, so no launch takes it for an orphan and sends it.
    @Test func aShortRecordingWhoseFileStaysIsRememberedAsDiscarded() async throws {
        let world = FakeWorld(transcript: "never heard")
        let pipeline = world.makePipeline()
        await world.audio.record(.milliseconds(200))
        await world.audio.failRemoval()

        await pipeline.dictate(world)

        let file = try #require(await world.audio.files.first)
        #expect(await world.audio.undeletable == [file])
        #expect(await world.store.discarded.count == 1)
        #expect(await world.store.records.isEmpty)
        #expect(await world.provider.requests.isEmpty)
        #expect(await pipeline.state == .idle)
    }

    /// A silent clip over the minimum is still sent; its empty answer says no speech was heard.
    @Test func aSilentRecordingOverTheMinimumSaysNoSpeechHeard() async throws {
        let world = FakeWorld(transcript: "")
        let pipeline = world.makePipeline()
        await world.audio.record(.milliseconds(800))

        await pipeline.dictate(world)

        let record = try #require(await world.store.records.first)
        #expect(await world.provider.requests.count == 1)
        #expect(await pipeline.state == .rejected(record.id, .emptyTranscript))
    }
}
