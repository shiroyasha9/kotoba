import Foundation
import Synchronization
import Testing

@testable import KotobaCore

/// The audio hardware under `AudioCapture`: devices the test connects and removes, inputs that open, start or fail as
/// the test says, and recorders that note how they were stopped. Its device, route and settling events go to the
/// capture as CoreAudio's would.
final class FakeCaptureHardware: CaptureHardware {
    static let builtIn = AudioDevice(
        id: 1, uid: "built-in", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
    static let usb = AudioDevice(id: 2, uid: "usb", name: "Shure MV7", transport: .usb, hasInput: true)
    static let airPods = AudioDevice(id: 3, uid: "airpods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)

    /// A listener the capture holds; the fake calls it only while the capture keeps the token.
    private final class Token: Sendable {}

    /// Not retained: the capture's release of a token or an input ends it, as CoreAudio's listeners end.
    private struct Weak<Object: AnyObject> {
        weak var object: Object?
    }

    private struct Watch {
        let token: Weak<Token>
        let uid: String
        let onChange: @Sendable () -> Void
    }

    private struct State {
        var devices: [AudioDevice]
        var defaultInput: AudioDevice?
        var order: [String] = []
        var sampleRates: [String: Double] = [:]
        /// By device UID: the errors the next opens throw, first first.
        var openFailures: [String: [any Error]] = [:]
        /// By device UID: how many of its next inputs fail their first start.
        var startFailures: [String: Int] = [:]
        /// The inputs the capture holds; one it released is closed, as CoreAudio would close it.
        var inputs: [Weak<FakeCaptureInput>] = []
        var opened: [String] = []
        var recorders: [FakeCaptureRecorder] = []
        var observers: [(token: Weak<Token>, onChange: @Sendable (AudioDeviceChange) -> Void)] = []
        var settling: [Watch] = []
        var holdsRateSwitch = false
        var writesUploadCopies = false
        var deviceReads = 0
    }

    private let state: Mutex<State>

    init(devices: [AudioDevice] = [builtIn], defaultInput: AudioDevice? = builtIn) {
        state = Mutex(State(devices: devices, defaultInput: defaultInput))
    }

    // MARK: What the capture saw

    /// The inputs open now (the capture holds them), oldest first.
    var inputs: [FakeCaptureInput] { state.withLock { $0.inputs.compactMap(\.object) } }
    var recorders: [FakeCaptureRecorder] { state.withLock { $0.recorders } }
    /// The UIDs of the devices whose inputs were opened, in order, closed ones too.
    var opened: [String] { state.withLock { $0.opened } }
    /// The input that runs now, if any.
    var running: FakeCaptureInput? { inputs.last { $0.isRunning } }
    /// How often the capture read the device list: once per input build or device check.
    var deviceReads: Int { state.withLock { $0.deviceReads } }
    /// The devices watched for the end of their change.
    var watchedForSettling: [String] {
        state.withLock { $0.settling.filter { $0.token.object != nil }.map(\.uid) }
    }

    // MARK: What the test does

    func setOrder(_ order: [String]) {
        state.withLock { $0.order = order }
    }

    /// Opens of `device` throw these errors, one per open, before an open succeeds.
    func failOpens(of device: AudioDevice, with errors: [any Error]) {
        state.withLock { $0.openFailures[device.uid] = errors }
    }

    /// The next `inputs` inputs opened on `device` fail their first start, as a unit of a restarted audio service.
    func failStarts(of device: AudioDevice, inputs: Int = 1) {
        state.withLock { $0.startFailures[device.uid] = inputs }
    }

    func setSampleRate(_ rate: Double, of device: AudioDevice) {
        state.withLock { $0.sampleRates[device.uid] = rate }
    }

    /// Recorders made from now on wait in `switchSampleRate` until they stop or the test calls `releaseRateSwitch`.
    /// From now on each recorder writes its Opus upload copy where the capture says, at the close
    /// (`RecordedAudio.upload`), as the app's recorder does.
    func writeUploadCopies() {
        state.withLock { $0.writesUploadCopies = true }
    }

    func holdRateSwitches() {
        state.withLock { $0.holdsRateSwitch = true }
    }

    /// The device connects; with no default input, macOS makes it the default.
    func connect(_ device: AudioDevice) {
        state.withLock { state in
            state.devices.append(device)
            if state.defaultInput == nil { state.defaultInput = device }
        }
        report(.devices)
    }

    /// The device goes away: it leaves the list, and its open inputs report the route change.
    func disconnect(_ device: AudioDevice) {
        let inputs = state.withLock { state in
            state.devices.removeAll { $0.uid == device.uid }
            if state.defaultInput?.uid == device.uid { state.defaultInput = state.devices.first }
            return state.inputs.compactMap(\.object).filter { $0.device.uid == device.uid }
        }
        for input in inputs { input.changeRoute() }
        report(.devices)
    }

    /// coreaudiod restarted.
    func restartService() {
        report(.serviceRestarted)
    }

    /// `device` ended its rate or format change: the watch on it fires once.
    func finishChange(of device: AudioDevice) {
        let fired = state.withLock { state in
            defer { state.settling.removeAll { $0.uid == device.uid } }
            return state.settling.filter { $0.uid == device.uid && $0.token.object != nil }.map(\.onChange)
        }
        for onChange in fired { onChange() }
    }

    private func report(_ change: AudioDeviceChange) {
        let observers = state.withLock { $0.observers.filter { $0.token.object != nil }.map(\.onChange) }
        for observer in observers { observer(change) }
    }

    // MARK: CaptureHardware

    func devices() -> [AudioDevice] {
        state.withLock { state in
            state.deviceReads += 1
            return state.devices
        }
    }

    func defaultInput() -> AudioDevice? { state.withLock { $0.defaultInput } }

    func microphoneOrder() -> [String] { state.withLock { $0.order } }

    func observeDevices(_ onChange: @escaping @Sendable (AudioDeviceChange) -> Void) -> AnyObject {
        let token = Token()
        state.withLock { $0.observers.append((Weak(object: token), onChange)) }
        return token
    }

    func openInput(on device: AudioDevice, onRouteChange: @escaping @Sendable () -> Void) throws -> any CaptureInput {
        try state.withLock { state in
            if var failures = state.openFailures[device.uid], !failures.isEmpty {
                let failure = failures.removeFirst()
                state.openFailures[device.uid] = failures
                throw failure
            }
            let failingInputs = state.startFailures[device.uid] ?? 0
            state.startFailures[device.uid] = max(0, failingInputs - 1)
            let input = FakeCaptureInput(
                device: device, sampleRate: state.sampleRates[device.uid] ?? 48_000,
                failingStarts: failingInputs > 0 ? 1 : 0, onRouteChange: onRouteChange)
            state.inputs.append(Weak(object: input))
            state.opened.append(device.uid)
            return input
        }
    }

    func watchSettling(of device: AudioDevice, onChange: @escaping @Sendable () -> Void) -> AnyObject {
        let token = Token()
        state.withLock { $0.settling.append(Watch(token: Weak(object: token), uid: device.uid, onChange: onChange)) }
        return token
    }

    func markCaptureStart() -> Int { 0 }

    func makeRecorder(
        files: CaptureFiles,
        sampleRate: Double,
        readingFrom position: Int,
        events: AsyncStream<CaptureEvent>.Continuation,
        levels: AsyncStream<Float>.Continuation
    ) throws -> any CaptureRecorder {
        state.withLock { state in
            let recorder = FakeCaptureRecorder(
                file: files.recording, sampleRate: sampleRate, events: events, holdsRateSwitch: state.holdsRateSwitch,
                upload: state.writesUploadCopies ? files.upload : nil)
            state.recorders.append(recorder)
            return recorder
        }
    }
}

/// A mic input: running or not, and how often it started.
final class FakeCaptureInput: CaptureInput, Sendable {
    private struct State {
        var isRunning = false
        var failingStarts: Int
    }

    struct StartFailure: Error {}

    let device: AudioDevice
    let sampleRate: Double
    private let onRouteChange: @Sendable () -> Void
    private let state: Mutex<State>

    init(device: AudioDevice, sampleRate: Double, failingStarts: Int, onRouteChange: @escaping @Sendable () -> Void) {
        self.device = device
        self.sampleRate = sampleRate
        self.onRouteChange = onRouteChange
        state = Mutex(State(failingStarts: failingStarts))
    }

    var isRunning: Bool { state.withLock { $0.isRunning } }

    /// The next start fails, as when the device went away while the mic was off.
    func failNextStart() {
        state.withLock { $0.failingStarts = 1 }
    }

    /// The device's rate changed or it died.
    func changeRoute() {
        onRouteChange()
    }

    func start() throws {
        try state.withLock { state in
            if state.failingStarts > 0 {
                state.failingStarts -= 1
                throw StartFailure()
            }
            state.isRunning = true
        }
    }

    func stop() {
        state.withLock { $0.isRunning = false }
    }
}

/// A capture's recorder: the rates it switched to and how it stopped.
final class FakeCaptureRecorder: CaptureRecorder {
    enum Stop: Equatable {
        /// After the hardware cycle that holds the stop moment.
        case afterCycle
        case now
    }

    private struct State {
        var rates: [Double]
        var stops: [Stop] = []
        var isStarted = false
    }

    let file: URL
    /// The upload copy it writes at the close, when it writes one.
    let upload: URL?
    private let events: AsyncStream<CaptureEvent>.Continuation
    /// Holds rate switches until the test releases them or the file closes; nil: they return at once.
    private let rateSwitchGate: Gate?
    private let state: Mutex<State>

    init(
        file: URL, sampleRate: Double, events: AsyncStream<CaptureEvent>.Continuation, holdsRateSwitch: Bool,
        upload: URL? = nil
    ) {
        self.file = file
        self.upload = upload
        self.events = events
        rateSwitchGate = holdsRateSwitch ? Gate() : nil
        state = Mutex(State(rates: [sampleRate]))
    }

    /// The first rate, then each switch.
    var rates: [Double] { state.withLock { $0.rates } }
    var stops: [Stop] { state.withLock { $0.stops } }
    var isStarted: Bool { state.withLock { $0.isStarted } }

    /// A rate switch waits for `releaseRateSwitch`.
    var hasHeldSwitch: Bool {
        get async { await rateSwitchGate?.hasWaiters ?? false }
    }

    /// The held rate switches return: the audio at the old rate is written.
    func releaseRateSwitch() async {
        await rateSwitchGate?.open()
    }

    func start() {
        state.withLock { $0.isStarted = true }
    }

    nonisolated(nonsending) func stop() async -> RecordedAudio {
        await close(.afterCycle)
    }

    func stopNow() async -> RecordedAudio {
        await close(.now)
    }

    func switchSampleRate(to sampleRate: Double) async {
        state.withLock { $0.rates.append(sampleRate) }
        await rateSwitchGate?.pass()
    }

    /// As the real recorder: closing returns a rate switch that waits, and later ones at once, and finishes the events.
    private func close(_ stop: Stop) async -> RecordedAudio {
        state.withLock { $0.stops.append(stop) }
        await rateSwitchGate?.open()
        events.finish()
        if let upload {
            try? FileManager.default.createDirectory(
                at: upload.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: upload.path, contents: Data("OggS".utf8))
        }
        return RecordedAudio(file: file, duration: .seconds(1), upload: upload)
    }
}

/// The elements of `stream` once it finishes; nil, with an issue, when it does not finish within `eventually`'s bound.
func finished<Element: Sendable>(_ stream: AsyncStream<Element>) async -> [Element]? {
    let seen = Mutex<[Element]?>(nil)
    let drain = Task {
        var all: [Element] = []
        for await element in stream { all.append(element) }
        seen.withLock { [all] in $0 = all }
    }
    guard await eventually({ seen.withLock { $0 != nil } }) else {
        drain.cancel()
        Issue.record("The stream did not finish")
        return nil
    }
    return seen.withLock { $0 }
}
