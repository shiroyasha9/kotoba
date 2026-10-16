import Foundation
import Testing

@testable import KotobaCore

/// "Paste Last Dictation" (menu and chord) and "Copy Last Dictation": a stored text sent again through the clipboard
/// guard.
struct PipelinePasteAgainTests {
    @Test func pasteAgainWaitsForNoTranscription() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let gate = Gate()
        await world.provider.hold(at: gate)
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.tap(world)

        await pipeline.pasteAgain("Older text.", of: DictationID())
        #expect(await eventually { await gate.hasWaiters })
        await gate.open()
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Fix the login bug."])
    }

    @Test func pasteAgainPastesAndRestoresTheClipboard() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.pasteAgain("Fix the login bug.", of: DictationID())
        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.pasteboard.isTransient)

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await world.paster.keystrokes == [.commandV])
    }

    @Test func pasteAgainWithoutPermissionLeavesTheTextCopied() async {
        let world = FakeWorld(transcript: "unused")
        await world.paster.deny(with: FakeError())
        let pipeline = world.makePipeline()
        let id = DictationID()

        await pipeline.pasteAgain("Fix the login bug.", of: id)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "Fix the login bug.")
        #expect(await world.pasteboard.isTransient == false)
        #expect(await pipeline.state == .copied(id))
    }

    @Test func pasteAgainWaitsForNoRecording() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)

        await pipeline.pasteAgain("Fix the login bug.", of: DictationID())

        #expect(await world.paster.pasted.isEmpty)
    }

    @Test func pasteLastChordPastesTheLastDictationAndRestoresTheClipboard() async {
        let world = FakeWorld(transcript: "Fix the login bug.")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        await pipeline.tap(world)
        await pipeline.settle()
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        await pipeline.handle(.pasteLast)
        await pipeline.settle()
        #expect(await world.paster.pasted == ["Fix the login bug.", "Fix the login bug."])
        #expect(await world.pasteboard.isTransient)

        world.clock.advance(by: .seconds(1))
        await pipeline.settle()
        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await world.paster.keystrokes == [.commandV, .commandV])
    }

    @Test func pasteLastChordTakesTheNewestDeliveredDictation() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record("Older text.", at: 1_000, .pasted))
        try await world.store.save(Self.record("Copied text.", at: 2_000, .copied))
        try await world.store.save(Self.record("Failed text.", at: 3_000, .failed))

        await pipeline.handle(.pasteLast)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Copied text."])
    }

    @Test func pasteLastChordWithNoDictationPastesNothing() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.handle(.pasteLast)
        await pipeline.settle()

        #expect(await world.paster.keystrokes.isEmpty)
        #expect(await world.pasteboard.text == "user's clipboard")
    }

    @Test func pasteLastChordWhileRecordingPastesNothing() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record("Older text.", at: 1_000, .pasted))
        await pipeline.tap(world)

        await pipeline.handle(.pasteLast)
        await pipeline.settle()

        #expect(await world.paster.pasted.isEmpty)
        #expect(await pipeline.state == .recording(isLong: false))
    }

    static func record(_ text: String, at time: TimeInterval, _ status: DictationRecord.Status) -> DictationRecord {
        DictationRecord(
            id: DictationID(), createdAt: Date(timeIntervalSince1970: time),
            audio: RecordedAudio(file: URL(filePath: "/tmp/\(time).flac"), duration: .seconds(1)),
            transcript: text, status: status, latency: LatencyLog())
    }

    @Test func copyLastChordCopiesTheLastDictationAndSaysSo() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        let last = Self.record("Copied text.", at: 2_000, .copied)
        try await world.store.save(Self.record("Older text.", at: 1_000, .pasted))
        try await world.store.save(last)

        await pipeline.handle(.copyLast)
        await pipeline.settle()
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "Copied text.")
        #expect(await world.pasteboard.isTransient == false)
        #expect(await world.paster.keystrokes.isEmpty)
        #expect(await pipeline.state == .copied(last.id))
    }

    @Test func copyLastChordWithNoDictationCopiesNothing() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.handle(.copyLast)
        await pipeline.settle()

        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.state == .idle)
    }

    @Test func copyLastChordWhileRecordingCopiesAndKeepsTheRecordingShown() async throws {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()
        try await world.store.save(Self.record("Older text.", at: 1_000, .pasted))
        await pipeline.tap(world)

        await pipeline.handle(.copyLast)
        await pipeline.settle()

        #expect(await world.pasteboard.text == "Older text.")
        #expect(await pipeline.state == .recording(isLong: false))
    }

    @Test func copyAgainLeavesTheTextWithNoRestore() async {
        let world = FakeWorld(transcript: "unused")
        let pipeline = world.makePipeline()

        await pipeline.copyAgain("Fix the login bug.")
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "Fix the login bug.")
        #expect(await world.pasteboard.isTransient == false)
        #expect(await world.paster.keystrokes.isEmpty)
    }
}
