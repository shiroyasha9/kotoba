import AppKit
import KotobaCore
import SwiftUI

// The 0.5.0 main window, as a prototype for the owner to approve the visual system (`Page.swift`;
// docs/research/ui-redesign.md, "Process"): the new page map in the sidebar, Home and Activity on sample data. On
// screen with `make prototype`; offscreen in `make snapshots`. It goes when every page is built on the system.

/// The 0.5.0 page map, in sidebar order. Only Home and Activity have a page in the prototype.
enum PrototypePage: String, CaseIterable, Identifiable {
    case home
    case history
    case activity
    case shortcuts
    case speech
    case dictionary
    case cleanup
    case microphone
    case general

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .activity: "Activity"
        case .shortcuts: "Shortcuts"
        case .speech: "Speech"
        case .dictionary: "Dictionary"
        case .cleanup: "Cleanup"
        case .microphone: "Microphone"
        case .general: "General"
        }
    }

    /// Drawn filled where the symbol has a filled form (`SymbolTile`).
    var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock"
        case .activity: "chart.bar"
        case .shortcuts: "keyboard"
        case .speech: "waveform"
        case .dictionary: "character.book.closed"
        case .cleanup: "wand.and.sparkles"
        case .microphone: "mic"
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
        case .cleanup: .purple
        case .microphone: .red
        case .general: .gray
        }
    }

    /// The sidebar's second group, under "Settings".
    var isSetting: Bool {
        switch self {
        case .home, .history, .activity: false
        case .shortcuts, .speech, .dictionary, .cleanup, .microphone, .general: true
        }
    }
}

struct WindowPrototypeView: View {
    var home = HomePrototypeData.sample
    var activity = ActivityPrototypeData.sample
    @State var page: PrototypePage = .home
    @State var period = ActivityPeriod.week
    /// Gets each page the window shows: the window title follows it, as in System Settings. SwiftUI's
    /// `navigationTitle` does not reach a window that AppKit built.
    var onShow: (PrototypePage) -> Void = { _ in }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding($page)) {
                Section {
                    rows(PrototypePage.allCases.filter { !$0.isSetting })
                }
                Section("Settings") {
                    rows(PrototypePage.allCases.filter(\.isSetting))
                }
            }
            .navigationSplitViewColumnWidth(PageMetrics.sidebarWidth)
        } detail: {
            detail
                .navigationTitle(page.title)
        }
        // No sidebar toggle, as System Settings. On the split view, not the sidebar list: there it made the split view
        // ignore `navigationSplitViewColumnWidth` (sidebar 144 pt, not 215 pt; sidebar-spike, 2026-10-24).
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: PageMetrics.minimumWindowSize.width, minHeight: PageMetrics.minimumWindowSize.height)
        .onChange(of: page) { _, page in onShow(page) }
    }

    private func rows(_ pages: [PrototypePage]) -> some View {
        ForEach(pages) { page in
            Label {
                Text(page.title)
            } icon: {
                SidebarTile(systemImage: page.systemImage, tint: page.tint)
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch page {
        case .home:
            HomePrototype(data: home) { page = $0 }
        case .activity:
            ActivityPrototype(data: activity, period: period)
        case .history, .shortcuts, .speech, .dictionary, .cleanup, .microphone, .general:
            EmptyState(
                "Not in the Prototype", systemImage: page.systemImage,
                description: "This page is built once Home and Activity are approved.")
        }
    }
}

// MARK: - On screen

@MainActor
enum WindowPrototype {
    /// `make prototype` opens kotoba Dev with `--prototype`: the prototype window and the pill gallery
    /// (`PillPrototypeGallery`) on screen, with real glass, and nothing else of the app (no hotkey tap, audio, store or
    /// menu bar item). It quits when its windows close. It runs before `CopyHandOver`, so it opens beside a running
    /// kotoba Dev.
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--prototype") else { return }
        let launcher = Launcher()
        NSApplication.shared.delegate = launcher
        withExtendedLifetime(launcher) {
            NSApplication.shared.run()
        }
        exit(0)
    }

    /// The prototype window, as the main window is built (`MainWindow.window(showing:)`).
    static func window(showing view: WindowPrototypeView, title: String = PrototypePage.home.title) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(PageMetrics.defaultWindowSize)
        return window
    }
}

