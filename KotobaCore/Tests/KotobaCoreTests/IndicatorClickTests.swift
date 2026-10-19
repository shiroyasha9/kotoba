import Testing

@testable import KotobaCore

/// A click on the indicator pill body is a chord tap (start or stop) only where the pill offers it.
struct IndicatorClickTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let state: DictationState
        let showsIdlePill: Bool
        let click: PillClick?

        var testDescription: String { "\(state), idle pill: \(showsIdlePill)" }
    }

    static let id = DictationID()

    static let rows: [Row] = [
        Row(state: .init(.recording(isLong: false)), showsIdlePill: false, click: .stopsDictation),
        Row(state: .init(.recording(isLong: false)), showsIdlePill: true, click: .stopsDictation),
        Row(state: .init(.recording(isLong: true)), showsIdlePill: false, click: .stopsDictation),
        Row(state: .init(.recording(isLong: false, isSilent: true)), showsIdlePill: false, click: .stopsDictation),
        Row(state: .idle, showsIdlePill: true, click: .startsDictation),
        Row(state: .idle, showsIdlePill: false, click: nil),
        Row(state: .init(.transcribing), showsIdlePill: true, click: nil),
        Row(state: .init(.undoable), showsIdlePill: true, click: nil),
        Row(state: .init(.idle, notice: .failed(id)), showsIdlePill: true, click: nil),
        Row(state: .init(.idle, notice: .copied(id)), showsIdlePill: false, click: nil),
    ]

    /// The recording pill's click stops the dictation and the idle pill's starts one; VoiceOver's press says which.
    @Test(arguments: rows)
    func aClickIsATapOnlyOnTheRecordingAndIdlePills(_ row: Row) {
        #expect(
            IndicatorPlacement.click(in: row.state, showsIdlePill: row.showsIdlePill, isYielding: false) == row.click)
    }

    /// A development build that gives way to the release app starts nothing from its idle pill, but a click still stops
    /// its own recording.
    @Test func whileYieldingOnlyARecordingPillIsATap() {
        #expect(IndicatorPlacement.click(in: .idle, showsIdlePill: true, isYielding: true) == nil)
        #expect(
            IndicatorPlacement.click(in: .init(.recording(isLong: false)), showsIdlePill: true, isYielding: true)
                == .stopsDictation)
    }

    /// The click's events are the chord tap's: down and up at one instant. The first starts a dictation, the second
    /// stops it and the text pastes.
    @Test func twoClicksStartAndStopADictation() async {
        let world = FakeWorld(transcript: "clicked")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordUp)
        #expect(await pipeline.state.phase == .recording(isLong: false))
        await pipeline.handle(.chordDown(.tapOrHold))
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(await world.paster.pasted == ["clicked"])
    }

    /// Review 2.6 bugs #6: a click on the pill during push-to-talk stops the recording, but the chord is still down,
    /// so the paste waits for the real release (else the app gets ⌃⌥⌘V). The classifier sends only chord-down for
    /// that click (`HotkeyClassifier.pillClick`); the real release sends chord-up.
    @Test func aClickDuringPushToTalkPastesAfterTheChordIsReleased() async {
        let world = FakeWorld(transcript: "held")
        let pipeline = world.makePipeline()
        await pipeline.handle(.chordDown(.tapOrHold))
        world.clock.advance(by: .seconds(1))

        // The click while the chord is held.
        await pipeline.handle(.chordDown(.tapOrHold))
        let pastedWhileHeld = await eventually { await world.paster.pasteCount > 0 }
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(pastedWhileHeld == false)
        #expect(await world.paster.pasted == ["held"])
    }
}
