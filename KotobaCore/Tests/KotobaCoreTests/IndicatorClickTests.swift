import Testing

@testable import KotobaCore

/// A click on the indicator pill body is a chord tap (start or stop) only where the pill offers it.
struct IndicatorClickTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let state: DictationState
        let showsIdlePill: Bool
        let isTap: Bool

        var testDescription: String { "\(state), idle pill: \(showsIdlePill)" }
    }

    static let id = DictationID()

    static let rows: [Row] = [
        Row(state: .recording(isLong: false), showsIdlePill: false, isTap: true),
        Row(state: .recording(isLong: false), showsIdlePill: true, isTap: true),
        Row(state: .recording(isLong: true), showsIdlePill: false, isTap: true),
        Row(state: .recording(isLong: false, isSilent: true), showsIdlePill: false, isTap: true),
        Row(state: .idle, showsIdlePill: true, isTap: true),
        Row(state: .idle, showsIdlePill: false, isTap: false),
        Row(state: .transcribing, showsIdlePill: true, isTap: false),
        Row(state: .undoable, showsIdlePill: true, isTap: false),
        Row(state: .failed(id), showsIdlePill: true, isTap: false),
        Row(state: .copied(id), showsIdlePill: false, isTap: false),
    ]

    @Test(arguments: rows)
    func aClickIsATapOnlyOnTheRecordingAndIdlePills(_ row: Row) {
        #expect(IndicatorPlacement.isClickATap(in: row.state, showsIdlePill: row.showsIdlePill) == row.isTap)
    }

    /// The click's events are the chord tap's: down and up at one instant. The first starts a dictation, the second
    /// stops it and the text pastes.
    @Test func twoClicksStartAndStopADictation() async {
        let world = FakeWorld(transcript: "clicked")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordUp)
        #expect(await pipeline.state == .recording(isLong: false))
        await pipeline.handle(.chordDown)
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
        await pipeline.handle(.chordDown)
        world.clock.advance(by: .seconds(1))

        // The click while the chord is held.
        await pipeline.handle(.chordDown)
        let pastedWhileHeld = await eventually { await world.paster.pasteCount > 0 }
        await pipeline.handle(.chordUp)
        await pipeline.settle()

        #expect(pastedWhileHeld == false)
        #expect(await world.paster.pasted == ["held"])
    }
}
