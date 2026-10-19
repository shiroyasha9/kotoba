import Foundation
import Testing

@testable import KotobaCore

/// A clipboard over `PasteboardSnapshot.byteLimit` is not kept: the dictation still pastes, the transcript stays on
/// the clipboard, and the pill says the earlier clipboard is gone.
struct PipelineLargeClipboardTests {
    @Test func aDictationPastesAndSaysTheClipboardWasNotKept() async throws {
        let world = FakeWorld(transcript: "dictated", clipboard: "a huge image")
        await world.pasteboard.holdMoreThanTheLimit()
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        let record = try #require(await world.store.records.first)
        #expect(await world.paster.pasted == ["dictated"])
        #expect(record.status == .pasted)
        #expect(await world.pasteboard.text == "dictated")
        #expect(await pipeline.state.notice == .clipboardNotKept(record.id))
    }

    @Test func pasteAgainSaysTheClipboardWasNotKept() async {
        let world = FakeWorld(transcript: "unused")
        await world.pasteboard.holdMoreThanTheLimit()
        let pipeline = world.makePipeline()
        let id = DictationID()

        await pipeline.pasteAgain("Fix the login bug.", of: id)
        world.clock.advance(by: .seconds(5))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["Fix the login bug."])
        #expect(await world.pasteboard.text == "Fix the login bug.")
        #expect(await pipeline.state.notice == .clipboardNotKept(id))
    }

    /// A clipboard under the limit comes back as before.
    @Test func aClipboardUnderTheLimitComesBack() async {
        let world = FakeWorld(transcript: "dictated", clipboard: "user's clipboard")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.settle()

        #expect(await world.pasteboard.text == "user's clipboard")
        #expect(await pipeline.state == .idle)
    }
}
