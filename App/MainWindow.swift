import AppKit
import KotobaCore
import Observation
import SwiftUI

/// One page of the main window. To add a pane, add its case to `PaneID` (the case order is the sidebar order) with
/// its title, symbol and color, write `extension Pane { static func name(…) -> Self }` in its own file and add
/// it to the list in `MainWindowController`.
struct Pane: Identifiable {
    let id: PaneID
    /// The count on the page's sidebar row (Dictionary's word suggestions), as Mail's unread count; none at 0. Read while
    /// the sidebar draws, so an `@Observable` source redraws the row when it changes.
    var badge: @MainActor () -> Int = { 0 }
    let content: @MainActor () -> AnyView

    var title: String { id.title }
}

/// In sidebar order: the app's own pages first, then the settings, where the pages a new user needs first come first
/// (docs/research/ui-redesign.md, "Page map").
/// The raw value is stored (`AppDefaults.lastPane`), so a case keeps its name when its page is renamed: `modes` is the
/// Cleanup page (Cleanup, Rewrite and App styles).
enum PaneID: String, Hashable, CaseIterable {
    case home
    case history
    case activity
    case shortcuts
    case speech
    case dictionary
    case modes
    case microphones
    case general

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .activity: "Activity"
        case .shortcuts: "Shortcuts"
        case .speech: "Speech"
        case .dictionary: "Dictionary"
        case .modes: "Cleanup"
        case .microphones: "Microphone"
        case .general: "General"
        }
    }

    /// The page's symbol, white on the page's tint in its sidebar tile and header card (`SymbolTile`, which draws the
    /// filled form where the symbol has one). A row elsewhere that shows a page's symbol uses the page's tint.
    var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .activity: "chart.bar"
        case .shortcuts: "keyboard"
        case .speech: "waveform"
        case .dictionary: "character.book.closed"
        // The pill's cleanup wand (`PillView`), so one symbol names one thing.
        case .modes: "wand.and.sparkles"
        case .microphones: "mic"
        case .general: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .home: .blue
        case .history: .pink
        case .activity: .indigo
        case .shortcuts: .gray
        case .speech: .teal
        case .dictionary: .orange
        case .modes: .purple
        case .microphones: .red
        case .general: .gray
        }
    }

    /// The sidebar's second group, under the "Settings" header.
    var isSetting: Bool {
        switch self {
        case .home, .history, .activity: false
        case .shortcuts, .speech, .dictionary, .modes, .microphones, .general: true
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

    /// Dead since the menu lost "Add Word…": always off. Its last reader is the Dictionary pane, whose rollout removes
    /// it; this key goes then.
    @Entry var addWordRequest: Binding<Bool> = .constant(false)
}

/// The main window: Home, History, Activity and the settings in one sidebar. Built when the owner opens it and
/// released when they close it, with every pane model; while it is closed it costs nothing but SwiftUI's loaded
/// runtime. SwiftUI is used only for on-demand windows (docs/spec.md, Platform and UI).
@MainActor
final class MainWindow: NSObject, NSWindowDelegate, NSMenuItemValidation {
    private static let frameName = "Main"

    /// Runs when the window closes, so the owner of the pane models releases them.
    var onClose: @MainActor () -> Void = {}
    private var window: NSWindow?
    /// The open window's pane; nil while it is closed.
    private var selection: Selection?

    /// The pane the open window shows; nil while it is closed.
    var shownPane: PaneID? { selection?.pane.current }

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
            window.setContentSize(PageMetrics.defaultWindowSize)
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

/// The pane the sidebar shows (`PaneSelection`, KotobaCore), for one open window.
@MainActor
@Observable
final class Selection {
    var pane: PaneSelection<PaneID>
    /// Edit > Find… requests; the shown pane gets them as `findRequests`.
    var findRequests = 0

    /// Shows `id`, else `last`, else Home; a pane missing from `panes` is skipped.
    init(panes: [Pane], showing id: PaneID?, last: PaneID? = nil) {
        pane = PaneSelection(panes: Set(panes.map(\.id)), showing: id, last: last, home: .home)
    }

    /// The sidebar's selection (the sidebar, a page's link, the menu). Optional only for the sidebar list, which sends
    /// nil on a ⌘-click; the window always shows a pane.
    var id: Pane.ID? {
        get { pane.current }
        set { pane.select(newValue) }
    }
}

struct MainView: View {
    let panes: [Pane]
    @Bindable var selection: Selection
    /// The name and icon at the top of the sidebar.
    let identity: AppIdentity
    /// Gets each pane the window shows.
    let onShow: (PaneID) -> Void

    init(
        panes: [Pane], selection: Selection, identity: AppIdentity = .running,
        onShow: @escaping (PaneID) -> Void = { _ in }
    ) {
        let order = PaneID.allCases
        self.panes = panes.sorted { order.firstIndex(of: $0.id) ?? 0 < order.firstIndex(of: $1.id) ?? 0 }
        self.selection = selection
        self.identity = identity
        self.onShow = onShow
    }

    private var shown: Pane? {
        panes.first { $0.id == selection.pane.current }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.id) {
                // The app's name at the top of the sidebar on every page (owner, 2026-10-25: the window looked like
                // another System Settings pane). A row that cannot be selected, so it takes the list's own insets and
                // its icon sits in the tiles' column; the traffic lights keep the title bar above it.
                Label {
                    // Bold, as a title: the sidebar list sets its own size on row text, so only the weight is set.
                    Text(identity.name)
                        .fontWeight(.bold)
                } icon: {
                    SidebarAppIcon(icon: identity.icon)
                }
                .selectionDisabled()
                .accessibilityAddTraits(.isHeader)
                Section {
                    rows(panes.filter { !$0.id.isSetting })
                }
                Section("Settings") {
                    rows(panes.filter(\.id.isSetting))
                }
            }
            .navigationSplitViewColumnWidth(PageMetrics.sidebarWidth)
        } detail: {
            if let pane = shown {
                pane.content()
                    .navigationTitle(pane.title)
                    .environment(\.findRequests, selection.findRequests)
                    // A pane opens another one (Home's "Show All"); the selection lives in the window.
                    .environment(\.openPane, OpenPaneAction { selection.id = $0 })
            }
        }
        // No sidebar toggle, as System Settings. On the split view, not on the sidebar list: there it made the split
        // view ignore `navigationSplitViewColumnWidth` (the sidebar was 144 pt, not the width asked; sidebar-spike,
        // 2026-10-24).
        .toolbar(removing: .sidebarToggle)
        // A wider window would leave the page column floating in blank space (`PageMetrics.maximumWindowWidth`).
        .frame(
            minWidth: PageMetrics.minimumWindowSize.width, maxWidth: PageMetrics.maximumWindowWidth,
            minHeight: PageMetrics.minimumWindowSize.height
        )
        .onChange(of: shown?.id, initial: true) { _, id in
            if let id { onShow(id) }
        }
    }

    private func rows(_ panes: [Pane]) -> some View {
        ForEach(panes) { pane in
            Label {
                Text(pane.title)
            } icon: {
                SidebarTile(systemImage: pane.id.systemImage, tint: pane.id.tint)
            }
            .badge(pane.badge())
        }
    }
}

/// The app's icon at the sidebar's tile size.
private struct SidebarAppIcon: View {
    let icon: NSImage
    @Environment(\.sidebarRowSize) private var rowSize

    var body: some View {
        AppIconView(icon: icon, side: PageMetrics.sidebarTileSide(rowSize))
    }
}

/// The name and icon at the top of the sidebar.
struct AppIdentity {
    var name: String
    var icon: NSImage

    /// This install's, as the Dock shows it: "kotoba Dev" and the DEV icon in a development build.
    @MainActor static var running: Self {
        Self(name: Install.displayName, icon: NSApplication.shared.applicationIconImage)
    }

    /// The release's, for the README images: a development build carries the release icon too (`AppIcon`).
    @MainActor static var release: Self {
        guard let icon = NSImage(named: "AppIcon") else { preconditionFailure("The build has no release icon") }
        return Self(name: Install.releaseDisplayName, icon: icon)
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
