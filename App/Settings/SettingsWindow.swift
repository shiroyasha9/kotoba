import AppKit
import Observation
import SwiftUI

/// One page in the Settings sidebar. To add a pane, add its case to `SettingsPaneID`, write
/// `extension SettingsPane { static func name(…) -> Self }` in its own file under App/Settings/ and add it to the
/// list in `SettingsController`.
struct SettingsPane: Identifiable {
    let id: SettingsPaneID
    let title: String
    let systemImage: String
    let content: @MainActor () -> AnyView
}

enum SettingsPaneID: String, Hashable {
    case dictionary
    case microphones
    case providers
}

/// The Settings window, built when the owner opens it and released when they close it. SwiftUI is used only for
/// on-demand windows (docs/spec.md, Platform and UI).
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let selection = Selection()

    /// Shows the window, building it with `panes` when it is not open. `id` picks the pane to show; nil keeps the
    /// pane already shown, or the first one.
    func show(_ panes: @autoclosure () -> [SettingsPane], selecting id: SettingsPane.ID? = nil) {
        let window = window ?? makeWindow(panes: panes())
        self.window = window
        if let id {
            selection.id = id
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        selection.id = nil
    }

    private func makeWindow(panes: [SettingsPane]) -> NSWindow {
        let view = SettingsView(panes: panes, selection: selection)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "kotoba Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 720, height: 480))
        window.setFrameAutosaveName("Settings")
        window.delegate = self
        window.center()
        return window
    }
}

/// The pane the sidebar shows; the window sets it to open on a pane.
@MainActor
@Observable
private final class Selection {
    var id: SettingsPane.ID?
}

private struct SettingsView: View {
    let panes: [SettingsPane]
    @Bindable var selection: Selection

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $selection.id) { pane in
                Label(pane.title, systemImage: pane.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            if let pane = panes.first(where: { $0.id == selection.id }) ?? panes.first {
                pane.content()
                    .navigationTitle(pane.title)
            }
        }
        .frame(minWidth: 600, minHeight: 380)
        .onAppear { selection.id = selection.id ?? panes.first?.id }
    }
}

// MARK: - Snapshots

extension SettingsWindow {
    /// One pane at the size of the window's detail column, for `make snapshots`. Each pane's file registers its own
    /// snapshots with this. The sidebar and the toolbar (title, search field) need the real window: the sidebar's
    /// selection and vibrancy do not render offscreen, so they are not in the image.
    /// `height` above the window's 440 shows a pane that scrolls in the window in full.
    static func snapshot(of pane: SettingsPane, named name: String, height: CGFloat = 440) -> Snapshot {
        Snapshot(name: name) {
            let view = NSHostingView(rootView: pane.content().frame(width: 540, height: height))
            view.setFrameSize(NSSize(width: 540, height: height))
            return view
        }
    }
}

extension SettingsWindow {
    static let defaultSize = NSSize(width: 720, height: 480)

    /// The whole window content (sidebar and detail) at the window's size, for `make snapshots`. It stops the run when
    /// the content is taller or wider than the window: on 2026-10-15 a pane that grew past the window pushed the
    /// sidebar rows above its top and the footer below its bottom, so the window looked empty. The sidebar's
    /// selection and vibrancy do not render offscreen (the selected row is a dark block); the layout check does not
    /// depend on them.
    static func windowSnapshot(of panes: [SettingsPane], selecting id: SettingsPane.ID, named name: String)
        -> Snapshot
    {
        Snapshot(name: name) {
            let selection = Selection()
            selection.id = id
            let view = NSHostingView(rootView: SettingsView(panes: panes, selection: selection))
            view.setFrameSize(defaultSize)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: defaultSize), styleMask: .borderless, backing: .buffered,
                defer: true)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            for content in view.subviews where content.frame != view.bounds {
                preconditionFailure("\(name): Settings content is \(content.frame), the window is \(view.bounds)")
            }
            window.contentView = nil
            return view
        }
    }
}
