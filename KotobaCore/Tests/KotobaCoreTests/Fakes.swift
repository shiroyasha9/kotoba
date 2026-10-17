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
        if let error { throw error }
        keystrokes.append(.returnKey)
    }

    func sendBackspaces(_ count: Int) async throws {
        if let error { throw error }
        keystrokes.append(.backspaces(count))
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
        return text.map(PasteboardSnapshot.plainText) ?? PasteboardSnapshot(items: [])
    }

    /// Called at the first read of the transient text on the pasteboard now.
    private var onRead: (@Sendable () -> Void)?

    /// An app reads the clipboard (a paste target at its Cmd-V); the first read of a transient text tells its writer.
    @discardableResult
    func appReads() -> String? {
        onRead?()
        onRead = nil
        return text
    }

    func write(_ text: String) async -> Int {
        await write(text, isTransient: false, onRead: nil)
    }

    /// A clipboard manager that ignores the transient marker reads each transient text as it is written.
    private var isManagerReading = false

    func readEachWriteAsAManager() {
        isManagerReading = true
    }

    /// Runs once, at the next transient write: what the owner does between the write and the Cmd-V.
    private var onNextTransientWrite: (@Sendable () -> Void)?

    func whenWritingTransient(_ action: @escaping @Sendable () -> Void) {
        onNextTransientWrite = action
    }

    func writeTransient(_ text: String, onRead: @escaping @Sendable () -> Void) async -> Int {
        let written = await write(text, isTransient: true, onRead: onRead)
        onNextTransientWrite?()
        onNextTransientWrite = nil
        if isManagerReading { appReads() }
        return written
    }

    private func write(_ text: String, isTransient transient: Bool, onRead: (@Sendable () -> Void)?) async -> Int {
        self.text = text
        isTransient = transient
        self.onRead = onRead
        count += 1
        let written = count
        if let gate = writeReturnGate {
            writeReturnGate = nil
            await gate.pass()
        }
        return written
    }

    func restore(_ snapshot: PasteboardSnapshot, ifChangeCount changeCount: Int) async -> Bool {
        guard count == changeCount else { return false }
        text = snapshot.items.first?.first { $0.type == PasteboardSnapshot.plainTextType }
            .flatMap { String(bytes: $0.data, encoding: .utf8) }
        isTransient = false
        onRead = nil
        count += 1
        return true
    }

    /// Another app copied something.
    func userCopies(_ text: String) {
        self.text = text
        isTransient = false
        onRead = nil
        count += 1
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
