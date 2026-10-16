import Foundation

/// The pane a window with a sidebar shows, and the panes shown before and after it for Back and Forward, as in System
/// Settings. The main window keeps one per open window (`App/MainWindow.swift`).
public struct PaneHistory<Pane: Hashable & Sendable>: Sendable, Equatable {
    public private(set) var current: Pane
    public private(set) var back: [Pane] = []
    public private(set) var forward: [Pane] = []
    /// The panes the window has; it never shows another.
    public let panes: Set<Pane>

    /// A new window, with no Back or Forward. It shows `named` (a click that names a pane, such as "Set API Key…"),
    /// else `last` (the pane the window showed when the owner last used it), else `home`. A pane the window does not
    /// have is skipped: History is missing when the history did not open.
    public init(panes: Set<Pane>, showing named: Pane?, last: Pane?, home: Pane) {
        self.panes = panes
        current = [named, last].lazy.compactMap { $0 }.first(where: panes.contains) ?? home
    }

    /// The owner shows `pane` (the sidebar, a pane's link, a menu item): the shown pane goes on the Back list and
    /// Forward empties. A pane the window does not have changes nothing, and so does nil: as in System Settings, a
    /// ⌘-click on the shown sidebar row leaves its pane shown.
    public mutating func select(_ pane: Pane?) {
        guard let pane, pane != current, panes.contains(pane) else { return }
        back.append(current)
        forward.removeAll()
        current = pane
    }

    public mutating func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(current)
        current = previous
    }

    public mutating func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(current)
        current = next
    }
}
