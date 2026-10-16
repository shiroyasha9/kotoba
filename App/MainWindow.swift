import AppKit
import KotobaCore
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

    /// Set only by the README snapshots: the sidebar draws its selected row and its labels with explicit colors.
    /// Offscreen, the list's own selection draws as a black block over its label, and the glass's text treatment
    /// leaves the labels near black in dark (docs/research/native-ui.md): the window server applies both.
    @Entry var drawsSidebarColors = false
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
    /// The open window's pane, Back and Forward; nil while it is closed.
    private var selection: Selection?

    /// The pane the open window shows; nil while it is closed.
    var shownPane: PaneID? { selection?.history.current }

    /// Shows the window, building it with `panes` when it is not open. `id` picks the pane to show; nil keeps the
    /// pane already shown, or opens at the pane the window showed last (Home the first time).
    func show(_ panes: @autoclosure () -> [Pane], selecting id: Pane.ID? = nil) {
        WindowFront.activate()
        if window != nil, let id {
            selection?.id = id
        }
        let window = window ?? makeWindow(panes: panes(), showing: id)
        self.window = window
        WindowFront.show(window)
    }

    /// Edit > Find… (⌘F): no view in the window answers it, so AppKit sends it to the window's delegate. SwiftUI's
    /// toolbar search field does not take it on its own.
    @objc func performTextFinderAction(_ sender: Any?) {
        selection?.findRequests += 1
    }

    /// Find is on only in a pane with a search field, and off while a sheet is open: AppKit also sends the sheet's
    /// actions to this window when no view in the sheet answers them, and the field is behind the sheet.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(performTextFinderAction(_:)) else { return true }
        return shownPane?.hasSearch == true && window?.attachedSheet == nil
    }

    func windowWillClose(_ notification: Notification) {
        // A window that is still being freed keeps the name, and a new window with the same name would not save its
        // frame.
        window?.setFrameAutosaveName("")
        window = nil
        selection = nil
        onClose()
    }

    private func makeWindow(panes: [Pane], showing id: Pane.ID?) -> NSWindow {
        let selection = Selection(panes: panes, showing: id, last: AppDefaults.lastPane)
        self.selection = selection
        let window = Self.window(
            showing: MainView(panes: panes, selection: selection) { [weak self] pane in
                // The window title follows the pane, as in System Settings; the next window opens at it.
                self?.window?.title = pane.title
                AppDefaults.lastPane = pane
            })
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

/// The pane the sidebar shows, with Back and Forward (`PaneHistory`, KotobaCore), for one open window.
@MainActor
@Observable
final class Selection {
    var history: PaneHistory<PaneID>
    /// Edit > Find… requests; the shown pane gets them as `findRequests`.
    var findRequests = 0

    /// Shows `id`, else `last`, else Home; a pane missing from `panes` is skipped.
    init(panes: [Pane], showing id: PaneID?, last: PaneID? = nil) {
        history = PaneHistory(panes: Set(panes.map(\.id)), showing: id, last: last, home: .home)
    }

    /// The sidebar's selection. Each change by the owner (the sidebar, a pane's link, the menu) goes on the Back list.
    /// Optional only for the sidebar list, which sends nil on a ⌘-click; the window always shows a pane.
    var id: Pane.ID? {
        get { history.current }
        set { history.select(newValue) }
    }
}

struct MainView: View {
    let panes: [Pane]
    @Bindable var selection: Selection
    @Environment(\.drawsSidebarColors) private var drawsSidebarColors
    /// Gets each pane the window shows.
    let onShow: (PaneID) -> Void

    init(panes: [Pane], selection: Selection, onShow: @escaping (PaneID) -> Void = { _ in }) {
        let order = PaneID.allCases
        self.panes = panes.sorted { order.firstIndex(of: $0.id) ?? 0 < order.firstIndex(of: $1.id) ?? 0 }
        self.selection = selection
        self.onShow = onShow
    }

    private var shown: Pane? {
        panes.first { $0.id == selection.history.current }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: drawsSidebarColors ? .constant(nil) : $selection.id) {
                Section {
                    rows(panes.filter { !$0.id.isSetting })
                }
                Section {
                    rows(panes.filter(\.id.isSetting))
                } header: {
                    Text("Settings")
                        .modifier(SidebarColor(color: .secondaryLabelColor))
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
                    Button("Back", systemImage: "chevron.backward") { selection.history.goBack() }
                        .help("Show the previous pane")
                        .keyboardShortcut("[", modifiers: .command)
                        .disabled(selection.history.back.isEmpty)
                    Button("Forward", systemImage: "chevron.forward") { selection.history.goForward() }
                        .help("Show the next pane")
                        .keyboardShortcut("]", modifiers: .command)
                        .disabled(selection.history.forward.isEmpty)
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
        .onChange(of: shown?.id, initial: true) { _, id in
            if let id { onShow(id) }
        }
    }

    private func rows(_ panes: [Pane]) -> some View {
        ForEach(panes) { pane in
            let isSelected = drawsSidebarColors && pane.id == selection.id
            Label {
                Text(pane.title)
                    .modifier(SidebarColor(color: isSelected ? .alternateSelectedControlTextColor : .labelColor))
            } icon: {
                PaneIcon(pane: pane.id)
            }
            .listRowBackground(
                isSelected
                    // The source list's emphasized selection, inset from the sidebar's edges.
                    ? RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .selectedContentBackgroundColor))
                        .padding(.horizontal, 10) : nil)
        }
    }
}

/// An explicit text color in the README snapshots (`drawsSidebarColors`); the system's own style everywhere else.
private struct SidebarColor: ViewModifier {
    let color: NSColor
    @Environment(\.drawsSidebarColors) private var drawsColor

    func body(content: Content) -> some View {
        if drawsColor {
            content.foregroundStyle(Color(nsColor: color))
        } else {
            content
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
