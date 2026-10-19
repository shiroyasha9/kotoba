import Foundation

/// What a click on Test Microphone started, or why it started nothing.
public enum MicrophoneTest: Sendable {
    public enum Problem: Sendable {
        case notAllowed
        /// A dictation records; the test would take its mic.
        case dictating
        /// No mic opened, or it did not start (logged).
        case noInput
    }

    /// The input level 0...1, about ten times a second, until the test ends.
    case running(AsyncStream<Float>)
    case blocked(Problem)
}

extension AudioCapture {
    /// The Settings mic test (ux-polish MP2): records `duration` through the dictation's input into a throwaway file and
    /// yields the input level until it ends, so it shows what a dictation would record. It does not start while a
    /// dictation records, or when no mic opens; it says which, so the pane never shows a click that did nothing. A
    /// dictation ends it.
    public func beginTest(for duration: Duration) -> MicrophoneTest {
        guard capture == nil else { return blocked(.dictating) }
        let (levels, continuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        let file = URL.temporaryDirectory.appending(path: "kotoba-microphone-test-\(UUID().uuidString).flac")
        do {
            _ = try startCapture(into: file, levels: continuation)
        } catch {
            Log.audio.error("The mic test did not start: \(error)")
            return .blocked(.noInput)
        }
        Log.audio.notice("The mic test started on \(self.currentInput?.name ?? "no mic", privacy: .public)")
        // A reader that stops early (the pane closed) ends the test; `endTest` does nothing when it already ran.
        continuation.onTermination = { _ in Task { await self.endTest() } }
        let deadline = clock.now + duration
        let timer = Task { [clock] in
            // Cancelled only by an earlier end, which has done the work.
            guard (try? await clock.sleep(until: deadline)) != nil else { return }
            await self.endTest()
        }
        micTest = MicTest(levels: continuation, timer: timer)
        return .running(levels)
    }

    private func blocked(_ problem: MicrophoneTest.Problem) -> MicrophoneTest {
        Log.audio.notice("The mic test did not start: \(String(describing: problem), privacy: .public)")
        return .blocked(problem)
    }

    func endTest() async {
        guard let micTest else { return }
        self.micTest = nil
        micTest.timer.cancel()
        await discardCapture()
        micTest.levels.finish()
    }
}
