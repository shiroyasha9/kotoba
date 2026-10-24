import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// What the pill shows (docs/research/ui-redesign.md, "Pill"): hotkey events in, the pill's look out. Push to talk shows
/// bars only, hands-free its Cancel and Stop; a paste ends in the check, and nothing else does.
struct IndicatorLookTests {
    /// Every look the pipeline's states go through, with "Show indicator: While Dictating".
    private static func looks(of states: [DictationState]) -> [IndicatorLook] {
        states.map { IndicatorLook($0, showsIdleBar: false, isSecureInputOn: false) }
    }

    /// Every state the pipeline published once its work settled, each one taken from `states`: the count comes from
    /// the pipeline (`publishedStateCount`), so a state too many or too few fails the test, and none is missed.
    private static func published(by pipeline: DictationPipeline) async -> [DictationState] {
        await pipeline.settle()
        let count = await pipeline.publishedStateCount
        let log = Mutex<[DictationState]>([])
        let reader = Task {
            for await state in pipeline.states {
                log.withLock { $0.append(state) }
            }
        }
        defer { reader.cancel() }
        #expect(await eventually { log.withLock { $0.count >= count } })
        return log.withLock { $0 }
    }

    // MARK: Hands-free and push to talk

    @Test func aTapRecordsHandsFree() async {
        let world = FakeWorld(transcript: "hands-free")
        let pipeline = world.makePipeline()

        await pipeline.tap(world)

        #expect(await pipeline.state.phase == .recording(isLong: false))
        let look = IndicatorLook(await pipeline.state, showsIdleBar: false, isSecureInputOn: false)
        #expect(look == .recording(IndicatorRecording(isHandsFree: true)))
    }

