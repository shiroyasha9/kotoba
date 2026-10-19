import Foundation
import Testing

@testable import KotobaCore

/// Segment upload (`SegmentUpload`, docs/research/latency-pass-2.md section 7): each segment the capture closes at a
/// pause goes while the recording goes on, and the stop sends only the copy after the last cut. The texts join with
/// one space, as the model wrote them. A segment that fails or times out sends the whole recording instead, so the text
/// never comes from part of the audio. Only a route that sends the upload copy sends segments.
struct PipelineSegmentTests {
    private let fixture = SegmentFixture()

    @Test func aCutWhileRecordingSendsThatSegmentAtOnce() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await pipeline.tap(world)
        let first = try fixture.segment(0, from: 0, seconds: 16)

        await world.audio.cut(first)

        #expect(await eventually { await world.provider.requests.count == 1 })
        let request = try #require(await world.provider.requests.first)
        #expect(request.audio == first.file)
        #expect(request.upload == first.file)
        #expect(request.duration == .seconds(16))
        #expect(await pipeline.state.phase == .recording(isLong: false))
        #expect(await eventually { !FileManager.default.fileExists(atPath: first.file.path) })
    }

    /// One speech entry: the costs added up, the recording's length, the words pasted.
    @Test func theStopSendsTheLastCopyAndPastesTheTextsJoined() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await world.provider.charge(.reported(0.001), audio: .seconds(1))
        let first = try fixture.segment(0, from: 0, seconds: 16)
        await world.provider.hear("First part.", for: first.file)
        let last = try await fixture.lastCopy(of: world, from: 16)
        await world.provider.hear("second part", for: last)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await world.provider.requests.count == 1 })
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.requests.map(\.audio) == [first.file, last])
        #expect(await world.provider.requests.last?.upload == last)
        #expect(await world.provider.requests.last?.duration == .seconds(24))
        #expect(await world.paster.pasted == ["First part. second part"])
        let record = try #require(await world.store.records.first)
        #expect(record.transcript == "First part. second part")
        let speech = record.usage.filter { $0.kind == .speech }
        #expect(speech.count == 1)
        #expect(speech.first?.audio == .seconds(40))
        #expect(speech.first?.cost == .reported(0.002))
        #expect(speech.first?.deliveredWords == 4)
        #expect(!FileManager.default.fileExists(atPath: last.path))
    }

    @Test func aSegmentStillOnItsWayAtTheStopIsWaitedFor() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        await world.provider.hear("one", for: first.file)
        let gate = Gate()
        await world.provider.hold(at: gate, onlyFor: first.file)
        let last = try await fixture.lastCopy(of: world, from: 16)
        await world.provider.hear("two", for: last)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.tap(world)
        #expect(await eventually { await world.provider.requests.count == 2 })
        #expect(await world.paster.pasted.isEmpty)
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted == ["one two"])
        #expect(await world.provider.requests.count == 2)
    }

    /// A segment's request has the bound of any request for its audio, from its send.
    /// The copy failed after a cut: no copy after it, so the whole recording goes.
    /// Esc keeps the segments for Undo; the Undo window's end cancels the one on its way and bills the one that answered.
    @Test func theEndOfTheUndoWindowCancelsASegmentOnItsWayAndBillsTheAnsweredOne() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await world.provider.charge(.reported(0.001), audio: .seconds(1))
        let first = try fixture.segment(0, from: 0, seconds: 16)
        let second = try fixture.segment(1, from: 16, seconds: 16)
        let gate = Gate()
        await world.provider.hold(at: gate, onlyFor: second.file)

        await pipeline.tap(world)
        await world.audio.cut(first)
        await world.audio.cut(second)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.handle(.escape)
        await pipeline.settle()
        #expect(await world.provider.cancelled.isEmpty)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.provider.cancelled == [second.file])
        let record = try #require(await world.store.records.first)
        #expect(record.status == .cancelled)
        let billed = await world.store.ledger.filter { $0.kind == .speech && $0.dictation == record.id }
        #expect(billed.count == 1)
        #expect(billed.first?.cost == .reported(0.001))
        #expect(billed.first?.audio == .zero)
        #expect(billed.first?.deliveredWords == 0)
        #expect(!FileManager.default.fileExists(atPath: second.file.path))
    }

    @Test func undoKeepsTheSegmentsAndTheResumedRecordingCutsOn() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        let second = try fixture.segment(1, from: 16, seconds: 16)
        await world.provider.hear("a", for: first.file)
        await world.provider.hear("b", for: second.file)
        let last = try await fixture.lastCopy(of: world, from: 32)
        await world.provider.hear("c", for: last)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await world.provider.requests.count == 1 })
        await pipeline.handle(.escape)
        await pipeline.undo()
        await world.audio.cut(second)
        #expect(await eventually { await world.provider.requests.count == 2 })
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["a b c"])
        #expect(await world.provider.requests.count == 3)
    }

    @Test func quitCancelsASegmentOnItsWayAndKeepsTheRecording() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        let gate = Gate()
        await world.provider.hold(at: gate, onlyFor: first.file)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.shutdown()
        await pipeline.settle()

        #expect(await world.provider.cancelled == [first.file])
        let record = try #require(await world.store.records.first)
        #expect(record.status == .pending)
        #expect(record.audio.file == (try #require(await world.audio.files.first)))
    }

    /// A segment request warms the route as a primer does: the next primer waits a whole interval from it.
    @Test func aSegmentPutsOffTheNextPrimer() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let interval = DictationPipeline.Settings(audioDirectory: URL(filePath: "/tmp")).primerInterval
        await pipeline.tap(world)
        await pipeline.settle()
        let primes = await world.provider.primes

        world.clock.advance(by: interval - .seconds(10))
        await world.audio.cut(try fixture.segment(0, from: 0, seconds: 16))
        #expect(await eventually { await world.provider.requests.count == 1 })
        world.clock.advance(by: interval - .seconds(1))
        await pipeline.settle()
        #expect(await world.provider.primes == primes)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.provider.primes == primes + 1)
    }

    /// No cut: one request for the copy, as before segments.
    @Test func aRecordingWithNoCutSendsOneRequest() async throws {
        let world = FakeWorld(transcript: "short one")
        await world.audio.writeUploadCopies(in: fixture.folder)
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }

        await pipeline.dictate(world)

        #expect(await world.provider.requests.count == 1)
        let request = try #require(await world.provider.requests.first)
        #expect(request.audio == (try #require(await world.audio.files.first)))
        #expect(request.upload?.deletingLastPathComponent().path == fixture.folder.path)
        #expect(await world.paster.pasted == ["short one"])
    }

    /// A route that sends the FLAC sends no segment: one request for the whole recording at the stop.
    @Test func aRouteWithoutTheCopySendsTheWholeRecordingOnly() async throws {
        let world = await fixture.world()
        world.provider.switchRoute(sendsUploadCopy: false)
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        _ = try await fixture.lastCopy(of: world, from: 16)

        await pipeline.tap(world)
        await world.audio.cut(first)
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.requests.count == 1)
        try await fixture.expectWhole(await world.provider.requests.first, of: world)
        #expect(await world.paster.pasted == ["whole recording"])
        #expect(!FileManager.default.fileExists(atPath: first.file.path))
    }
}

