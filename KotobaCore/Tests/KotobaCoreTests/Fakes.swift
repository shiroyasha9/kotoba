import Foundation
import Synchronization

@testable import KotobaCore

/// All ports wired to fakes. Tests drive the pipeline with hotkey events and assert on the fakes.
struct FakeWorld {
    let audio = FakeAudioSource()
    let provider: FakeTranscriptionProvider
    let pasteboard: FakePasteboard
    let paster: FakePaster
    let clock = ManualClock()
    let store = FakeStore()
    let frontApp = FakeFrontApp()

    init(transcript: String, clipboard: String? = "user's clipboard", hasPrimer: Bool = true) {
        provider = FakeTranscriptionProvider(transcript: transcript, hasPrimer: hasPrimer)
        pasteboard = FakePasteboard(text: clipboard)
        paster = FakePaster(pasteboard: pasteboard)
    }

    let setup = FakeSetup()

    /// The fake mic sends no levels, so the no-sound deadline (`Settings.noSoundWarning`) stays out of other
    /// tests' way unless a test sets it.
    func makePipeline(noSoundWarning: Duration = .seconds(3_600)) -> DictationPipeline {
        DictationPipeline(
            ports: .init(
                audio: audio,
                provider: provider,
                paster: paster,
                pasteboard: pasteboard,
                clock: clock,
                store: store,
                missingSetup: { [setup] in setup.missing },
                frontApp: { [frontApp] in frontApp.current }
            ),
            settings: .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests"), noSoundWarning: noSoundWarning)
        )
    }
}

struct FakeError: Error {}

/// What the route still needs (a key or an endpoint); nil when it is ready.
final class FakeSetup: Sendable {
    private let value = Mutex<SetupItem?>(nil)

