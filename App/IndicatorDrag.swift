import AppKit
import KotobaCore

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

/// The pill's window.
extension IndicatorPanel {
    /// The window frame for glass at `frame`: `PillGeometry.shadowMargin` larger on each side.
    static func windowFrame(around frame: NSRect) -> NSRect {
        frame.insetBy(dx: -PillGeometry.shadowMargin, dy: -PillGeometry.shadowMargin)
    }

    /// A borderless, non-activating, clear panel that floats on every Space, for the pill.
    /// `content` fills `frame`; the window is `shadowMargin` larger, and its clear margin lets clicks through. It stays
    /// when kotoba is hidden (⌘H, or Hide Others in another app): a panel that can hide unhides every kotoba window when
    /// it is ordered in (docs/research/dock-app.md). It is not in the Window menu.
    static func makeFloatingPanel(holding content: NSView, frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: windowFrame(around: frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        let margin = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        content.frame = margin.bounds.insetBy(dx: PillGeometry.shadowMargin, dy: PillGeometry.shadowMargin)
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

    /// Puts a shown panel back on every Space when it is not on the one the owner is on. A panel made here joins all
    /// Spaces, but the window server can drop a Space from a long-lived one: on 2026-10-19 the pill (and Dia's floating
    /// panel) was on every Space but Desktop 1, while a new panel joined all of them. Setting the behavior again does
    /// nothing, and a clear and a set in one Core Animation transaction send no change; the flush sends the clear
    /// first, so the set joins every Space again (10 of 10 broken panels in a spike, 0 of 4 without the flush).
    static func rejoinAllSpaces(_ panel: NSPanel) {
        guard panel.isVisible, !panel.isOnActiveSpace else { return }
        Log.app.info("Indicator rejoins all Spaces")
        let behavior = panel.collectionBehavior
        panel.collectionBehavior = []
        CATransaction.flush()
        panel.collectionBehavior = behavior
    }
}

// MARK: Drag

extension IndicatorPanel {
    /// A drag of the pill: the press it began from and the window's frame then.
    struct Drag {
        let press: NSPoint
        let frame: NSRect
    }

    /// The pill itself moves with the pointer, in its look: no other shape, window or marker shows.
    func beginDrag(from press: NSPoint) {
        drag = Drag(press: press, frame: panel.frame)
        moveDrag(to: NSEvent.mouseLocation)
    }

    /// The window keeps its size, so the pill's layout and glass do not change while it moves.
    func moveDrag(to point: NSPoint) {
        guard let drag else { return }
        let room = IndicatorPlacement.draggedRoom(
            ScreenRect(drag.frame), from: ScreenPoint(drag.press), to: ScreenPoint(point))
        panel.setFrameOrigin(NSPoint(x: room.x, y: room.y))
    }

    /// The pill snaps to the anchor nearest its capsule's centre, on the screen that holds that centre, and saves it;
    /// every later pill shows there. Without a point (the pill hid during the drag) the drag only ends.
    func endDrag(at point: NSPoint? = nil) {
        guard drag != nil else { return }
        drag = nil
        guard point != nil else { return }
        let capsule = panel.convertToScreen(pill.convert(pill.capsuleFrame, to: nil))
        let centre = NSPoint(x: capsule.midX, y: capsule.midY)
        if let dropScreen = NSScreen.screens.first(where: { $0.frame.contains(centre) }) {
            screen = dropScreen
        }
        guard let screen else { return }
        anchor = IndicatorPlacement.nearestAnchor(
            to: ScreenPoint(centre), thickness: Double(PillGeometry.height), in: ScreenRect(screen.visibleFrame))
    }
}
