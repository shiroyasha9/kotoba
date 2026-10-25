import AppKit
import KotobaCore
import SwiftUI

// MARK: - Snapshots

extension MainWindow {
    /// One pane at the size of the window's detail column, for `make snapshots`. Each pane's file registers its own
    /// snapshots with this. The sidebar and the toolbar (title, search field) are in `windowSnapshot`.
    /// 760 x 600 is about the detail column at the default window size; a taller `height` shows a pane that scrolls in
    /// the window in full.
    static func snapshot(of pane: Pane, named name: String, height: CGFloat = 600) -> Snapshot {
        var snapshot = Snapshot(name: name) {
            let view = NSHostingView(rootView: pane.content().frame(width: 760, height: height))
            view.setFrameSize(NSSize(width: 760, height: height))
            return view
        }
        // A pane's list rows (History, Dictionary) take their measured heights in the window.
        snapshot.settlesInWindow = true
        return snapshot
    }

    /// The whole window content (sidebar and pane) at the default size, for `make snapshots`. It stops the run when
    /// the content is taller or wider than the window: on 2026-10-15 a pane that grew past the window pushed the
    /// sidebar rows above its top and the footer below its bottom, so the window looked empty. `isFramed` draws the
    /// real window instead, title bar and toolbar included (a pane's toolbar buttons and search field).
    static func windowSnapshot(
        of panes: [Pane], selecting id: Pane.ID, named name: String, size: NSSize = PageMetrics.defaultWindowSize,
        isFramed: Bool = false
    ) -> Snapshot {
        let selection = { Selection(panes: panes, showing: id) }
        guard isFramed else {
            return Snapshots.fixedWindow(
                named: name, size: size, check: { overflow($0) ?? clipped(in: $0) },
                { MainView(panes: panes, selection: selection()) })
        }
        return Snapshots.window(named: name, contentSize: size) {
            window(showing: MainView(panes: panes, selection: selection()))
        } check: {
            overflow($0) ?? clipped(in: $0)
        }
    }

    /// A showcase image (`Pane.showcaseSnapshots`, `make readme-images`): the real window at the default size, title
    /// bar and toolbar included, with the release's name and icon, on the showcase stage. The page's scroll
    /// bar is not in the image (an overlay scroll bar shows as the page appears).
    static func showcaseSnapshot(of panes: [Pane], selecting id: Pane.ID, named name: String) -> Snapshot {
        var snapshot = Snapshots.window(named: name, contentSize: PageMetrics.defaultWindowSize) {
            let view = MainView(panes: panes, selection: Selection(panes: panes, showing: id), identity: .release)
            return window(showing: view, root: view.scrollIndicators(.hidden))
        } check: {
            overflow($0)
        }
        snapshot.isOnStage = true
        snapshot.scale = 2
        return snapshot
    }

    /// Content that left the window's bounds: a pane taller than the window moves the split view.
    private static func overflow(_ content: NSView) -> String? {
        content.subviews.first { $0.frame != content.bounds }.map {
            "the window content is \($0.frame), the window is \(content.bounds)"
        }
    }

    /// Content cut off in a scroll view with no scroller, which cannot scroll (a list page's pinned cards at large
    /// text, owner QA 1, Q18). Not for the showcase images, which hide their scroll bars on purpose.
    private static func clipped(in view: NSView) -> String? {
        if let scroll = view as? NSScrollView, !scroll.hasVerticalScroller,
            let document = scroll.documentView?.frame.height, document > scroll.contentView.bounds.height + 0.5
        {
            return "a view \(document) pt tall is cut off at \(scroll.contentView.bounds.height) pt and cannot scroll"
        }
        return view.subviews.lazy.compactMap { clipped(in: $0) }.first
    }
}

extension MainWindow {
    /// The frames a pane change must not move: the window, the traffic lights and the area under the toolbar (which
    /// the toolbar's height sets, and with it the sidebar rows and the pane title).
    private struct Chrome: Equatable, CustomStringConvertible {
        var frame: NSRect
        var closeButton: NSRect
        var content: NSRect

        @MainActor init(_ window: NSWindow) {
            frame = window.frame
            closeButton = window.standardWindowButton(.closeButton)?.frame ?? .zero
            content = window.contentLayoutRect
        }

        var description: String { "window \(frame), close button \(closeButton), content \(content)" }
    }

    /// One window that shows each pane of `path` in turn, as a click in the sidebar does, drawn on the last one. The
    /// run fails when the window, its traffic lights or its toolbar height differ from the first pane's (owner,
    /// 2026-10-16: History's tall toolbar moved the sidebar 17 pt below Home's).
    static func switchSnapshot(of panes: [Pane], through path: [PaneID], named name: String) -> Snapshot {
        var chromes: [(PaneID, Chrome)] = []
        var snapshot = Snapshots.window(named: name, contentSize: PageMetrics.defaultWindowSize) {
            let selection = Selection(panes: panes, showing: path.first)
            let window = window(showing: MainView(panes: panes, selection: selection))
            window.setContentSize(PageMetrics.defaultWindowSize)
            for id in path {
                selection.id = id
                window.title = id.title
                Snapshots.settle()
                window.layoutIfNeeded()
                chromes.append((id, Chrome(window)))
            }
            return window
        } check: { _ in
            guard let (first, expected) = chromes.first else { return "no pane was shown" }
            return chromes.first { $0.1 != expected }.map { id, chrome in
                "\(id.title) has \(chrome); \(first.title) has \(expected)"
            }
        }
        // The toolbar's glass animates in after the last switch in the window server, so a capture can catch it midway.
        snapshot.hasImage = false
        return snapshot
    }
}

