import AppKit
import SwiftUI

// MARK: - Snapshots

extension MainWindow {
    /// One pane at the size of the window's detail column, for `make snapshots`. Each pane's file registers its own
    /// snapshots with this. The sidebar and the toolbar (title, search field) need the real window: the sidebar's
    /// selection and vibrancy do not render offscreen, so they are not in the image.
    /// 760 x 600 is about the detail column at the default window size; a taller `height` shows a pane that scrolls in
    /// the window in full.
    static func snapshot(of pane: Pane, named name: String, height: CGFloat = 600) -> Snapshot {
        var snapshot = Snapshot(name: name) {
            let view = Snapshots.hostingView(pane.content().frame(width: 760, height: height))
            view.setFrameSize(NSSize(width: 760, height: height))
            return view
        }
        // A pane's list rows (History, Dictionary) take their measured heights in the window.
        snapshot.settlesInWindow = true
        return snapshot
    }

    /// The whole window content (sidebar and pane) at the default size, for `make snapshots`. It stops the run when
    /// the content is taller or wider than the window: on 2026-10-15 a pane that grew past the window pushed the
    /// sidebar rows above its top and the footer below its bottom, so the window looked empty. The sidebar's
    /// selection and vibrancy do not render offscreen (the selected row is a dark block); the layout check does not
    /// depend on them. `isFramed` draws the real window instead, title bar and toolbar included (a pane's toolbar
    /// buttons and search field); its macOS 26 glass sidebar draws blank offscreen.
    static func windowSnapshot(
        of panes: [Pane], selecting id: Pane.ID, named name: String, size: NSSize = defaultSize, isFramed: Bool = false
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
    /// `windowSnapshot` draws it, with the sidebar's selected row and labels in explicit colors (`drawsSidebarColors`)
    /// and "on" switches in the accent color (`ActiveSwitchStyle`).
    /// `isScrolledToEnd` shows the end of a pane that scrolls; 610 pt high, General's end then starts at a section.
    static func readmeSnapshot(
        of panes: [Pane], selecting id: Pane.ID, named name: String, isScrolledToEnd: Bool = false
    ) -> Snapshot {
        var snapshot = Snapshots.fixedWindow(named: name, size: NSSize(width: 960, height: 610), check: overflow) {
            MainView(panes: panes, selection: Selection(panes: panes, showing: id))
                .environment(\.drawsSidebarColors, true)
                .defaultScrollAnchor(isScrolledToEnd ? .bottom : nil)
                .toggleStyle(ActiveSwitchStyle())
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
        return Snapshots.window(named: name, contentSize: defaultSize) {
            let selection = Selection(panes: panes, showing: path.first)
            let window = window(showing: MainView(panes: panes, selection: selection))
            window.setContentSize(defaultSize)
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
    }
}

/// The README images' switches: "on" in the accent color, as in the active app. Offscreen AppKit draws an on switch's
/// track grey, because a snapshot run is never the active app; an off switch draws right, so it stays native. Custom:
/// a stand-in for the macOS 26 switch (36 x 16 pt, a white capsule knob), as `PillStandIn` stands in for glass.
private struct ActiveSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        if configuration.isOn {
            LabeledContent {
                Capsule()
                    .fill(Color(nsColor: .controlAccentColor))
                    .overlay(alignment: .trailing) {
                        Capsule().fill(.white).frame(width: 22, height: 13).padding(.horizontal, 1.5)
                    }
                    .frame(width: 36, height: 16)
            } label: {
                configuration.label
            }
        } else {
            Toggle(configuration).toggleStyle(.switch)
        }
    }
}
