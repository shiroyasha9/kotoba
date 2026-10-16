import AppKit
import Observation
import SwiftUI

/// One page of the main window. To add a pane, add its case to `PaneID` (the case order is the sidebar order) with
/// its title, symbol and color, write `extension Pane { static func name(…) -> Self }` in its own file and add
/// it to the list in `MainWindowController`.
struct Pane: Identifiable {
    let id: PaneID
    let content: @MainActor () -> AnyView

    var title: String { id.title }
}

/// In sidebar order: the app's own pages first, then the settings, where the panes a new user needs first come first
/// (docs/research/ux-polish.md W2).
enum PaneID: String, Hashable, CaseIterable {
    case home
    case history
    case insights
    case usage
    case general
    case speech
    case dictionary
    case modes
    case microphones

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .insights: "Insights"
        case .usage: "Usage"
        case .general: "General"
        case .speech: "Speech"
        case .dictionary: "Dictionary"
        case .modes: "Modes"
        case .microphones: "Microphone"
        }
    }

    /// Filled symbols, white on the pane's color, as in System Settings.
    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .history: "clock.fill"
        case .insights: "chart.line.uptrend.xyaxis"
        case .usage: "chart.bar.fill"
        case .general: "gearshape.fill"
        case .speech: "waveform"
        case .dictionary: "character.book.closed.fill"
        case .modes: "square.grid.2x2.fill"
        case .microphones: "mic.fill"
        }
    }

    var tint: Color {
        switch self {
        case .home: .teal
        case .history: .pink
        case .insights: .indigo
        case .usage: .green
        case .general: .gray
        case .speech: .blue
        case .dictionary: .orange
        case .modes: .purple
        case .microphones: .red
        }
    }

    /// The sidebar's second group, under the "Settings" header.
    var isSetting: Bool {
        switch self {
        case .home, .history, .insights, .usage: false
        case .general, .speech, .dictionary, .modes, .microphones: true
        }
    }

    /// The panes with a toolbar search field: Edit > Find… (⌘F) puts the cursor in it. In the other panes Find stays
    /// off.
    var hasSearch: Bool { self == .dictionary || self == .history }
}

extension EnvironmentValues {
    /// Goes up by one each time the owner chooses Edit > Find… in the main window. A pane with a search field focuses
    /// it on each change.
    @Entry var findRequests = 0
}

/// A pane's symbol, white on a rounded square of the pane's color, as in the System Settings sidebar. Custom: SwiftUI
/// has no settings icon style.
struct PaneIcon: View {
    let pane: PaneID
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: pane.systemImage)
            .resizable()
            .scaledToFit()
            .padding(size * 0.2)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pane.tint.gradient, in: .rect(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The main window: Home, History, Insights, Usage and the settings in one sidebar. Built when the owner opens it and
/// released when they close it, with every pane model; while it is closed it costs nothing but SwiftUI's loaded
/// runtime. SwiftUI is used only for on-demand windows (docs/spec.md, Platform and UI).
@MainActor
final class MainWindow: NSObject, NSWindowDelegate, NSMenuItemValidation {
    /// Room for History's rows and Home's figures next to the sidebar (owner, 2026-10-16: open big by default).
    static let defaultSize = NSSize(width: 960, height: 640)
    private static let frameName = "Main"

    /// Runs when the window closes, so the owner of the pane models releases them.
    var onClose: @MainActor () -> Void = {}
    private var window: NSWindow?
    private let selection = Selection()
    /// The panes of the open window; a pane the window was built without (History when the history did not open) is
    /// never selected.
    private var paneIDs: Set<PaneID> = []

    /// The pane the open window shows; nil while it is closed.
    var shownPane: PaneID? { window == nil ? nil : selection.id }

    /// Shows the window, building it with `panes` when it is not open. `id` picks the pane to show; nil keeps the
    /// pane already shown, or Home.
    func show(_ panes: @autoclosure () -> [Pane], selecting id: Pane.ID? = nil) {
        WindowFront.activate()
        let window = window ?? makeWindow(panes: panes())
        self.window = window
        if let id, paneIDs.contains(id) {
            selection.id = id
        }
        WindowFront.show(window)
    }

    /// Edit > Find… (⌘F): no view in the window answers it, so AppKit sends it to the window's delegate. SwiftUI's
    /// toolbar search field does not take it on its own.
    @objc func performTextFinderAction(_ sender: Any?) {
        selection.findRequests += 1
    }

    /// Find is on only in a pane with a search field, and off while a sheet is open: AppKit also sends the sheet's
    /// actions to this window when no view in the sheet answers them, and the field is behind the sheet.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performTextFinderAction(_:)) else { return true }
        return selection.id?.hasSearch == true && window?.attachedSheet == nil
    }

    func windowWillClose(_ notification: Notification) {
        // A window that is still being freed keeps the name, and a new window with the same name would not save its
        // frame.
        window?.setFrameAutosaveName("")
        window = nil
        selection.reset(to: nil)
        onClose()
    }

    private func makeWindow(panes: [Pane]) -> NSWindow {
        paneIDs = Set(panes.map(\.id))
        selection.reset(to: .home)
        // The window title follows the pane, as in System Settings.
        let window = Self.window(
            showing: MainView(panes: panes, selection: selection) { [weak self] title in self?.window?.title = title })
        window.delegate = self
        // The size and place the owner left it at; centred at the default size the first time.
        if !window.setFrameUsingName(Self.frameName) {
            window.setContentSize(Self.defaultSize)
            window.center()
        }
        window.setFrameAutosaveName(Self.frameName)
        return window
    }

    /// The window and its content, toolbar included; the snapshot run draws the same window.
    static func window(showing view: MainView) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = Install.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        return window
    }
}