extension MainWindow {
    /// Each page's sidebar tile and the header tile, at the small, medium and large sidebar icon sizes (System Settings
    /// > Appearance), to compare the symbols' weight and size.
    static func tileSnapshots() -> [Snapshot] {
        [
            Snapshot(name: "sidebar-tiles") { NSHostingView(rootView: TileSheet()) },
            // A page's sidebar badge (`Pane.badge`), on a page that is not shown and on the shown one.
            windowSnapshot(
                of: [
                    .home(.sample), Pane(id: .history, badge: { 3 }, content: { AnyView(EmptyView()) }),
                    Pane(id: .dictionary, badge: { 12 }, content: { AnyView(EmptyView()) }),
                ],
                selecting: .dictionary, named: "sidebar-badge"),
        ]
    }
}

private struct TileSheet: View {
    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                Text("Page")
                Text("Small")
                Text("Medium")
                Text("Large")
                Text("Header")
            }
            .foregroundStyle(.secondary)
            ForEach(PaneID.allCases, id: \.self) { page in
                GridRow {
                    Text(page.title)
                    ForEach([SidebarRowSize.small, .medium, .large], id: \.self) { size in
                        SidebarTile(systemImage: page.systemImage, tint: page.tint)
                            .environment(\.sidebarRowSize, size)
                    }
                    SymbolTile(systemImage: page.systemImage, tint: page.tint, side: PageMetrics.headerTileSide)
                }
            }
        }
        .padding()
    }
}

extension MainWindow {
    /// A frame saved before the window had a maximum width (0.4.6 kept one up to the screen's width) comes back at most
    /// `PageMetrics.maximumWindowWidth` wide: AppKit restores the saved frame as it is, and the hosting controller's
    /// maximum content size narrows it at the first layout, before the window shows (review-upgrade, 2026-10-25). The
    /// run fails if a change loses that. No image.
    static func frameChecks() -> [Snapshot] {
        var width: CGFloat = 0
        var snapshot = Snapshot(name: "window-wide-saved-frame") {
            let panes = [Pane.home(.sample)]
            let window = window(showing: MainView(panes: panes, selection: Selection(panes: panes, showing: .home)))
            // A 0.4.6 frame 1,440 pt wide, as `setFrameUsingName` reads it from the saved string.
            window.setFrame(from: "100 100 1440 800 0 0 1920 1080 ")
            Snapshots.settle()
            window.layoutIfNeeded()
            width = window.contentLayoutRect.width
            return NSView()
        } check: { _ in
            width > PageMetrics.maximumWindowWidth + 0.5
                ? "a saved frame stays \(width) pt wide, more than the maximum \(PageMetrics.maximumWindowWidth) pt"
                : nil
        }
        snapshot.hasImage = false
        return [snapshot, titleCheck()]
    }

    /// The window is titled with the page it opens on, also when it opens again after a close (owner QA 2, R6: it
    /// showed the app's name). History, not Home, so a title that only ever says Home fails too. No image.
    private static func titleCheck() -> Snapshot {
        var titles: [String] = []
        var snapshot = Snapshot(name: "window-title") {
            let panes = [Pane.home(.sample), Pane(id: .history) { AnyView(EmptyView()) }]
            for _ in 0..<2 {
                let window = window(
                    showing: MainView(panes: panes, selection: Selection(panes: panes, showing: .history)))
                Snapshots.settle()
                titles.append(window.title)
                window.close()
            }
            return NSView()
        } check: { _ in
            titles.allSatisfy { $0 == PaneID.history.title }
                ? nil : "the window opened titled \(titles), not “\(PaneID.history.title)” each time"
        }
        snapshot.hasImage = false
        return snapshot
    }
}

extension MainWindow {
    /// A page with toolbar items (`pageSearch`, `pageToolbar`) beside one without: the title bar keeps one height
    /// (`switchSnapshot` fails on a move). The second image shows the toolbar.
    static func pageToolbarSnapshots() -> [Snapshot] {
        let panes = [
            Pane.home(.sample),
            Pane(id: .dictionary) { AnyView(ToolbarSample()) },
        ]
        return [
            switchSnapshot(of: panes, through: [.home, .dictionary, .home], named: "page-toolbar-switch"),
            windowSnapshot(of: panes, selecting: .dictionary, named: "page-toolbar", isFramed: true),
        ]
    }
}

private struct ToolbarSample: View {
    @State private var search = ""

    var body: some View {
        PageForm {
            Section {
                PageHeader(page: .dictionary, summary: "Words kotoba spells your way.")
            }
        }
        .pageSearch(text: $search, prompt: "Search Words")
        .pageToolbar {
            Button("Import from Wispr Flow", systemImage: "square.and.arrow.down") {}
            Button("Add Word", systemImage: "plus") {}
        }
    }
}
