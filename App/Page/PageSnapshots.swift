import SwiftUI

// MARK: - Snapshots

@MainActor
extension MainWindow {
    /// The page system's parts that no page shows yet in its own snapshots: the search field (empty and with a
    /// search) and a switch row, beside a native form switch with a subtitle, so the two can be compared.
    static func pageSystemSnapshots() -> [Snapshot] {
        [snapshot(of: Pane(id: .general) { AnyView(SystemSheet()) }, named: "page-system")]
    }
}

private struct SystemSheet: View {
    @State private var empty = ""
    @State private var search = "standup"
    @State private var isOn = true
    @State private var isOff = false

    var body: some View {
        PageForm {
            Section {
                PageRow(title: "Move the standup to Thursday", subtitle: nil) {}
            } header: {
                PageSearchField(text: $empty, prompt: "Search")
            }
            Section {
                PageRow(title: "Move the standup to Thursday", subtitle: nil) {}
            } header: {
                PageSearchField(text: $search, prompt: "Search")
            }
            Section {
                PageToggle(title: "Keep filler words", subtitle: "Leaves “um” and “uh” in the text.", isOn: $isOn)
                PageToggle(
                    title: "Learn from my edits",
                    subtitle:
                        "kotoba watches the text field for a minute after a paste and suggests the words you correct, "
                        + "so they can go into your dictionary.",
                    isOn: $isOff)
                Toggle(isOn: $isOn) {
                    Text("Native form switch")
                    Text("For comparison only.")
                }
            }
        }
    }
}
