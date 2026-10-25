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

/// The guides shown while the owner drags the pill: at each anchor the idle bar where it sits there, a faint clear
/// glass capsule, the nearest one tinted (owner QA 4, U3: the guides match the pill's shape, never a circle). Each is
/// its own panel, never on the pill's glass. They are made when a drag starts and closed when it ends, so idle holds
/// none.
@MainActor
final class DropGuides {
    let screen: NSScreen
    private var guides: [IndicatorAnchor: (panel: NSPanel, glass: NSGlassEffectView)] = [:]
    /// The tinted guide; a drag event that keeps it changes nothing.
    private var nearest: IndicatorAnchor?

    init(on screen: NSScreen, below pill: NSPanel) {
        self.screen = screen
        for anchor in IndicatorAnchor.allCases {
            let frame = Self.frame(at: anchor, on: screen)
            let glass = Self.glass(size: frame.size)
            let panel = IndicatorPanel.makeFloatingPanel(holding: glass, frame: frame)
            panel.ignoresMouseEvents = true
            panel.alphaValue = Self.alpha(isNearest: false)
            panel.orderFrontRegardless()
            guides[anchor] = (panel, glass)
        }
        // The guides sit under the pill at the same window level.
        pill.orderFrontRegardless()
    }

    /// The guide's frame at `anchor` on `screen`: the idle bar there.
    static func frame(at anchor: IndicatorAnchor, on screen: NSScreen) -> NSRect {
        NSRect(
            IndicatorPlacement.guide(
                at: anchor, thickness: Double(PillGeometry.height), in: ScreenRect(screen.visibleFrame)))
    }

    /// A guide's glass: the pill's capsule shape, clear.
    static func glass(size: NSSize) -> NSGlassEffectView {
        let glass = CapsuleGlass(frame: NSRect(origin: .zero, size: size))
        glass.style = .clear
        return glass
    }

    static func tint(_ glass: NSGlassEffectView, isNearest: Bool) {
        glass.tintColor = isNearest ? .controlAccentColor : nil
    }

    static func alpha(isNearest: Bool) -> CGFloat {
        isNearest ? 0.9 : 0.6
    }

    func highlight(_ nearest: IndicatorAnchor) {
        guard nearest != self.nearest else { return }
        self.nearest = nearest
        for (anchor, guide) in guides {
            let isNearest = anchor == nearest
            Self.tint(guide.glass, isNearest: isNearest)
            guide.panel.alphaValue = Self.alpha(isNearest: isNearest)
        }
    }

    func close() {
        for guide in guides.values {
            guide.panel.close()
        }
        guides = [:]
    }
}

extension IndicatorPanel {
    /// A drag of the pill: the press it began from, the window's frame then, and the guides on the screen under the
    /// pill now.
    struct Drag {
        let press: NSPoint
        let frame: NSRect
        var guides: DropGuides
    }

    /// The pill itself moves with the pointer, in its look; the guides show where it can land.
    func beginDrag(from press: NSPoint) {
        guard let screen = screen ?? NSScreen.focused else { return }
        drag = Drag(press: press, frame: panel.frame, guides: DropGuides(on: screen, below: panel))
        moveDrag(to: NSEvent.mouseLocation)
    }

    /// The window keeps its size, so the pill's layout and glass do not change while it moves. The guides follow the
    /// screen under the pill's centre, and the one it would snap to is tinted.
    func moveDrag(to point: NSPoint) {
        guard var drag else { return }
        let room = IndicatorPlacement.draggedRoom(
            ScreenRect(drag.frame), from: ScreenPoint(drag.press), to: ScreenPoint(point))
        panel.setFrameOrigin(NSPoint(x: room.x, y: room.y))
        let centre = capsuleCentre
        if let under = NSScreen.screens.first(where: { $0.frame.contains(centre) }), under != drag.guides.screen {
            drag.guides.close()
            drag.guides = DropGuides(on: under, below: panel)
            self.drag = drag
        }
        drag.guides.highlight(nearestAnchor(to: centre, on: drag.guides.screen))
    }

    /// The pill snaps to the anchor nearest its capsule's centre, on the guides' screen, and saves it; every later pill
    /// shows there. Without a point (the pill hid during the drag) the drag only ends. The guides close either way.
    func endDrag(at point: NSPoint? = nil) {
        guard let drag else { return }
        drag.guides.close()
        self.drag = nil
        guard point != nil else { return }
        screen = drag.guides.screen
        anchor = nearestAnchor(to: capsuleCentre, on: drag.guides.screen)
    }

    /// The pill's capsule's centre on the screen.
    private var capsuleCentre: NSPoint {
        let capsule = panel.convertToScreen(pill.convert(pill.capsuleFrame, to: nil))
        return NSPoint(x: capsule.midX, y: capsule.midY)
    }

    private func nearestAnchor(to point: NSPoint, on screen: NSScreen) -> IndicatorAnchor {
        IndicatorPlacement.nearestAnchor(
            to: ScreenPoint(point), thickness: Double(PillGeometry.height), in: ScreenRect(screen.visibleFrame))
    }
}
