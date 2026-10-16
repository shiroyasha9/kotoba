import Foundation
import KotobaCore
import Observation

/// The microphone preference order as the pane shows it: "Your order" holds only mics the owner
/// put there (a menu pick, or Add to Order here); the other connected mics are offered by the Add
/// menu and are never saved by a drag or a remove. So a Bluetooth mic joins the order only when the
/// owner adds it.
@MainActor
@Observable
final class MicrophoneModel {
    struct Row: Identifiable, Equatable {
        let uid: String
        let name: String
        let isConnected: Bool
        /// A Bluetooth mic records in the call profile, so the pane says so.
        var isBluetooth = false

        var id: String { uid }
    }

    /// Where the pane reads devices and reads and writes the order: the live system, or samples for snapshots.
    struct Source {
        var inputs: @MainActor () -> [AudioDevice]
        var entries: @MainActor () -> [MicrophonePreferences.Entry]
        var save: @MainActor ([MicrophonePreferences.Entry]) -> Void
        /// The UID of the mic kotoba records from.
        var current: @MainActor () -> String?
        /// What the menu also warns about the mic in use (a Bluetooth mic).
        var warning: @MainActor () -> MicrophoneWarning? = { nil }
        /// Calls its argument on each device change and each change of the mic in use, until the returned value is
        /// released. Nil: nothing to observe (snapshots).
        var observe: @MainActor (@escaping @MainActor @Sendable () -> Void) -> AnyObject? = { _ in nil }
        /// Starts the mic test, or says why it did not start.
        var test: @MainActor () async -> MicrophoneTest = { .blocked(.noInput) }
        /// Opens Privacy & Security > Microphone, where a denied mic is turned on.
        var openPrivacy: @MainActor () -> Void = {}

        static func live(_ preferences: MicrophonePreferences, audio: AudioCapture, readiness: Readiness) -> Self {
            Self(
                inputs: AudioDevices.inputs,
                entries: { preferences.entries },
                save: { preferences.entries = $0 },
                current: { audio.inputInUse?.uid },
                warning: {
                    InputDevicePolicy.warning(
                        input: audio.inputInUse, outputTransport: AudioDevices.defaultOutputTransport())
                },
                observe: { onChange in
                    LiveObservation(
                        devices: AudioDevices.observe { MainActor.assumeIsolated(onChange) },
                        input: NotificationCenter.default.addObserver(
                            forName: AudioCapture.inputDidChange, object: nil, queue: .main
                        ) { _ in MainActor.assumeIsolated(onChange) })
                },
                test: { await audio.test(for: .seconds(5)) },
                openPrivacy: { readiness.openSettings(.microphone) }
            )
        }

        /// Three sample mics, for snapshots: the built-in one in use and in the order, a Shure in the order but not
        /// connected, and AirPods (Bluetooth) connected but not in the order. `order` and `current` (UIDs) change that.
        @MainActor
        static func sample(
            order: [String] = ["shure", "built-in"], current: String = "built-in", warning: MicrophoneWarning? = nil
        ) -> Self {
            let builtIn = AudioDevice(
                id: 1, uid: "built-in", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
            let airPods = AudioDevice(
                id: 2, uid: "airpods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)
            let names = ["shure": "Shure MV7", "built-in": builtIn.name, "airpods": airPods.name]
            var entries = order.map { MicrophonePreferences.Entry(uid: $0, name: names[$0] ?? $0) }
            return Self(
                inputs: { [builtIn, airPods] }, entries: { entries }, save: { entries = $0 }, current: { current },
                warning: { warning })
        }
    }

    /// The device listeners and the mic-in-use observer of the open pane; both end when this is released.
    private final class LiveObservation {
        let devices: AudioDeviceObservation
        let input: any NSObjectProtocol

        init(devices: AudioDeviceObservation, input: any NSObjectProtocol) {
            self.devices = devices
            self.input = input
        }

        deinit {
            NotificationCenter.default.removeObserver(input)
        }
    }

    private(set) var listed: [Row] = []
    private(set) var others: [Row] = []
    /// The mic in use, by UID.
    private(set) var currentUID: String?
    private(set) var warning: MicrophoneWarning?
    /// The mic test: not run, running with the input level 0...1, or why the last click started nothing.
    enum TestState: Equatable {
        case idle
        case running(level: Float)
        case blocked(MicrophoneTest.Problem)
    }

    private(set) var testState = TestState.idle
    @ObservationIgnored private var test: Task<Void, Never>?
    /// Held while the pane shows, so a closed pane observes nothing.
    @ObservationIgnored private var observation: AnyObject?

    @ObservationIgnored private let source: Source
    @ObservationIgnored private let onChange: @MainActor () -> Void

    /// `onChange` runs after each saved change, so the audio engine can switch mics.
    init(source: Source, onChange: @escaping @MainActor () -> Void) {
        self.source = source
        self.onChange = onChange
        reload()
    }

    func reload() {
        let connected = source.inputs()
        let saved = source.entries()
        let savedUIDs = Set(saved.map(\.uid))
        listed = saved.map { entry in
            let device = connected.first { $0.uid == entry.uid }
            return Row(
                uid: entry.uid, name: device?.name ?? entry.name, isConnected: device != nil,
                isBluetooth: device?.transport == .bluetooth)
        }
        others = connected.filter { !savedUIDs.contains($0.uid) }.map {
            Row(uid: $0.uid, name: $0.name, isConnected: true, isBluetooth: $0.transport == .bluetooth)
        }
        currentUID = source.current()
        warning = source.warning()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        listed.move(fromOffsets: offsets, toOffset: destination)
        save(listed)
    }

    func add(_ row: Row) {
        save(listed + [row])
    }

    func remove(_ uids: Set<Row.ID>) {
        save(listed.filter { !uids.contains($0.uid) })
    }

    /// Records for 5 s and shows the level next to the mic in use (ux-polish MP2). The mic's orange dot shows
    /// meanwhile, as after any click that records.
    func testMicrophone() {
        guard test == nil else { return }
        test = Task {
            switch await source.test() {
            case .running(let levels):
                testState = .running(level: 0)
                for await level in levels {
                    testState = .running(level: level)
                }
                testState = .idle
            case .blocked(let problem):
                testState = .blocked(problem)
            }
            test = nil
        }
    }

    /// The input level while the test runs; nil otherwise.
    var testLevel: Float? {
        if case .running(let level) = testState { level } else { nil }
    }

    func openMicrophonePrivacy() {
        source.openPrivacy()
    }

    /// The pane shows: reads the devices, then reads them again on each change until `disappear()`.
    func appear() {
        reload()
        observation = observation ?? source.observe { [weak self] in self?.reload() }
    }

    /// The pane closed: stops observing, and ends a running test early (the stream's end stops the capture).
    func disappear() {
        observation = nil
        test?.cancel()
    }

    /// Clears the order, so kotoba follows the system default input again.
    func followSystemDefault() {
        save([])
    }

    private func save(_ rows: [Row]) {
        source.save(rows.map { MicrophonePreferences.Entry(uid: $0.uid, name: $0.name) })
        reload()
        onChange()
    }
}

// MARK: - Snapshots

extension MicrophoneModel {
    /// A model in the middle of a mic test, or after a test that did not start, for the snapshot.
    static func testing(_ source: Source, problem: MicrophoneTest.Problem? = nil) -> MicrophoneModel {
        let model = MicrophoneModel(source: source) {}
        model.testState = problem.map(TestState.blocked) ?? .running(level: 0.6)
        return model
    }
}
