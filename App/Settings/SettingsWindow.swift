import AppKit
import Observation
import SwiftUI

/// One page in the Settings sidebar. To add a pane, add its case to `SettingsPaneID` (the case order is the sidebar
/// order) with its title, symbol, color and summary, write `extension SettingsPane { static func name(…) -> Self }` in
/// its own file under App/Settings/ and add it to the list in `SettingsController`.
struct SettingsPane: Identifiable {
    let id: SettingsPaneID
    let content: @MainActor () -> AnyView

    var title: String { id.title }
}

/// In sidebar order: the panes a new user needs first come first (docs/research/ux-polish.md W2).
enum SettingsPaneID: String, Hashable, CaseIterable {
    case general
    case speech
    case dictionary
    case microphones

    var title: String {
        switch self {
        case .general: "General"
        case .speech: "Speech"
        case .dictionary: "Dictionary"
        case .microphones: "Microphone"
        }
    }

    /// Filled symbols, white on the pane's color, as in System Settings.
    var systemImage: String {
        switch self {
        case .general: "gearshape.fill"
        case .speech: "waveform"
        case .dictionary: "character.book.closed.fill"
        case .microphones: "mic.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .speech: .blue
        case .dictionary: .orange
        case .microphones: .red
        }
    }

    /// The line under the pane's title at the top of the pane.
    var summary: String {
        switch self {
        case .general: "Your shortcut, how kotoba starts, and what it shows while you dictate."
        case .speech: "The speech model that turns your voice into text, and its key."
        case .dictionary: "Names and terms kotoba should know, and words to replace."
        case .microphones: "The mic kotoba records from, and how to test it."
        }
    }
}

/// A pane's symbol, white on a rounded square of the pane's color, as in the System Settings sidebar. Custom: SwiftUI
/// has no settings icon style.
struct SettingsIcon: View {
    let pane: SettingsPaneID
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

/// The first box of a pane: its icon, title and what it does, as at the top of a System Settings pane.
struct PaneHeader: View {
    let pane: SettingsPaneID

    var body: some View {
        HStack {
            SettingsIcon(pane: pane, size: 40)
            VStack(alignment: .leading) {
                Text(pane.title).font(.headline)
                Text(pane.summary).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
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
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(pane: pane.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            // System Settings keeps its sidebar: no toggle to hide it.
            .toolbar(removing: .sidebarToggle)
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
