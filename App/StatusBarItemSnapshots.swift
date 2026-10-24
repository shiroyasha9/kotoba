import AppKit

extension StatusBarItem {
    /// The menu bar glyphs at 2x, in state order: ready, needs attention, listening (caret on), listening (caret
    /// off). Tinted like the menu bar, so each appearance shows its contrast.
    static func snapshots() -> [Snapshot] {
        [
            Snapshot(name: "menubar-icons") {
                let views = [idle, attention, idle, caretOff].map { image in
                    let view = NSImageView(image: image ?? NSImage())
                    view.imageScaling = .scaleProportionallyUpOrDown
                    view.contentTintColor = .labelColor
                    view.widthAnchor.constraint(equalToConstant: 36).isActive = true
                    view.heightAnchor.constraint(equalToConstant: 36).isActive = true
                    return view
                }
                let row = NSStackView(views: views)
                row.spacing = 16
                row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                return row
            }
        ]
    }
}
