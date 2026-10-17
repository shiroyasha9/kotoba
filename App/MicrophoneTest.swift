import AVFAudio
import Foundation
import KotobaCore

/// The mic test records through the dictation's input and ring, so it shows what a dictation would record.
extension AudioCapture {
    /// The Settings mic test (ux-polish MP2): records `duration` into a throwaway file and yields the input level
    /// until it ends. It does not start when the mic is not allowed (no prompt from Settings), a dictation records, or
    /// no mic opens; it says which, so the pane never shows a click that did nothing.
    func test(for duration: Duration) -> MicrophoneTest {
        guard Readiness.Microphone.current == .allowed else { return blocked(.notAllowed) }
        guard writer == nil else { return blocked(.dictating) }
        let (levels, continuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        let file = URL.temporaryDirectory.appending(path: "kotoba-microphone-test-\(UUID().uuidString).flac")
        do {
            _ = try startCapture(into: file, levels: continuation)
        } catch {
            Log.audio.error("The mic test did not start: \(error)")
            return .blocked(.noInput)
        }
        Log.audio.notice("The mic test started on \(self.currentInput?.name ?? "no mic", privacy: .public)")
        testLevels = continuation
        // A reader that stops early (the pane closed) ends the test; `endTest` does nothing when it already ran.
        continuation.onTermination = { _ in Task { await self.endTest() } }
        testTimer = Task {
            // Cancelled only by an earlier end, which has done the work.
            guard (try? await Task.sleep(for: duration)) != nil else { return }
            await endTest()
        }
        return .running(levels)
    }

    private func blocked(_ problem: MicrophoneTest.Problem) -> MicrophoneTest {
        Log.audio.notice("The mic test did not start: \(String(describing: problem), privacy: .public)")
        return .blocked(problem)
    }

    func endTest() async {
        guard let testLevels else { return }
        self.testLevels = nil
        testTimer?.cancel()
        testTimer = nil
        await discardCapture()
        testLevels.finish()
    }
}

/// What a click on Test Microphone started, or why it started nothing.
enum MicrophoneTest: Sendable {
    enum Problem: Sendable {
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