/// The pane the sidebar shows, and the panes shown before and after it for Back and Forward, as in System Settings.
@MainActor
@Observable
final class Selection {
    /// Each change by the owner (the sidebar, a pane's link, the menu) goes on the Back list.
    var id: Pane.ID? {
        didSet {
            guard let oldValue, oldValue != id else { return }
            if isMovingInHistory {
                isMovingInHistory = false
            } else {
                back.append(oldValue)
                forward.removeAll()
            }
        }
    }
    /// Edit > Find… requests; the shown pane gets them as `findRequests`.
    var findRequests = 0
    private(set) var back: [Pane.ID] = []
    private(set) var forward: [Pane.ID] = []
    @ObservationIgnored private var isMovingInHistory = false

    func goBack() {
        guard let id, let previous = back.popLast() else { return }
        forward.append(id)
        isMovingInHistory = true
        self.id = previous
    }

    func goForward() {
        guard let id, let next = forward.popLast() else { return }
        back.append(id)
        isMovingInHistory = true
        self.id = next
    }

    /// A new window starts with no Back or Forward.
    func reset(to id: Pane.ID?) {
        isMovingInHistory = true
        self.id = id
        isMovingInHistory = false
        back.removeAll()
        forward.removeAll()
    }
}

struct MainView: View {
    let panes: [Pane]
    @Bindable var selection: Selection
    let onTitle: (String) -> Void

    init(panes: [Pane], selection: Selection, onTitle: @escaping (String) -> Void = { _ in }) {
        let order = PaneID.allCases
        self.panes = panes.sorted { order.firstIndex(of: $0.id) ?? 0 < order.firstIndex(of: $1.id) ?? 0 }
        self.selection = selection
        self.onTitle = onTitle
    }

    private var shown: Pane? {
        panes.first { $0.id == selection.id } ?? panes.first
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.id) {
                Section {
                    rows(panes.filter { !$0.id.isSetting })
                }
                Section("Settings") {
                    rows(panes.filter(\.id.isSetting))
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190, max: 240)
            // System Settings keeps its sidebar: no toggle to hide it.
            .toolbar(removing: .sidebarToggle)
            // Back and Forward on every pane, as in System Settings. They also keep the toolbar on panes with no items
            // of their own: such a pane got a 32 pt title bar, and History's 52 pt toolbar moved the traffic lights,
            // the sidebar and the title (owner, 2026-10-16).
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Back", systemImage: "chevron.backward", action: selection.goBack)
                        .help("Show the previous pane")
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(selection.back.isEmpty)
                    Button("Forward", systemImage: "chevron.forward", action: selection.goForward)
                        .help("Show the next pane")
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(selection.forward.isEmpty)
                }
            }
        } detail: {
            if let pane = shown {
                pane.content()
                    .navigationTitle(pane.title)
                    .environment(\.findRequests, selection.findRequests)
                    // A pane opens another one (Home's "Show All"); the selection lives in the window.
                    .environment(\.openPane, OpenPaneAction { selection.id = $0 })
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .onChange(of: shown?.title, initial: true) { _, title in onTitle(title ?? Install.displayName) }
    }

    private func rows(_ panes: [Pane]) -> some View {
        ForEach(panes) { pane in
            Label {
                Text(pane.title)
            } icon: {
                PaneIcon(pane: pane.id)
            }
        }
    }
}

/// Shows another pane of the main window, from inside a pane.
struct OpenPaneAction {
    let open: @MainActor (PaneID) -> Void

    @MainActor func callAsFunction(_ pane: PaneID) {
        open(pane)
    }
}

extension EnvironmentValues {
    @Entry var openPane = OpenPaneAction { _ in }
}
