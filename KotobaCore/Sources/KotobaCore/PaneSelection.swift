import Foundation

/// The pane a window with a sidebar shows. The main window keeps one per open window (`App/MainWindow.swift`). It has no
/// Back and Forward: about nine pages and no drill-downs (docs/research/ui-redesign.md, "Window").
public struct PaneSelection<Pane: Hashable & Sendable>: Sendable, Equatable {
    public private(set) var current: Pane
    /// The panes the window has; it never shows another.
    public let panes: Set<Pane>

    /// A new window. It shows `named` (a click that names a pane, such as "Set API Key…"), else `last` (the pane the
    /// window showed when the owner last used it), else `home`. A pane the window does not have is skipped: History is
    /// missing when the history did not open.
    public init(panes: Set<Pane>, showing named: Pane?, last: Pane?, home: Pane) {
        self.panes = panes
        current = [named, last].lazy.compactMap { $0 }.first(where: panes.contains) ?? home
    }

    /// The owner shows `pane` (the sidebar, a page's link, a menu item). A pane the window does not have changes
    /// nothing, and so does nil: as in System Settings, a ⌘-click on the shown sidebar row leaves its pane shown.
    public mutating func select(_ pane: Pane?) {
        guard let pane, panes.contains(pane) else { return }
        current = pane
    }
}