@MainActor
private final class Launcher: NSObject, NSApplicationDelegate {
    private var mainMenu: MainMenu?
    private var window: NSWindow?
    private var gallery: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘W, ⌘Q and the Edit menu, as in the app.
        let mainMenu = MainMenu(target: nil) { MenuModel.Updates() }
        NSApp.mainMenu = mainMenu.menu
        self.mainMenu = mainMenu
        WindowFront.activate()
        // `--prototype activity` opens on that page.
        let arguments = CommandLine.arguments
        let first =
            arguments.firstIndex(of: "--prototype").flatMap { arguments.dropFirst($0 + 1).first }
            .flatMap(PrototypePage.init(rawValue:)) ?? .home
        var view = WindowPrototypeView(page: first)
        view.onShow = { [weak self] page in self?.window?.title = page.title }
        let window = WindowPrototype.window(showing: view, title: first.title)
        window.center()
        self.window = window
        WindowFront.show(window)
        // proto-pill's gallery of the 0.5.0 pill states, on real glass.
        let gallery = PillPrototypeGallery.makeWindow()
        self.gallery = gallery
        WindowFront.show(gallery)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Window memory

@MainActor
extension WindowPrototype {
    /// `make window-memory PROTOTYPE=1`: the prototype window on Home, on Activity's week and on its month (one
    /// window each, as a page switch keeps its state inside the view), built, drawn and closed, three times, then 5 s of
    /// idle, as `Pane.measureWindowMemory` does for the main window.
    static func measureWindowMemory() -> Never {
        Pane.reportFootprint(at: "launch")
        for cycle in 1...3 {
            autoreleasepool {
                let windows = [
                    WindowPrototypeView(), WindowPrototypeView(page: .activity),
                    WindowPrototypeView(page: .activity, period: .month),
                ]
                .map { window(showing: $0) }
                Snapshots.settle()
                for window in windows {
                    window.displayIfNeeded()
                }
                Pane.reportFootprint(at: "window open \(cycle)")
                for window in windows {
                    window.close()
                }
            }
            Snapshots.settle()
            Pane.reportFootprint(at: "window closed \(cycle)")
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
        Pane.reportFootprint(at: "5 s after close")
        exit(0)
    }
}

// MARK: - Snapshots

@MainActor
extension WindowPrototype {
    /// The prototype window on each page and state, at the default size, wide (the centred column) and at its smallest;
    /// each page in full; the sidebar tiles at each sidebar icon size next to today's.
    static func snapshots() -> [Snapshot] {
        let wide = PageMetrics.wideWindowSize
        let smallest = PageMetrics.minimumWindowSize
        return [
            window(named: "prototype-window-home") { WindowPrototypeView() },
            window(named: "prototype-window-home-setup") {
                WindowPrototypeView(home: .sampleNew)
            },
            window(named: "prototype-window-activity") { WindowPrototypeView(page: .activity) },
            window(named: "prototype-window-activity-month") {
                WindowPrototypeView(page: .activity, period: .month)
            },
            window(named: "prototype-window-activity-new") {
                WindowPrototypeView(activity: .sampleNew, page: .activity)
            },
            window(named: "prototype-window-home-wide", size: wide) { WindowPrototypeView() },
            window(named: "prototype-window-activity-wide", size: wide) {
                WindowPrototypeView(page: .activity)
            },
            window(named: "prototype-window-home-smallest", size: smallest) {
                WindowPrototypeView()
            },
            page(named: "prototype-home", height: PageMetrics.homePageHeight) { HomePrototype(data: .sample) { _ in } },
            page(named: "prototype-activity", height: PageMetrics.activityPageHeight) {
                ActivityPrototype(data: .sample)
            },
            Snapshot(name: "prototype-sidebar-tiles") { NSHostingView(rootView: TileSheet()) },
            // The real window, title bar included: the title bar keeps one height on every page.
            framed(named: "prototype-framed-home", .home),
            framed(named: "prototype-framed-activity", .activity),
            framed(named: "prototype-framed-history", .history),
        ]
    }

    /// The whole window content at `size`, laid out again after its first pass: the page column takes its width from
    /// the window (`PageForm`).
    private static func window(
        named name: String, size: NSSize = PageMetrics.defaultWindowSize, _ view: @escaping @MainActor () -> some View
    ) -> Snapshot {
        var snapshot = Snapshots.fixedWindow(named: name, size: size, view)
        snapshot.settlesInWindow = true
        return snapshot
    }

    private static func framed(named name: String, _ page: PrototypePage) -> Snapshot {
        Snapshots.window(named: name, contentSize: PageMetrics.defaultWindowSize) {
            window(showing: WindowPrototypeView(page: page), title: page.title)
        }
    }

    /// One page at the detail column's width at the default window size, tall enough to show it whole.
    private static func page(
        named name: String, height: CGFloat, _ view: @escaping @MainActor () -> some View
    ) -> Snapshot {
        var snapshot = Snapshot(name: name) {
            let width = PageMetrics.detailWidth
            let hosting = NSHostingView(rootView: view().frame(width: width, height: height))
            hosting.setFrameSize(NSSize(width: width, height: height))
            return hosting
        }
        snapshot.settlesInWindow = true
        return snapshot
    }
}

/// Each page's sidebar tile at the small, medium and large sidebar icon sizes, beside today's `PaneIcon` where the page
/// has one, to compare the symbols' weight and size.
private struct TileSheet: View {
    private static let today: [PrototypePage: PaneID] = [
        .home: .home, .history: .history, .activity: .insights, .speech: .speech, .dictionary: .dictionary,
        .cleanup: .modes, .microphone: .microphones, .general: .general,
    ]

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Page")
                Text("Today")
                Text("Small")
                Text("Medium")
                Text("Large")
            }
            .foregroundStyle(.secondary)
            ForEach(PrototypePage.allCases) { page in
                GridRow {
                    Text(page.title)
                    if let pane = Self.today[page] {
                        PaneIcon(pane: pane)
                    } else {
                        Text("None").foregroundStyle(.secondary)
                    }
                    ForEach([SidebarRowSize.small, .medium, .large], id: \.self) { size in
                        SidebarTile(systemImage: page.systemImage, tint: page.tint)
                            .environment(\.sidebarRowSize, size)
                    }
                }
            }
        }
        .padding()
    }
}
