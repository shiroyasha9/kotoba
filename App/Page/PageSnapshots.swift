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
            framedList,
            largeTextList,
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
                    title: "Learn from edits",
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

/// A list page in a wide detail column (`PageList`), with its pinned header, a setting and the search.
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

@MainActor
/// A list page in the real window, title bar included: the title bar over the list.
private var framedList: Snapshot {
    let panes = [Pane.home(.sample), Pane(id: .history) { AnyView(ListSample()) }]
    return MainWindow.windowSnapshot(of: panes, selecting: .history, named: "page-list-framed", isFramed: true)
}

/// A list page whose pinned groups are taller than `PageMetrics.pinnedMaxHeight`, in the smallest window: they scroll,
/// and the run fails if they are cut off. It stands in for large text: macOS draws `dynamicTypeSize(.accessibility3)`
/// at the regular size (the pinned groups measured 153 pt either way).
@MainActor
private var largeTextList: Snapshot {
    let panes = [Pane.home(.sample), Pane(id: .history) { AnyView(ListSample(isTall: true)) }]
    return MainWindow.windowSnapshot(
        of: panes, selecting: .history, named: "page-list-large-text", size: PageMetrics.minimumWindowSize)
}

private struct ListSample: View {
    /// Pinned groups taller than `PageMetrics.pinnedMaxHeight`, as large text makes them.
    var isTall = false
    @State private var selection: Set<Int> = [2]
    @State private var search = ""

    var body: some View {
        PageList(selection: $selection) {
            Section("Today") {
                ForEach(1...6, id: \.self) { Text("Dictation \($0)") }
            }
        } pinned: {
            Section {
                PageHeader(page: .history, summary: "Every dictation, newest first.")
            }
            Section {
                PageRow(title: "Keep audio", subtitle: "For Retry and Play. The text always stays.") {
                    Text("7 Days").foregroundStyle(.secondary)
                }
            }
            if isTall {
                Section {
                    ForEach(1...3, id: \.self) {
                        PageRow(
                            title: "Setting \($0)",
                            subtitle: "A subtitle long enough to wrap onto a second line in the smallest window."
                        ) {}
                    }
                }
            }
        }
        .pageSearch(text: $search, prompt: "Search")
    }
}
