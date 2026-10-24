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
    let microphone = FakeMicrophoneAccess()

    /// Returns once `pipeline`'s paste waits for the release of the press made at `press`: the bound on its lost
    /// release (`Settings.chordReleaseWait`) is armed, after the transcript came. From then no paste is a fact.
    func waitForReleaseWait(_ pipeline: DictationPipeline, pressedAt press: ContinuousClock.Instant) async {
        await clock.waitForTimer(at: press + pipeline.settings.chordReleaseWait)
    }

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
                frontApp: { [frontApp] in frontApp.current },
                isMicrophoneAllowed: { [microphone] in microphone.isAllowed }
            ),
            settings: .init(audioDirectory: URL(filePath: "/tmp/kotoba-tests"), noSoundWarning: noSoundWarning)
        )
    }
}

struct FakeError: Error {}

/// `KOTOBA_TEST_SLOW=<yields>` (`make test-slow`): each fake port call yields that many times before it acts, as a busy
/// machine delays the pipeline's tasks. A test that passes only because those tasks ran before its next step (a clock
/// advance before a timer was armed, a check that nothing happened yet) fails under it.
enum Slowness {
    static let yields = ProcessInfo.processInfo.environment["KOTOBA_TEST_SLOW"].flatMap { Int($0) } ?? 0

    static func pause() async {
        for _ in 0..<yields {
            await Task.yield()
        }
    }
}

/// Whether Microphone access is on; tests turn it off as the owner would in System Settings.
final class FakeMicrophoneAccess: Sendable {
    private let value = Mutex(true)

    var isAllowed: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

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
        primerOn = Mutex(hasPrimer)
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

    /// Whether the route has a primer; false acts as a direct route. `switchRoute(hasPrimer:)` changes it, as a route
    /// picked in the menu does.
    private let primerOn: Mutex<Bool>
    nonisolated var hasPrimer: Bool { primerOn.withLock { $0 } }

    nonisolated func switchRoute(hasPrimer: Bool) {
        primerOn.withLock { $0 = hasPrimer }
    }

    /// Whether the route sends the upload copy, so recordings send their segments while they record; true, as MAI
    /// through OpenRouter, by default.
    private let uploadCopyOn = Mutex(true)
    nonisolated var sendsUploadCopy: Bool { uploadCopyOn.withLock { $0 } }

    nonisolated func switchRoute(sendsUploadCopy: Bool) {
        uploadCopyOn.withLock { $0 = sendsUploadCopy }
    }

    /// Answers by request audio file (a segment's), over `transcript`.
    private var heardFor: [URL: String] = [:]
    private var errorFor: [URL: any Error] = [:]
    /// Requests whose task was cancelled while they waited.
    private(set) var cancelled: [URL] = []

    /// The request for `audio` hears `text`.
    func hear(_ text: String, for audio: URL) {
        heardFor[audio] = text
    }

    /// The request for `audio` fails with `error`.
    func fail(_ audio: URL, with error: any Error) {
        errorFor[audio] = error
    }
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
        await Slowness.pause()
        primeSizes.append(size)
        primesInFlight += 1
        maxPrimesInFlight = max(maxPrimesInFlight, primesInFlight)
        await primerGate?.pass()
        primesInFlight -= 1
        return primer
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> Transcript {
        await Slowness.pause()
        requests.append(request)
        await gate?.pass()
        await gates[request.audio]?.pass()
        if Task.isCancelled {
            cancelled.append(request.audio)
            throw CancellationError()
        }
        if let error = errorFor[request.audio] ?? error { throw error }
        return Transcript(
            text: heardFor[request.audio] ?? transcript, usage: TranscriptionUsage(audio: usageAudio, cost: cost),
            model: "fake/model-1", network: network)
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

    /// Runs once, at the next Cmd-V: what the owner does just as it lands.
    private var onNextPaste: (@Sendable () -> Void)?

    func whenPasting(_ action: @escaping @Sendable () -> Void) {
        onNextPaste = action
    }

    /// The focused app reads the clipboard at each Cmd-V, unless it is busy (`readLater`): then the test reads for
    /// it with `FakePasteboard.appReads()`.
    private var isReadingAtOnce = true

    func readLater() {
        isReadingAtOnce = false
    }

    func sendPaste() async throws {
        await Slowness.pause()
        if let error { throw error }
        onNextPaste?()
        onNextPaste = nil
        pasteCount += 1
        keystrokes.append(.commandV)
        if isReadingAtOnce, let text = await pasteboard?.appReads() {
            pasted.append(text)
        }
    }

    enum Keystroke: Equatable {
        case commandV, returnKey
        case backspaces(Int)
    }

    /// Every Cmd-V, Return and run of Backspaces, in the order the focused app got them.
    private(set) var keystrokes: [Keystroke] = []

    func sendReturn() async throws {
        await Slowness.pause()
        if let error { throw error }
        keystrokes.append(.returnKey)
    }

    func sendBackspaces(_ count: Int) async throws {
        await Slowness.pause()
        if let error { throw error }
        keystrokes.append(.backspaces(count))
    }
}

/// Yields until `condition` holds, for the few steps that run in tasks the test cannot await. Runs on the caller's actor.
/// False only after `Gate.limit` of real time: the bound on a test whose event never comes, as a gate never opened. A
/// count of yields was no bound: on a busy machine the pipeline's task did not run during them. Never a way to show
/// that something did not happen: a check that nothing happened waits first for the event that fixes its moment (a
/// timer armed, `ManualClock.waitForTimer`; the due timers run, `DictationPipeline.settleTimers`; a fake's call).
nonisolated(nonsending) func eventually(_ condition: () async -> Bool) async -> Bool {
    let bound = ContinuousClock.now.advanced(by: Gate.limit)
    while ContinuousClock.now < bound {
        if await condition() { return true }
        await Task.yield()
    }
    return await condition()
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
