import AppKit
import Observation
import SwiftUI

/// One page in the Settings sidebar. To add a pane, add its case to `SettingsPaneID` (the case order is the sidebar
/// order), write `extension SettingsPane { static func name(…) -> Self }` in its own file under App/Settings/ and add
/// it to the list in `SettingsController`.
struct SettingsPane: Identifiable {
    let id: SettingsPaneID
    let title: String
    let systemImage: String
    let content: @MainActor () -> AnyView
}

/// In sidebar order: the panes a new user needs first come first (docs/research/ux-polish.md W2).
enum SettingsPaneID: String, Hashable, CaseIterable {
    case general
    case speech
    case dictionary
    case microphones
}

/// The Settings window, built when the owner opens it and released when they close it. SwiftUI is used only for
/// on-demand windows (docs/spec.md, Platform and UI).
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 720, height: 480)

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
        // The window title follows the pane, as in System Settings.
        let view = SettingsView(panes: panes, selection: selection) { [weak self] title in self?.window?.title = title }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.defaultSize)
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
    let onTitle: (String) -> Void

    init(panes: [SettingsPane], selection: Selection, onTitle: @escaping (String) -> Void = { _ in }) {
        let order = SettingsPaneID.allCases
        self.panes = panes.sorted { order.firstIndex(of: $0.id) ?? 0 < order.firstIndex(of: $1.id) ?? 0 }
        self.selection = selection
        self.onTitle = onTitle
    }

    private var shown: SettingsPane? {
        panes.first { $0.id == selection.id } ?? panes.first
    }

    var body: some View {
        NavigationSplitView {
            List(panes, selection: $selection.id) { pane in
                Label(pane.title, systemImage: pane.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } detail: {
            if let pane = shown {
                pane.content()
                    .navigationTitle(pane.title)
            }
        }
        .frame(minWidth: 600, minHeight: 380)
        .onAppear { selection.id = selection.id ?? panes.first?.id }
        .onChange(of: shown?.title, initial: true) { _, title in onTitle(title ?? "Settings") }
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
            let view = Snapshots.hostingView(pane.content().frame(width: 540, height: height))
            view.setFrameSize(NSSize(width: 540, height: height))
            return view
        }
    }
}

extension SettingsWindow {
    /// The whole window content (sidebar and detail) at the window's size, for `make snapshots`. It stops the run when
    /// the content is taller or wider than the window: on 2026-10-15 a pane that grew past the window pushed the
    /// sidebar rows above its top and the footer below its bottom, so the window looked empty. The sidebar's
    /// selection and vibrancy do not render offscreen (the selected row is a dark block); the layout check does not
    /// depend on them.
    static func windowSnapshot(of panes: [SettingsPane], selecting id: SettingsPane.ID, named name: String)
        -> Snapshot
    {
        let overflow: @MainActor (NSView) -> String? = { view in
            view.subviews.first { $0.frame != view.bounds }.map {
                "Settings content is \($0.frame), the window is \(view.bounds)"
            }
        }
        return Snapshots.fixedWindow(named: name, size: defaultSize, check: overflow) {
            let selection = Selection()
            selection.id = id
            return SettingsView(panes: panes, selection: selection)
        }
    }
}