    var missing: SetupItem? {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

actor FakeTranscriptionProvider: TranscriptionProvider {
    private var error: (any Error)?
    private var transcript: String
    private(set) var requests: [TranscriptionRequest] = []
    /// When set, `transcribe` waits for this gate.
    private var gate: Gate?
    /// Gates for single recordings, by audio file.
    private var gates: [URL: Gate] = [:]
    /// The usage each answer reports.
    private var usageAudio: Duration = .seconds(1)
    private var cost: Cost?
    /// The network metrics each answer carries; nil, as on a route without metrics, by default.
    private var network: NetworkTiming?

    init(transcript: String, hasPrimer: Bool = true) {
        self.transcript = transcript
        self.hasPrimer = hasPrimer
    }

    func fail(with error: (any Error)?) {
        self.error = error
    }

    /// Each answer from now on hears `transcript`.
    func hear(_ transcript: String) {
        self.transcript = transcript
    }

    /// Each answer from now on reports `audio` and `cost`.
    func charge(_ cost: Cost?, audio: Duration) {
        self.cost = cost
        usageAudio = audio
    }

    /// Each answer from now on carries `network`.
    func time(_ network: NetworkTiming?) {
        self.network = network
    }

    func hold(at gate: Gate) {
        self.gate = gate
    }

    /// Holds only the request for `audio`.
    func hold(at gate: Gate, onlyFor audio: URL) {
        gates[audio] = gate
    }

    func warmUp() async {}

    /// Whether the route has a primer; false acts as a direct route.
    nonisolated let hasPrimer: Bool
    /// How many primers the pipeline sent, and what each answers: nil (an answer with no cost) by default.
    var primes: Int { primeSizes.count }
    /// Each primer's size, in order.
    private(set) var primeSizes: [PrimerSize] = []
    private var primer: Transcript?
    private var primerGate: Gate?

    /// Each primer from now on answers `primer`, after `gate` opens when one is given.
    func answerPrimes(with primer: Transcript?, after gate: Gate? = nil) {
        self.primer = primer
        primerGate = gate
    }

    /// The most primers that were in flight at once.
    private(set) var maxPrimesInFlight = 0
    private var primesInFlight = 0

    func prime(language: Locale.Language, size: PrimerSize) async -> Transcript? {
        primeSizes.append(size)
        primesInFlight += 1
        maxPrimesInFlight = max(maxPrimesInFlight, primesInFlight)
        await primerGate?.pass()
        primesInFlight -= 1
        return primer
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        requests.append(request)
        await gate?.pass()
        await gates[request.audio]?.pass()
        if let error { throw error }
        return Transcript(
            text: transcript, usage: TranscriptionUsage(audio: usageAudio, cost: cost), model: "fake/model-1",
            network: network)
    }
}

actor FakePaster: Paster {
    private(set) var pasteCount = 0
    /// What the focused app received with each Cmd-V.
    private(set) var pasted: [String] = []
    private var error: (any Error)?
    private let pasteboard: FakePasteboard?

    init(pasteboard: FakePasteboard? = nil) {
        self.pasteboard = pasteboard
    }

    func deny(with error: any Error) {
        self.error = error
    }

    func sendPaste() async throws {
        if let error { throw error }
        pasteCount += 1
        keystrokes.append(.commandV)
        if let text = await pasteboard?.text {
            pasted.append(text)
        }
    }

    enum Keystroke: Equatable { case commandV, returnKey }

    /// Every Cmd-V and Return, in the order the focused app got them.
    private(set) var keystrokes: [Keystroke] = []

    func sendReturn() async throws {
        if let error { throw error }
        keystrokes.append(.returnKey)
    }
}

actor FakePasteboard: Pasteboard {
    private var count = 0
    /// Holds the next `changeCount` read, once, after it took its value.
    private var changeCountGate: Gate?

    var changeCount: Int {
        get async {
            // The value is read first, so a held read returns what was true before the hold.
            let value = count
            if let gate = changeCountGate {
                changeCountGate = nil
                await gate.pass()
            }
            return value
        }
    }

    func holdNextChangeCountRead(at gate: Gate) {
        changeCountGate = gate
    }

    /// The next write changes the contents at once but returns only when `gate` opens.
    private var writeReturnGate: Gate?

    func holdNextWriteReturn(at gate: Gate) {
        writeReturnGate = gate
    }
    private(set) var text: String?
    private(set) var isTransient = false
    /// How many times the full contents were read.
    private(set) var snapshots = 0

    init(text: String? = nil) {
        self.text = text
    }

    /// The clipboard holds more than `PasteboardSnapshot.byteLimit`.
    private var isOverLimit = false

    func holdMoreThanTheLimit() {
        isOverLimit = true
    }

    func snapshot() async -> PasteboardSnapshot {
        snapshots += 1
        if isOverLimit { return PasteboardSnapshot(items: [], isTooLarge: true) }
        return PasteboardSnapshot(items: text.map { [["public.utf8-plain-text": Data($0.utf8)]] } ?? [])
    }

    func write(_ text: String, isTransient transient: Bool) async -> Int {
        self.text = text
        isTransient = transient
        count += 1
        let written = count
        if let gate = writeReturnGate {
            writeReturnGate = nil
            await gate.pass()
        }
        return written
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount changeCount: Int) async {
        guard count == changeCount else { return }
        text = snapshot.items.first?["public.utf8-plain-text"].flatMap { String(bytes: $0, encoding: .utf8) }
        isTransient = false
        count += 1
    }

    /// Another app copied something.
    func userCopies(_ text: String) {
        self.text = text
        isTransient = false
        count += 1
    }
}

/// Time moves only when a test calls `advance(by:)`; sleepers whose deadline passes wake then.
final class ManualClock: PipelineClock {
    private struct Sleeper {
        let id: UUID
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = ContinuousClock.Instant.now
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var sleepers: [Sleeper] = []
        /// Sleeps cancelled before they registered.
        var cancelled: Set<UUID> = []
    }

    private let state = Mutex(State())

    var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    var date: Date {
        state.withLock { $0.date }
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resumeNow = state.withLock { state in
                    guard deadline > state.now, !state.cancelled.contains(id) else { return true }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    /// The deadlines of the timers waiting on this clock.
    var deadlines: [ContinuousClock.Instant] {
        state.withLock { $0.sleepers.map(\.deadline) }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now += duration
            state.date += duration / .seconds(1)
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

/// Yields until `condition` holds, for the few steps that run in tasks the test cannot await. Runs on the caller's actor.
nonisolated(nonsending) func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<10_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

extension DictationPipeline {
    /// Chord down and up within the tap threshold.
    func tap(_ world: FakeWorld) async {
        await handle(.chordDown(.tapOrHold))
        await handle(.chordUp)
    }

    /// Tap to start, tap to stop, then wait for the paste.
    func dictate(_ world: FakeWorld) async {
        await tap(world)
        await tap(world)
        await settle()
    }
}
