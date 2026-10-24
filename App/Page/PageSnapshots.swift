import SwiftUI

// MARK: - Snapshots

@MainActor
extension MainWindow {
    /// The page system's parts that no page shows yet in its own snapshots: the search field (empty and with a
    /// search) and a switch row, beside a native form switch with a subtitle, so the two can be compared.
    static func pageSystemSnapshots() -> [Snapshot] {
        [
            snapshot(of: Pane(id: .general) { AnyView(SystemSheet()) }, named: "page-system"),
            pageList,
            // A sheet longer than the smallest window stops at its height and scrolls.
            sheetSnapshot(named: "page-sheet-long") {
                PageSheet(title: "Long") {
                    Section {
                        ForEach(1...30, id: \.self) { PageRow(title: "Row \($0)", subtitle: nil) {} }
                    }
                }
            },
        ]
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

@MainActor
extension MainWindow {
    /// A `PageSheet` at the height it takes in the app: a window that fits its content each round until it holds still
    /// (`Snapshots.fittedWindow`), since the sheet measures its form a run loop turn after its first layout. The sheet's
    /// content only, with no title bar: a sheet's Cancel and Done draw at its foot, which only a real sheet shows.
    static func sheetSnapshot(named name: String, _ sheet: @escaping @MainActor () -> some View) -> Snapshot {
        Snapshots.fittedWindow(named: name) {
            let window = NSWindow(contentViewController: NSHostingController(rootView: sheet()))
            window.styleMask = [.borderless]
            window.isReleasedWhenClosed = false
            return window
        }
    }
}

/// A list page in a wide detail column: its rows start where a form's card text does (`PageList`).
@MainActor
private var pageList: Snapshot {
    var snapshot = Snapshot(name: "page-list") {
        let view = NSHostingView(rootView: ListSample().frame(width: 840, height: 500))
        view.setFrameSize(NSSize(width: 840, height: 500))
        return view
    }
    snapshot.settlesInWindow = true
    return snapshot
}

private struct ListSample: View {
    @State private var selection: Set<Int> = [2]

    var body: some View {
        PageList(selection: $selection) {
            Section {
                PageHeader(page: .history, summary: "Every dictation, newest first.")
            }
            .selectionDisabled()
            Section("Today") {
                ForEach(1...6, id: \.self) { Text("Dictation \($0)") }
            }
        }
    }
}
