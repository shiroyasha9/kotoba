import Foundation
import Testing

@testable import KotobaCore

/// Latency marks and what each dictation record carries.
struct PipelineLatencyTests {

    @Test func latencyMarksAreOffsetsFromKeyDown() async throws {
        let world = FakeWorld(transcript: "timed")
        let pipeline = world.makePipeline()
        let keyDown = world.clock.now

        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordUp)
        await world.audio.deliverFirstBuffer(at: keyDown + .milliseconds(40))
        world.clock.advance(by: .seconds(12))
        await pipeline.tap(world)
        await pipeline.settle()

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.keyDown] == .zero)
        #expect(latency.offsets[.firstAudioBuffer] == .milliseconds(40))
        #expect(latency.offsets[.stop] == .seconds(12))
        #expect(latency.offsets[.uploadStart] == .seconds(12))
        #expect(latency.offsets[.response] == .seconds(12))
        #expect(latency.offsets[.pasteSent] == .seconds(12))
        #expect(latency.duration(from: .stop, to: .pasteSent) == .zero)
    }

    @Test func theProvidersNetworkTimingSplitsTheWaitIntoUploadAndServer() async throws {
        let world = FakeWorld(transcript: "split")
        let pipeline = world.makePipeline()
        let keyDown = world.clock.now
        await world.provider.time(
            NetworkTiming(
                connected: keyDown + .milliseconds(12_040), uploadSent: keyDown + .milliseconds(12_100),
                firstByte: keyDown + .milliseconds(12_700)))

        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordUp)
        world.clock.advance(by: .seconds(12))
        await pipeline.tap(world)
        await pipeline.settle()

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.connected] == .milliseconds(12_040))
        #expect(latency.offsets[.uploadSent] == .milliseconds(12_100))
        #expect(latency.offsets[.firstByte] == .milliseconds(12_700))
    }

    @Test func aReusedConnectionRecordsNoConnectedMark() async throws {
        let world = FakeWorld(transcript: "warm")
        let pipeline = world.makePipeline()
        let keyDown = world.clock.now
        await world.provider.time(
            NetworkTiming(uploadSent: keyDown + .milliseconds(30), firstByte: keyDown + .milliseconds(500)))

        await pipeline.dictate(world)

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.connected] == nil)
        #expect(latency.offsets[.uploadSent] == .milliseconds(30))
        #expect(latency.offsets[.firstByte] == .milliseconds(500))
    }

    @Test func aRouteWithoutNetworkMetricsRecordsNoNetworkMarks() async throws {
        let world = FakeWorld(transcript: "no metrics")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.pasteSent] != nil)
        #expect(latency.offsets[.connected] == nil)
        #expect(latency.offsets[.uploadSent] == nil)
        #expect(latency.offsets[.firstByte] == nil)
    }

    @Test func inTapModeTheStopMarkIsTheSecondChordDownNotItsRelease() async throws {
        let world = FakeWorld(transcript: "tap")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)
        world.clock.advance(by: .seconds(3))
        await pipeline.handle(.chordDown)
        #expect(await pipeline.state == .transcribing)
        world.clock.advance(by: .milliseconds(150))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.stop] == .seconds(3))
    }

    @Test func inHoldModeTheStopMarkIsTheRelease() async throws {
        let world = FakeWorld(transcript: "hold")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown)
        world.clock.advance(by: .seconds(2))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        let latency = try #require(await world.store.records.first).latency
        #expect(latency.offsets[.stop] == .seconds(2))
    }

    @Test func eachDictationRecordsTheModelThatTranscribedIt() async throws {
        let world = FakeWorld(transcript: "which model")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        await pipeline.tap(world)
        await pipeline.handle(.escape)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        let records = await world.store.records
        #expect(records.first?.model == "fake/model-1")
        #expect(records.last?.status == .cancelled)
        #expect(records.last?.model == nil)
    }

    @Test func theRequestCarriesTheRecordedFileAndLanguage() async throws {
        let world = FakeWorld(transcript: "hello")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let request = try #require(await world.provider.requests.first)
        #expect(request.audio == (await world.audio.files.first))
        #expect(request.language == Locale.Language(identifier: "en"))
    }
}
