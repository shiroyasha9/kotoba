import Testing

@testable import KotobaCore

/// Style: hotkey events in, outcomes out (text pasted, clipboard restored, audio kept,
/// latency recorded). Assert on what the fakes saw, never on the pipeline's private state.
struct DictationPipelineTests {
    @Test func tapToStartThenTapToStopPastesTheTranscript() async {
        let world = FakeWorld(transcript: "run make check")
        let pipeline = world.makePipeline()

        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordUp)
        await pipeline.handle(.chordDown)
        await pipeline.handle(.chordUp)

        // Remove `withKnownIssue` when phase 1 builds the state machine; the test must then pass as is.
        await withKnownIssue("Phase 1: hotkey state machine not built yet") {
            #expect(await world.pasteboard.written == ["run make check"])
            #expect(await world.paster.pasteCount == 1)
        }
    }
}
