import Testing

@testable import KotobaCore

/// The paste waits for the chord's release, but not for ever: a lost release (Secure Input took the keyboard) holds
/// it only for `Settings.chordReleaseWait`.
struct PipelineChordReleaseTests {
    @Test func aReleaseThatNeverComesHoldsThePasteOnlyForTheBound() async {
        let world = FakeWorld(transcript: "stuck")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        world.clock.advance(by: .seconds(1))

        // The stop tap's release is lost.
        await pipeline.handle(.chordDown(.tapOrHold))
        let pastedAtOnce = await eventually { await world.paster.pasteCount > 0 }
        world.clock.advance(by: .milliseconds(1_900))
        let pastedBeforeTheBound = await eventually { await world.paster.pasteCount > 0 }
        world.clock.advance(by: .milliseconds(100))
        let pastedAtTheBound = await eventually { await world.paster.pasteCount > 0 }

        #expect(pastedAtOnce == false)
        #expect(pastedBeforeTheBound == false)
        #expect(pastedAtTheBound)
        #expect(await world.paster.pasted == ["stuck"])
    }

    @Test func aReleaseBeforeTheBoundPastesAtOnceAndTheBoundDoesNothingLater() async {
        let world = FakeWorld(transcript: "held")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.handle(.chordDown(.tapOrHold))
        _ = await eventually { await world.paster.pasteCount > 0 }

        await pipeline.handle(.chordUp)
        await pipeline.settle()
        world.clock.advance(by: .seconds(3))
        await pipeline.settle()

        #expect(await world.paster.pasted == ["held"])
    }
}
