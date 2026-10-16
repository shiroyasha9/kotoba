import AppKit
import KotobaCore

/// The three drop targets shown while the owner drags the pill: a faint glass shape at each anchor,
/// the nearest one tinted. They live only for the drag.
@MainActor
final class DropTargets {
    private var targets: [IndicatorAnchor: (panel: NSPanel, glass: NSGlassEffectView)] = [:]
    /// The tinted target; a drag event that keeps it changes nothing.
    private var nearest: IndicatorAnchor?

    init(in visibleFrame: NSRect, contentWidth: CGFloat, below pill: NSPanel) {
        for anchor in IndicatorAnchor.allCases {
            let frame = NSRect(
                IndicatorPlacement.frame(
                    at: anchor, isCompact: true, contentWidth: contentWidth, in: ScreenRect(visibleFrame)))
            let glass = NSGlassEffectView()
            glass.style = .clear
            glass.cornerRadius = IndicatorPlacement.cornerRadius
            let panel = IndicatorPanel.makeFloatingPanel(holding: glass, frame: frame)
            panel.ignoresMouseEvents = true
            panel.alphaValue = 0.6
            panel.orderFrontRegardless()
            targets[anchor] = (panel, glass)
        }
        // The targets sit under the pill at the same window level.
        pill.orderFrontRegardless()
    }

    func highlight(_ nearest: IndicatorAnchor) {
        guard nearest != self.nearest else { return }
        self.nearest = nearest
        for (anchor, target) in targets {
            let isNearest = anchor == nearest
            target.glass.tintColor = isNearest ? .controlAccentColor : nil
            target.panel.alphaValue = isNearest ? 0.9 : 0.6
        }
    }

    func close() {
        for target in targets.values {
            target.panel.close()
        }
        targets = [:]
    }
}

extension ScreenPoint {
    init(_ point: NSPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension ScreenRect {
    init(_ rect: NSRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
    }
}

extension NSRect {
    init(_ rect: ScreenRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

// MARK: Floating panel

/// The window for the pill and for each drop target.
extension IndicatorPanel {
    /// Room around the glass in its window, so the shadow the glass draws is not cut off at the window edge.
    static let shadowMargin: CGFloat = 16

    /// The window frame for glass at `frame`: `shadowMargin` larger on each side.
    static func windowFrame(around frame: NSRect) -> NSRect {
        frame.insetBy(dx: -shadowMargin, dy: -shadowMargin)
    }

    /// A borderless, non-activating, clear panel that floats on every Space, for the pill and its drop targets.
    /// `content` fills `frame`; the window is `shadowMargin` larger, and its clear margin lets clicks through. It stays
    /// when kotoba is hidden (⌘H, or Hide Others in another app): a panel that can hide unhides every kotoba window when
    /// it is ordered in (docs/research/dock-app.md). It is not in the Window menu.
    static func makeFloatingPanel(holding content: NSView, frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: windowFrame(around: frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        let margin = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        content.frame = margin.bounds.insetBy(dx: shadowMargin, dy: shadowMargin)
        content.autoresizingMask = [.width, .height]
        margin.addSubview(content)
        panel.contentView = margin
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.canHide = false
        panel.isExcludedFromWindowsMenu = true
        return panel
    }
}
