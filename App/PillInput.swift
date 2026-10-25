import AppKit
import KotobaCore

// The pill's VoiceOver and pointer handling (`PillView`).

extension PillView {
    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        true
    }

    /// The idle pill with a click is a button ("Start Dictating"); every other look is a group that VoiceOver reads by
    /// its label, with the look's buttons as its children.
    override func accessibilityRole() -> NSAccessibility.Role? {
        isClickable && (look == .idle || look.isHover) ? .button : .group
    }

    /// Read when VoiceOver asks, so the recording's time is the time now.
    override func accessibilityLabel() -> String? {
        look.accessibilityLabel(at: .now, isClickable: isClickable)
    }

    override func accessibilityChildren() -> [Any]? {
        buttons
    }

    override func accessibilityPerformPress() -> Bool {
        guard accessibilityRole() == .button else { return false }
        onAction?(.click)
        return true
    }

    /// The look's role and children changed: VoiceOver reads the pill again. Not gated on VoiceOver: with it off the
    /// post costs about 80 ns, and reading `isVoiceOverEnabled` about 660 ns.
    func updateAccessibility() {
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    /// The buttons the look shows, in order.
    var buttons: [PillButtonHost] {
        stack.arrangedSubviews.compactMap { $0 as? PillButtonHost }
    }

    // MARK: Pointer

    /// Where the pointer counts as on the pill: the look's capsule, and around the idle bar (8 pt thin) and its hover
    /// half the capsule's height more. The hover's area holds the idle bar's, so the pointer that brings up the keys
    /// keeps them.
    var hoverRect: NSRect {
        let margin = look == .idle || look.isHover ? PillGeometry.height / 2 : 0
        return capsuleFrame.insetBy(dx: -margin, dy: -margin)
    }

    /// One area at the look's capsule, set again when the look or the room changes. A pill that appears under a still
    /// pointer gets no mouse-entered event, so the area starts inside when the pointer is there now, and its exit
    /// still comes.
    func trackHover() {
        if let hoverArea {
            removeTrackingArea(hoverArea)
        }
        let rect = hoverRect
        let isInside = window.map { rect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
        // kotoba is never the active app, so hover must work while it is inactive.
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        if isInside {
            options.insert(.assumeInside)
        }
        let area = NSTrackingArea(rect: rect, options: options, owner: self)
        addTrackingArea(area)
        hoverArea = area
        hoverChanged(to: isInside)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackHover()
    }

    /// Hover is where the pointer is now, not a count of enter and exit events (a lost exit left the idle bar showing
    /// its keys, owner trial round 2).
    private func hoverChanged(to isInside: Bool) {
        guard isInside != isHovering else { return }
        isHovering = isInside
        onHoverChanged?(isInside)
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged(to: hoverRect.contains(convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged(to: hoverRect.contains(convert(event.locationInWindow, from: nil)))
    }

    // MARK: Click and drag

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// The pill takes the pointer on its capsule only, so a click beside it reaches the app under it. A button takes
    /// its own clicks; the rest of the capsule is a drag handle, and a click where the look has one.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard hoverRect.contains(convert(point, from: superview)) else { return nil }
        let hit = super.hitTest(point)
        if let hit, buttons.contains(where: { hit.isDescendant(of: $0) }) {
            return hit
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        pressStart = NSEvent.mouseLocation
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressStart else { return }
        let point = NSEvent.mouseLocation
        if !isDragging {
            guard IndicatorPlacement.isDrag(from: ScreenPoint(pressStart), to: ScreenPoint(point)) else { return }
            isDragging = true
            onDragBegan?(pressStart)
        }
        onDragMoved?(point)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragEnded?(NSEvent.mouseLocation)
        } else if pressStart != nil, isClickable {
            onAction?(.click)
        }
        pressStart = nil
        isDragging = false
    }
}

extension PillLook {
    var isHover: Bool {
        if case .hover = self { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}
