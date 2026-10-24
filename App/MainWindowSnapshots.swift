import AppKit
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
            return Snapshots.fixedWindow(named: name, size: size, check: overflow) {
                MainView(panes: panes, selection: selection())
            }
        }
        return Snapshots.window(named: name, contentSize: size) {
            let window = window(showing: MainView(panes: panes, selection: selection()))
            // Set here: the window sets it when the pane appears, and an offscreen window shows no view.
            window.title = id.title
            return window
        } check: {
            overflow($0)
        }
    }

    /// The README images (`Pane.readmeSnapshots`, `make readme-images`): the whole window content at one size, as
    /// `windowSnapshot` draws it, each page from its top, so its header shows. The pane's scroll bar is not in the image.
    static func readmeSnapshot(of panes: [Pane], selecting id: Pane.ID, named name: String) -> Snapshot {
        var snapshot = Snapshots.fixedWindow(named: name, size: NSSize(width: 960, height: 610), check: overflow) {
            MainView(panes: panes, selection: Selection(panes: panes, showing: id), identity: .release)
                .scrollIndicators(.hidden)
        }
        snapshot.scale = 2
        return snapshot
    }

    /// Content that left the window's bounds: a pane taller than the window moves the split view.
    private static func overflow(_ content: NSView) -> String? {
        content.subviews.first { $0.frame != content.bounds }.map {
            "the window content is \($0.frame), the window is \(content.bounds)"
        }
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