    @Test func aHoldPastTheThresholdIsPushToTalkUntilTheRelease() async {
        let world = FakeWorld(transcript: "held")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()
        #expect(await pipeline.state.phase == .recording(isLong: false, isPushToTalk: true))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        let shown = Self.looks(of: await Self.published(by: pipeline))
        #expect(
            shown == [.recording(IndicatorRecording(isHandsFree: false)), .processing, .done, .hidden])
    }

    /// With push to talk on a chord of its own, the hands-free chord held past the threshold still runs until the next
    /// press, and the push-to-talk chord's hold is push to talk.
    @Test(arguments: [(ChordGesture.toggle, true), (.hold, false)])
    func aSplitChordHeldPastTheThresholdKeepsItsMode(_ gesture: ChordGesture, isHandsFree: Bool) async {
        let world = FakeWorld(transcript: "split")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(gesture))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()

        #expect(await pipeline.state.phase == .recording(isLong: false, isPushToTalk: !isHandsFree))
    }

    /// The silent mic and the 10-minute mark keep the mode.
    @Test func aPushToTalkRecordingStaysPushToTalkWhenTheMicGoesSilent() async {
        let world = FakeWorld(transcript: "quiet")
        let pipeline = world.makePipeline(noSoundWarning: .seconds(2))

        await pipeline.handle(.chordDown(.tapOrHold))
        await world.meter(pipeline, 0, for: .seconds(3))

        #expect(await pipeline.state.phase == .recording(isLong: false, isSilent: true, isPushToTalk: true))
    }

    /// Undo resumes a recording that the next press stops, whatever started it.
    @Test func undoResumesHandsFree() async {
        let world = FakeWorld(transcript: "resumed")
        let pipeline = world.makePipeline()
        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()

        await pipeline.handle(.escape)
        #expect(IndicatorLook(await pipeline.state, showsIdleBar: false, isSecureInputOn: false) == .message)
        await pipeline.handle(.chordUp)
        await pipeline.undo()

        #expect(await pipeline.state.phase == .recording(isLong: false))
    }

    /// A release handled after the threshold announced the press as push to talk, with the release's own time under
    /// the threshold: a tap. The pill shows the recording hands-free again.
    @Test func aLateReleaseOfATapShowsTheRecordingHandsFree() async {
        let world = FakeWorld(transcript: "late")
        let pipeline = world.makePipeline()
        let pressedAt = world.clock.now

        await pipeline.handle(.chordDown(.tapOrHold), at: pressedAt)
        world.clock.advance(by: .milliseconds(400))
        await pipeline.settle()
        await pipeline.handle(.chordUp, at: pressedAt + .milliseconds(100))

        let published = await Self.published(by: pipeline)
        #expect(published.map(\.phase) == [.recording(isLong: false, isPushToTalk: true), .recording(isLong: false)])
    }

    // MARK: The check

    @Test func aPasteShowsTheCheckOnceThenIdle() async {
        let world = FakeWorld(transcript: "pasted")
        let pipeline = world.makePipeline()

        await pipeline.dictate(world)

        let published = await Self.published(by: pipeline)
        #expect(published.map(\.phase) == [.recording(isLong: false), .transcribing, .idle, .idle])
        #expect(published.map(\.isPasted) == [false, false, true, false])
        #expect(Self.looks(of: published) == [.recording(.init(isHandsFree: true)), .processing, .done, .hidden])
        // The state rests on idle: nothing waits on the check.
        #expect(await pipeline.state == .idle)
    }

    /// A paste while the next dictation is on its way shows no check: the sweep goes on, and the check comes when the
    /// last one pastes.
    @Test func aPasteWithAnotherDictationInFlightShowsNoCheck() async throws {
        let world = FakeWorld(transcript: "text")
        let pipeline = world.makePipeline()
        await pipeline.tap(world)
        let first = try #require(await world.audio.files.last)
        let firstGate = Gate()
        await world.provider.hold(at: firstGate, onlyFor: first)
        await pipeline.tap(world)
        #expect(await eventually { await firstGate.hasWaiters })
        await pipeline.tap(world)
        let second = try #require(await world.audio.files.last)
        let secondGate = Gate()
        await world.provider.hold(at: secondGate, onlyFor: second)
        await pipeline.tap(world)
        #expect(await eventually { await secondGate.hasWaiters })

        await firstGate.open()
        #expect(await eventually { await world.paster.pasteCount == 1 })
        await secondGate.open()
        await pipeline.settle()

        let published = await Self.published(by: pipeline)
        let checks = published.filter(\.isPasted)
        #expect(checks == [DictationState(.idle, isPasted: true)])
        #expect(await world.paster.pasteCount == 2)
    }

    /// An accidental double tap is dropped with no word: no check, as nothing was pasted.
    @Test func aDroppedShortRecordingShowsNoCheck() async {
        let world = FakeWorld(transcript: "never heard")
        let pipeline = world.makePipeline()
        await world.audio.record(.milliseconds(100))

        await pipeline.dictate(world)

        let published = await Self.published(by: pipeline)
        #expect(Self.looks(of: published) == [.recording(.init(isHandsFree: true)), .processing, .hidden])
    }

    @Test func aFailedSendShowsItsMessageNotTheCheck() async {
        let world = FakeWorld(transcript: "later")
        let pipeline = world.makePipeline()
        await world.provider.fail(with: ProviderError.timedOut)

        await pipeline.dictate(world)

        let published = await Self.published(by: pipeline)
        #expect(Self.looks(of: published) == [.recording(.init(isHandsFree: true)), .processing, .message])
        #expect(published.allSatisfy { !$0.isPasted })
    }

    // MARK: Each state

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        let state: DictationState
        var showsIdleBar = false
        var isSecureInputOn = false
        let look: IndicatorLook

        var testDescription: String { name }
    }

    static let id = DictationID()

    static let rows: [Row] = [
        Row(name: "idle, while dictating", state: .idle, look: .hidden),
        Row(name: "idle, always", state: .idle, showsIdleBar: true, look: .idle),
        Row(
            name: "hands-free", state: .init(.recording(isLong: false)),
            look: .recording(.init(isHandsFree: true))),
        Row(
            name: "push to talk with cleanup",
            state: .init(.recording(isLong: false, isCleaned: true, isPushToTalk: true)),
            look: .recording(.init(isHandsFree: false, isCleaned: true))),
        Row(
            name: "silent", state: .init(.recording(isLong: false, isSilent: true)),
            look: .recording(.init(isHandsFree: true, isSilent: true))),
        Row(
            name: "10 minutes", state: .init(.recording(isLong: true)),
            look: .recording(.init(isHandsFree: true, isLong: true))),
        Row(
            name: "Secure Input", state: .init(.recording(isLong: false)), isSecureInputOn: true,
            look: .recording(.init(isHandsFree: true, isSecureInputOn: true))),
        Row(name: "transcribing", state: .init(.transcribing), look: .processing),
        Row(name: "cleaning", state: .init(.cleaning), look: .processing),
        Row(name: "rewriting", state: .init(.polishing), look: .processing),
        Row(name: "pasted", state: .init(.idle, isPasted: true), look: .done),
        Row(
            name: "pasted, the bar after it", state: .init(.idle, isPasted: true), showsIdleBar: true, look: .done),
        Row(name: "Undo", state: .init(.undoable), look: .message),
        Row(name: "a notice", state: .init(.idle, notice: .failed(id)), showsIdleBar: true, look: .message),
        Row(name: "a notice over a send", state: .init(.transcribing, notice: .copied(id)), look: .message),
    ]

    @Test(arguments: rows)
    func eachStateHasItsLook(_ row: Row) {
        let look = IndicatorLook(row.state, showsIdleBar: row.showsIdleBar, isSecureInputOn: row.isSecureInputOn)
        #expect(look == row.look)
    }
}
