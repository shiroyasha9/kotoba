import Foundation
import Synchronization

@testable import KotobaCore

/// All ports wired to fakes. Tests drive `pipeline` with hotkey events and assert on the fakes.
struct FakeWorld {
    let audio = FakeAudioSource()
    let provider: FakeTranscriptionProvider
    let paster = FakePaster()
    let pasteboard = FakePasteboard()
    let clock = ManualClock()
    let store = FakeStore()

    init(transcript: String) {
        provider = FakeTranscriptionProvider(
            result: .success(Transcript(text: transcript, usage: TranscriptionUsage(audio: .seconds(1), costUSD: nil)))
        )
    }

    func makePipeline() -> DictationPipeline {
        DictationPipeline(
            ports: .init(
                audio: audio,
                provider: provider,
                paster: paster,
                pasteboard: pasteboard,
                clock: clock,
                store: store
            )
        )
    }
}

actor FakeAudioSource: AudioSource {
    private(set) var files: [URL] = []

    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func beginCapture(into file: URL) async throws -> AsyncStream<CaptureEvent> {
        files.append(file)
        let (stream, continuation) = AsyncStream.makeStream(of: CaptureEvent.self)
        self.continuation = continuation
        return stream
    }

    /// The first buffer arrived, captured at `instant`.
    func deliverFirstBuffer(at instant: ContinuousClock.Instant) {
        continuation?.yield(.firstBuffer(at: instant))
    }

    func endCapture() async throws -> RecordedAudio {
        continuation?.finish()
        return RecordedAudio(file: files.last ?? URL(filePath: "/dev/null"), duration: .seconds(1))
    }

    func cancelCapture() async -> RecordedAudio? {
        continuation?.finish()
        return files.last.map { RecordedAudio(file: $0, duration: .seconds(1)) }
    }
}

actor FakeTranscriptionProvider: TranscriptionProvider {
    var result: Result<Transcript, any Error>
    private(set) var requests: [TranscriptionRequest] = []
    private(set) var warmUps = 0

    init(result: Result<Transcript, any Error>) {
        self.result = result
    }

    func warmUp() async {
        warmUps += 1
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        requests.append(request)
        return try result.get()
    }
}

actor FakePaster: Paster {
    private(set) var pasteCount = 0

    func sendPaste() async throws {
        pasteCount += 1
    }
}

actor FakePasteboard: Pasteboard {
    private(set) var changeCount = 0
    private(set) var text: String?
    private(set) var written: [String] = []

    func snapshot() async -> PasteboardSnapshot {
        PasteboardSnapshot(items: text.map { [["public.utf8-plain-text": Data($0.utf8)]] } ?? [])
    }

    func writeTransient(_ text: String) async -> Int {
        self.text = text
        written.append(text)
        changeCount += 1
        return changeCount
    }

    func restore(_ snapshot: PasteboardSnapshot) async {
        text = snapshot.items.first?["public.utf8-plain-text"].flatMap { String(bytes: $0, encoding: .utf8) }
        changeCount += 1
    }

    /// Another app copied something.
    func userCopies(_ text: String) {
        self.text = text
        changeCount += 1
    }
}

/// Time moves only when a test calls `advance(by:)`; sleepers whose deadline passes wake then.
final class ManualClock: PipelineClock {
    private struct State {
        var now = ContinuousClock.Instant.now
        var sleepers: [(deadline: ContinuousClock.Instant, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    func sleep(for duration: Duration) async throws {
        await withCheckedContinuation { continuation in
            state.withLock { $0.sleepers.append(($0.now + duration, continuation)) }
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now += duration
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}

actor FakeStore: Store {
    private(set) var records: [DictationRecord] = []

    func save(_ record: DictationRecord) async throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
    }

    func pendingRetries() async throws -> [DictationRecord] {
        records.filter { $0.status == .failed }
    }

    func prune(olderThan cutoff: Date) async throws {
        records.removeAll { $0.createdAt < cutoff }
    }
}
