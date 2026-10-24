// 0.5.0 ratchet: the Microphone page's rollout puts this file on the page system and removes the next line.
// swiftlint:disable row_is_page_row page_form
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

private struct MicrophonePane: View {
    @Bindable var model: MicrophoneModel

    var body: some View {
        Form {
            Section {
                if let warning = model.warning {
                    Label {
                        Text(StatusText.title(warning))
                        Text(StatusText.detail(warning))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").symbolRenderingMode(.multicolor)
                    }
                }
                EditableList(
                    rows: model.listed, emptyText: "No mics in your order: kotoba follows the system default input.",
                    addTitle: "Add to Order",
                    addHelp: model.others.isEmpty ? "No other mics are connected" : "Add a connected mic to the order",
                    isAddDisabled: model.others.isEmpty, removeTitle: "Remove from Order", remove: model.remove,
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
                    // Clears the order, so it sits with the buttons that change it.
                    Button("Follow System Default", action: model.followSystemDefault)
                        .labelStyle(.titleOnly)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(model.listed.isEmpty)
                }
            } header: {
                Text("Microphone Order")
            } footer: {
                Text("kotoba uses the first connected mic in this list. Drag to change the order.")
            }
            Section {
                LabeledContent("Input level") {
                    HStack {
                        Gauge(value: Double(min(max(model.testLevel ?? 0, 0), 1))) {}
                            .gaugeStyle(.accessoryLinearCapacity)
                            .animation(.linear(duration: 0.1), value: model.testLevel)
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
                    Text("Listening for \(MicrophoneModel.testSeconds) seconds. Speak to see the level.")
                } else {
                    Text("Records \(MicrophoneModel.testSeconds) seconds from the mic in use and keeps nothing.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.appear)
        .onDisappear(perform: model.disappear)
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
                of: .microphones(MicrophoneModel(source: .sample(order: [])) {}), named: "settings-microphone-empty"),
            MainWindow.snapshot(
                of: .microphones(
                    MicrophoneModel(
                        source: .sample(
                            order: ["airpods", "built-in"], current: "airpods",
                            warning: .bluetoothMic(interruptsPlayback: true))
                    ) {}),
                named: "settings-microphone-bluetooth"),
        ]
    }
}
