import KotobaCore
import Observation
import SwiftUI

extension Pane {
    static func microphones(_ model: MicrophoneModel) -> Self {
        Pane(id: .microphones) {
            AnyView(MicrophonePane(model: model))
        }
    }
}

/// The ranked list of mics, the Bluetooth switch, and the mic test (docs/research/ui-redesign.md, "Microphone"). Each
/// row's status follows the device and mic-in-use events while the page shows (`MicrophoneModel.appear`).
private struct MicrophonePane: View {
    @Bindable var model: MicrophoneModel

    var body: some View {
        PageForm {
            Section {
                PageHeader(
                    page: .microphones,
                    summary: "kotoba records from the first connected microphone in the list.")
            }
            if let warning = model.warning {
                Section {
                    PageRow(title: StatusText.title(warning), subtitle: StatusText.detail(warning)) {
                        SymbolTile(
                            systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
                    } trailing: {
                    }
                }
            }
            Section {
                EditableList(
                    rows: model.listed,
                    emptyText: emptyText,
                    addTitle: "Add to List",
                    addHelp: model.others.isEmpty
                        ? "No other microphones are connected" : "Add a connected microphone to the list",
                    isAddDisabled: model.others.isEmpty, removeTitle: "Remove from List", remove: model.remove,
                    move: model.move
                ) { row in
                    LabeledContent {
                        Text(status(of: row)).foregroundStyle(.secondary)
                    } label: {
                        Text(row.name).foregroundStyle(row.isConnected ? .primary : .secondary)
                    }
                } addItems: {
                    ForEach(model.others) { row in
                        Button {
                            model.add(row)
                        } label: {
                            Text(row.name)
                            if row.isBluetooth {
                                Text(StatusText.bluetoothMicNote)
                            }
                        }
                    }
                } accessory: {
                    // Clears the list, so it sits with the buttons that change it.
                    Button("Clear List", action: model.followSystemDefault)
                        .labelStyle(.titleOnly)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.listed.isEmpty)
                }
            } header: {
                Text("Microphone Order")
            } footer: {
                Text("Drag to change the order.")
            }
            Section {
                PageToggle(
                    title: "Use Bluetooth microphones only from the list",
                    // Why, not the quality note again: the warning above says that while one is in use.
                    subtitle: "So kotoba does not record from headphones you connect only to listen.",
                    isOn: $model.isBluetoothOnlyWhenListed)
            }
            Section {
                PageRow(title: "Input level", subtitle: nil) {
                    HStack {
                        InputLevelMeter(level: Double(min(max(model.testLevel ?? 0, 0), 1)))
                        Button("Test Microphone", action: model.testMicrophone)
                            .disabled(model.testLevel != nil)
                    }
                }
                if case .blocked(let problem) = model.testState {
                    TestProblemRow(problem: problem, openPrivacy: model.openMicrophonePrivacy)
                }
            } footer: {
                // Before a test the footer says what the click does, so the bar at rest is not read as broken; a quiet
                // room moves the bar little, so the running test says so.
                if model.testLevel != nil {
                    Text("Testing for \(MicrophoneModel.testSeconds) seconds. Speak to see the level.")
                } else {
                    Text("Records \(MicrophoneModel.testSeconds) seconds from the microphone in use and keeps nothing.")
                }
            }
        }
        .onAppear(perform: model.appear)
        .onDisappear(perform: model.disappear)
    }

    /// What an empty list means: the switch keeps a Bluetooth input chosen in System Settings out.
    private var emptyText: String {
        let rule = "No microphones in the list. kotoba uses the input chosen in System Settings"
        return model.isBluetoothOnlyWhenListed
            ? rule + ", or another microphone when that input is Bluetooth." : rule + "."
    }

    /// "In use", "Not connected" and the Bluetooth note, the ones that apply.
    private func status(of row: MicrophoneModel.Row) -> String {
        var parts: [String] = []
        if row.uid == model.currentUID {
            parts.append("In use")
        }
        if !row.isConnected {
            parts.append("Not connected")
        } else if row.isBluetooth, !(row.uid == model.currentUID && model.warning != nil) {
            // The warning above the list already says it for the mic in use.
            parts.append(StatusText.bluetoothMicNote)
        }
        return parts.joined(separator: " · ")
    }
}

/// Why Test Microphone started nothing, with the fix when there is one.
private struct TestProblemRow: View {
    let problem: MicrophoneTest.Problem
    let openPrivacy: () -> Void

    var body: some View {
        switch problem {
        case .notAllowed:
            HStack {
                StatusLine(Readiness.Missing.microphone.problemText, .problem)
                Spacer()
                Button("Open System Settings…", action: openPrivacy)
            }
        case .dictating:
            StatusLine("A dictation is recording. Test again when it ends.", .problem)
        case .noInput:
            StatusLine("Couldn’t open the microphone. Check that it’s connected, then test again.", .problem)
        case .bluetoothNotListed(let name):
            StatusLine("Not in the list: \(name). Add it with +, then test again.", .problem)
        }
    }
}

@MainActor
extension Pane {
    static func microphoneSnapshots() -> [Snapshot] {
        let source = MicrophoneModel.Source.sample()
        return [
            MainWindow.snapshot(of: .microphones(MicrophoneModel(source: source) {}), named: "settings-microphone"),
            MainWindow.snapshot(of: .microphones(.testing(source)), named: "settings-microphone-test"),
            MainWindow.snapshot(
                of: .microphones(.testing(source, problem: .notAllowed)),
                named: "settings-microphone-test-not-allowed"),
            MainWindow.snapshot(
                of: .microphones(.testing(source, problem: .bluetoothNotListed("Alex’s AirPods Pro"))),
                named: "settings-microphone-test-bluetooth-not-listed"),
            MainWindow.snapshot(
                of: .microphones(MicrophoneModel(source: .sample(order: [])) {}), named: "settings-microphone-empty"),
            MainWindow.snapshot(
                of: .microphones(
                    MicrophoneModel(
                        source: .sample(
                            order: ["airpods", "built-in"], current: "airpods",
                            warning: .bluetoothMic(interruptsPlayback: true))
                    ) {}),
                named: "settings-microphone-bluetooth"),
            MainWindow.snapshot(
                of: .microphones(MicrophoneModel(source: .sample(bluetoothOnlyWhenListed: false)) {}),
                named: "settings-microphone-bluetooth-switch-off"),
        ]
    }
}

/// The input level as Sound > Input draws it: a row of segments, all empty at rest. Custom: SwiftUI's gauge and linear
/// progress bar draw a filled cap at zero, which read as a level with nothing to hear (qa1-review, Microphone);
/// `NSLevelIndicator` is the system's meter.
private struct InputLevelMeter: NSViewRepresentable {
    /// 0 to 1.
    let level: Double

    /// Segments in the meter, as Sound > Input's.
    private static let segments = 15.0

    func makeNSView(context: Context) -> NSLevelIndicator {
        let meter = NSLevelIndicator()
        meter.levelIndicatorStyle = .discreteCapacity
        meter.minValue = 0
        meter.maxValue = Self.segments
        return meter
    }

    func updateNSView(_ meter: NSLevelIndicator, context: Context) {
        meter.doubleValue = level * Self.segments
    }

    /// The meter's own height, and segments half as wide as tall, as Sound > Input's (a representable otherwise takes
    /// all it is offered).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView meter: NSLevelIndicator, context: Context) -> CGSize? {
        let height = meter.fittingSize.height
        return CGSize(width: min(proposal.width ?? .infinity, Self.segments * height / 2), height: height)
    }
}
