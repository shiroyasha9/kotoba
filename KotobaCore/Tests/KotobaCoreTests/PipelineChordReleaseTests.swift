import Testing

@testable import KotobaCore

/// The paste waits for the chord's release, but not for ever: a lost release (Secure Input took the keyboard) holds
/// it only for `Settings.chordReleaseWait`.
struct PipelineChordReleaseTests {
    /// The test moves the clock only once the bound's timer is armed (`ManualClock.waitForTimer`): until then the
    /// paste waits for it, so no paste before it is a fact, not a guess after some yields. An advance before the
    /// timer was armed put its deadline later, and the paste missed the bound on a busy machine.
    @Test func aReleaseThatNeverComesHoldsThePasteOnlyForTheBound() async {
        let world = FakeWorld(transcript: "stuck")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        world.clock.advance(by: .seconds(1))

        // The stop tap's release is lost.
        let stop = world.clock.now
        await pipeline.handle(.chordDown(.tapOrHold))
        await world.clock.waitForTimer(at: stop + .seconds(2))
        let pastedAtOnce = await world.paster.pasteCount
        world.clock.advance(by: .milliseconds(1_900))
        let pastedBeforeTheBound = await world.paster.pasteCount
        world.clock.advance(by: .milliseconds(100))
        await pipeline.settle()

        #expect(pastedAtOnce == 0)
        #expect(pastedBeforeTheBound == 0)
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

    /// A push-to-talk hold for the next dictation is a new press: the bound is only for the press that stopped this
    /// one, so the paste waits for the new press's release however long it is held (a Cmd-V before it would reach
    /// the app as ⌃⌥⌘V and paste nothing).
    @Test func aNewPressHoldsThePasteUntilItsReleaseWithNoBound() async {
        let world = FakeWorld(transcript: "first")
        let pipeline = world.makePipeline()
        let gate = Gate()
        await world.provider.hold(at: gate)
        await pipeline.tap(world)
        world.clock.advance(by: .seconds(1))
        await pipeline.tap(world)
        #expect(await eventually { await gate.hasWaiters })

        // The next dictation: a push-to-talk hold while the first one is still being transcribed.
        await pipeline.handle(.chordDown(.tapOrHold))
        await gate.open()
        let pastedAtOnce = await eventually { await world.paster.pasteCount > 0 }
        for _ in 0..<5 {
            world.clock.advance(by: .seconds(1))
            _ = await eventually { await world.paster.pasteCount > 0 }
        }
        let pastedWhileHeld = await world.paster.pasteCount

        await world.provider.hear("second")
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(pastedAtOnce == false)
        #expect(pastedWhileHeld == 0)
        #expect(await world.paster.pasted == ["first", "second"])
    }
}
