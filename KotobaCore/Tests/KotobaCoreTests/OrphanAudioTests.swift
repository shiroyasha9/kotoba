import Foundation
import Testing

@testable import KotobaCore

/// An audio file with no History row gets a row at launch and is transcribed into Recovered, as a quit does.
struct OrphanAudioTests {
    let folder = URL(filePath: "/tmp/kotoba-tests")
    let launchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func file(_ id: DictationID = DictationID(), secondsBeforeLaunch: TimeInterval = 60) -> OrphanAudio.File {
        OrphanAudio.File(
            url: folder.appending(path: "\(id.rawValue.uuidString).flac"),
            createdAt: launchedAt - secondsBeforeLaunch)
    }

    @Test func anOrphanGetsAPendingRowWithTheFileCreationDateAndLength() throws {
        let orphan = file(secondsBeforeLaunch: 3_600)

        let records = OrphanAudio.records(files: [orphan], knownIDs: [], launchedAt: launchedAt) { _ in .seconds(42) }

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.id == OrphanAudio.id(of: orphan.url))
        #expect(record.status == .pending)
        #expect(record.createdAt == orphan.createdAt)
        #expect(record.audio == RecordedAudio(file: orphan.url, duration: .seconds(42)))
        #expect(record.transcript == nil)
        #expect(record.output == .transcript)
    }

    @Test func aFileWithARowIsSkippedAndNotRead() {
        let known = DictationID()
        var read: [URL] = []

        let records = OrphanAudio.records(files: [file(known)], knownIDs: [known], launchedAt: launchedAt) {
            read.append($0)
            return .seconds(1)
        }

        #expect(records.isEmpty)
        #expect(read.isEmpty)
    }

    /// A recording that started after launch has no row until its stop; it is never taken.
    @Test func aFileCreatedAfterLaunchIsSkipped() {
        let records = OrphanAudio.records(
            files: [file(secondsBeforeLaunch: -1), file(secondsBeforeLaunch: 0)], knownIDs: [], launchedAt: launchedAt
        ) { _ in .seconds(1) }

        #expect(records.isEmpty)
    }

    @Test func onlyAUUIDNamedFlacIsADictation() {
        let id = UUID().uuidString
        let names = ["notes.flac", "\(id).wav", "\(id.lowercased()).flac", "\(id).flac.part", "\(id) 2.flac"]
        let files = names.map { OrphanAudio.File(url: folder.appending(path: $0), createdAt: launchedAt - 60) }

        #expect(OrphanAudio.records(files: files, knownIDs: [], launchedAt: launchedAt) { _ in .seconds(1) }.isEmpty)
        #expect(OrphanAudio.id(of: folder.appending(path: "\(id).flac"))?.rawValue.uuidString == id)
    }

    /// The owner sees it in History and can delete it; kotoba deletes nothing.
    @Test func aFileWithNoReadableAudioGetsACancelledRow() {
        let records = OrphanAudio.records(
            files: [file(), file()], knownIDs: [], launchedAt: launchedAt
        ) { _ in nil }

        #expect(records.map(\.status) == [.cancelled, .cancelled])
        #expect(records.allSatisfy { $0.audio.duration == .zero })
    }

    @Test func orphansComeOldestFirst() {
        let newer = file(secondsBeforeLaunch: 10)
        let older = file(secondsBeforeLaunch: 20)

        let records = OrphanAudio.records(files: [newer, older], knownIDs: [], launchedAt: launchedAt) { _ in
            .seconds(1)
        }

        #expect(records.map(\.audio.file) == [older.url, newer.url])
    }

    @Test func anAdoptedOrphanIsRetriedAtLaunchIntoRecoveredAndNothingIsPasted() async throws {
        let world = FakeWorld(transcript: "from before the crash", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()
        let orphan = file()
        for record in OrphanAudio.records(
            files: [orphan], knownIDs: [], launchedAt: launchedAt, length: { _ in .seconds(5) })
        {
            try await world.store.save(record)
        }

        await pipeline.retryPending()

        let record = try #require(await world.store.records.first)
        #expect(record.status == .recovered)
        #expect(record.transcript == "from before the crash")
        #expect(await world.provider.requests.map(\.audio) == [orphan.url])
        #expect(await world.paster.pasteCount == 0)
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.retries.recovered().map(\.id) == [record.id])
    }

    @Test func theNameRuleReadsBackTheNameThePipelineWrites() {
        let id = DictationID()

        #expect(OrphanAudio.id(of: folder.appending(path: id.audioFileName)) == id)
    }

    /// The bytes the spike wrote by hand (`spikes/flac-kill`), which AVAudioFile reads.
    @Test func theStreamInfoHoldsTheCaptureFormat() {
        let expected =
            Data([0x00, 0x00, 0x00, 0x22, 0x12, 0x00, 0x12, 0x00] + [UInt8](repeating: 0, count: 6))
            + Data([0x03, 0xE8, 0x00, 0xF0] + [UInt8](repeating: 0, count: 20))

        let streamInfo = OrphanAudio.streamInfo(sampleRate: 16_000, channels: 1, bitsPerSample: 16, blockSize: 4_608)

        #expect(streamInfo == expected)
        #expect(streamInfo.count == OrphanAudio.flacHeaderSize - 4)
    }

    @Test func onlyAZeroedStreamInfoIsUnfinished() {
        let fLaC = Data("fLaC".utf8)
        let streamInfo = OrphanAudio.streamInfo(sampleRate: 16_000, channels: 1, bitsPerSample: 16, blockSize: 4_608)

        #expect(OrphanAudio.isUnfinished(header: fLaC + Data(count: 38)))
        #expect(!OrphanAudio.isUnfinished(header: fLaC + streamInfo))
        #expect(!OrphanAudio.isUnfinished(header: Data()))
        #expect(!OrphanAudio.isUnfinished(header: fLaC + Data(count: 20)))
        #expect(!OrphanAudio.isUnfinished(header: Data("RIFF".utf8) + Data(count: 38)))
    }
}