/// A segment that fails or times out, or a copy lost after a cut: the whole recording goes, as the FLAC.
struct PipelineSegmentFallbackTests {
    private let fixture = SegmentFixture()

    @Test func aFailedSegmentSendsTheWholeRecording() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        await world.provider.charge(.reported(0.001), audio: .seconds(1))
        let first = try fixture.segment(0, from: 0, seconds: 16)
        await world.provider.fail(first.file, with: ProviderError.server(status: 502))
        let last = try await fixture.lastCopy(of: world, from: 16)
        await world.provider.hear("two", for: last)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await world.provider.requests.count == 1 })
        await pipeline.tap(world)
        await pipeline.settle()

        try await fixture.expectWhole(await world.provider.requests.last, of: world)
        #expect(await world.paster.pasted == ["whole recording"])
        let record = try #require(await world.store.records.first)
        // The whole answer counts the words and the minutes; a segment's answer that is not used, only its cost.
        let speech = record.usage.filter { $0.kind == .speech }
        #expect(speech.map(\.deliveredWords) == [2])
        #expect(speech.map(\.audio) == [.seconds(1)])
    }

    @Test func aSegmentThatTimesOutSendsTheWholeRecording() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)
        let gate = Gate()
        await world.provider.hold(at: gate, onlyFor: first.file)
        let last = try await fixture.lastCopy(of: world, from: 16)
        await world.provider.hear("two", for: last)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await gate.hasWaiters })
        await pipeline.tap(world)
        #expect(await eventually { await world.provider.requests.count == 2 })
        world.clock.advance(by: DictationPipeline.Settings.transcriptionTimeout(for: first.duration))
        #expect(await eventually { await world.provider.requests.count == 3 })
        await pipeline.settle()

        try await fixture.expectWhole(await world.provider.requests.last, of: world)
        #expect(await world.paster.pasted == ["whole recording"])
        #expect(await world.provider.cancelled == [first.file])
    }

    @Test func aCutWithNoCopyAfterItSendsTheWholeRecording() async throws {
        let world = await fixture.world()
        let pipeline = world.makePipeline()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let first = try fixture.segment(0, from: 0, seconds: 16)

        await pipeline.tap(world)
        await world.audio.cut(first)
        #expect(await eventually { await world.provider.requests.count == 1 })
        await pipeline.tap(world)
        await pipeline.settle()

        #expect(await world.provider.requests.count == 2)
        try await fixture.expectWhole(await world.provider.requests.last, of: world)
        #expect(await world.paster.pasted == ["whole recording"])
    }

}

/// Segments, the copy after the last cut and a 40 s recording, for the segment upload suites.
struct SegmentFixture {
    let folder = URL.temporaryDirectory.appending(path: "kotoba-segment-test-\(UUID().uuidString)")

    func segment(_ index: Int, from start: Int, seconds: Int) throws -> UploadSegment {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "segment-\(index).ogg")
        FileManager.default.createFile(atPath: file.path, contents: Data("OggS".utf8))
        return UploadSegment(index: index, file: file, start: .seconds(start), duration: .seconds(seconds))
    }

    /// The copy after the last cut, from `start` to the stop.
    func lastCopy(of world: FakeWorld, from start: Int) async throws -> URL {
        let file = try segment(99, from: start, seconds: 0).file
        await world.audio.endSegments(withCopy: file, startingAt: .seconds(start))
        return file
    }

    /// A 40 s recording, by default.
    func world(transcript: String = "whole recording") async -> FakeWorld {
        let world = FakeWorld(transcript: transcript)
        await world.audio.record(.seconds(40))
        return world
    }

    /// The whole recording's request: the FLAC, for the recording's length.
    func expectWhole(_ request: TranscriptionRequest?, of world: FakeWorld) async throws {
        let flac = try #require(await world.audio.files.first)
        let whole = try #require(request)
        #expect(whole.audio == flac)
        #expect(whole.upload == nil)
        #expect(whole.duration == .seconds(40))
    }

}
