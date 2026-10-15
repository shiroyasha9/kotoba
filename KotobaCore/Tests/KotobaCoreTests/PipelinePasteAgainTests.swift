import Foundation
import Testing

@testable import KotobaCore

/// "Paste Last Dictation" and "Copy Last Dictation": a stored text sent again through the clipboard guard.
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
