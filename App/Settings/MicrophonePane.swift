import KotobaCore
import Observation
import SwiftUI

extension SettingsPane {
    static func microphones(_ model: MicrophoneModel) -> Self {
        SettingsPane(id: .microphones, title: "Microphone", systemImage: "mic") {
            AnyView(MicrophonePane(model: model))
        }
    }
}

/// The microphone preference order as the pane shows it: "Your order" holds only mics the owner
/// put there (a menu pick, or Add to Order here); "Other connected" lists the rest and is never
/// saved by a drag or a remove. So a Bluetooth mic joins the order only when the owner adds it.
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
        /// Starts the mic test; the stream yields the input level until the test ends.
        var testLevels: @MainActor () async -> AsyncStream<Float> = { AsyncStream { $0.finish() } }

        static func live(_ preferences: MicrophonePreferences, audio: AudioCapture) -> Self {
            Self(
                inputs: AudioDevices.inputs,
                entries: { preferences.entries },
                save: { preferences.entries = $0 },
                current: { audio.inputInUse?.uid },
                testLevels: { await audio.testLevels(for: .seconds(5)) }
            )
        }

        /// Three sample mics, for snapshots: the built-in one in use and in the order, a Shure in the order but not
        /// connected, and AirPods (Bluetooth) connected but not in the order.
        @MainActor
        static func sample() -> Self {
            let builtIn = AudioDevice(
                id: 1, uid: "built-in", name: "MacBook Pro Microphone", transport: .builtIn, hasInput: true)
            let airPods = AudioDevice(
                id: 2, uid: "airpods", name: "AirPods Pro", transport: .bluetooth, hasInput: true)
            var entries = [
                MicrophonePreferences.Entry(uid: "shure", name: "Shure MV7"),
                MicrophonePreferences.Entry(uid: "built-in", name: "MacBook Pro Microphone"),
            ]
            return Self(
                inputs: { [builtIn, airPods] }, entries: { entries }, save: { entries = $0 }, current: { "built-in" })
        }
    }

    private(set) var listed: [Row] = []
    private(set) var others: [Row] = []
    /// The mic in use, by UID.
    private(set) var currentUID: String?
    /// The input level 0...1 while the mic test runs; nil otherwise.
    private(set) var testLevel: Float?
    @ObservationIgnored private var test: Task<Void, Never>?

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
    }

    func move(from offsets: IndexSet, to destination: Int) {
        listed.move(fromOffsets: offsets, toOffset: destination)
        save(listed)
    }

    func add(_ row: Row) {
        save(listed + [row])
    }

    func remove(_ row: Row) {
        save(listed.filter { $0 != row })
    }

    /// Records for 5 s and shows the level next to the mic in use (ux-polish MP2). The mic's orange dot shows
    /// meanwhile, as after any click that records.
    func testMicrophone() {
        guard test == nil else { return }
        testLevel = 0
        test = Task {
            for await level in await source.testLevels() {
                testLevel = level
            }
            testLevel = nil
            test = nil
        }
    }

    /// Ends a running test early (the pane closed); the stream's end stops the capture.
    func stopTest() {
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

private struct MicrophonePane: View {
    @Bindable var model: MicrophoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List {
                Section {
                    ForEach(model.listed) { row in
                        MicrophoneRow(row: row, isCurrent: row.uid == model.currentUID, level: model.testLevel)
                            .contextMenu {
                                Button("Remove from Order", role: .destructive) { model.remove(row) }
                            }
                    }
                    .onMove(perform: model.move)
                    if model.listed.isEmpty {
                        Text("No mics in your order: kotoba follows the system default input.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your Order")
                } footer: {
                    Text("kotoba uses the first connected mic in this list. Drag to change the order.")
                        .font(.callout)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
                if !model.others.isEmpty {
                    Section("Other Connected") {
                        ForEach(model.others) { row in
                            MicrophoneRow(row: row, isCurrent: row.uid == model.currentUID, level: model.testLevel) {
                                model.add(row)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Test Microphone", action: model.testMicrophone)
                    .disabled(model.testLevel != nil)
                Spacer()
                Button("Follow System Default", action: model.followSystemDefault)
                    .disabled(model.listed.isEmpty)
            }
            .padding(12)
        }
        .onAppear(perform: model.reload)
        .onDisappear(perform: model.stopTest)
    }
}

private struct MicrophoneRow: View {
    let row: MicrophoneModel.Row
    let isCurrent: Bool
    /// The mic test's level, shown on the mic in use while the test runs.
    var level: Float?
    /// A listed row shows a drag handle; another connected mic shows Add instead.
    var onAdd: (() -> Void)?

    var body: some View {
        HStack {
            // A plain checkmark marks the mic in use; the rows are an order, not a choice.
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .opacity(isCurrent ? 1 : 0)
                .accessibilityLabel(isCurrent ? "In use" : "")
            Text(row.name)
                .foregroundStyle(row.isConnected ? .primary : .secondary)
            Spacer()
            if isCurrent, let level {
                // A live level, like the pill's meter, not a progress bar.
                Capsule()
                    .fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(nsColor: .systemGreen))
                            .frame(width: 80 * CGFloat(min(max(level, 0), 1)))
                    }
                    .frame(width: 80, height: 6)
                    .animation(.linear(duration: 0.1), value: level)
                    .accessibilityLabel("Input level")
            }
            if !row.isConnected {
                Text("Not connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if row.isBluetooth {
                Text("Bluetooth: lower quality while recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let onAdd {
                Button("Add", action: onAdd)
                    .controlSize(.small)
            } else {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }
}

@MainActor
extension SettingsPane {
    static func microphoneSnapshots() -> [Snapshot] {
        let source = MicrophoneModel.Source.sample()
        return [
            SettingsWindow.snapshot(of: .microphones(MicrophoneModel(source: source) {}), named: "settings-microphone"),
            SettingsWindow.snapshot(of: .microphones(.testing(source)), named: "settings-microphone-test"),
        ]
    }
}

extension MicrophoneModel {
    /// A model in the middle of a mic test, for the snapshot.
    static func testing(_ source: Source) -> MicrophoneModel {
        let model = MicrophoneModel(source: source) {}
        model.testLevel = 0.6
        return model
    }
}
