import AppKit

// The prototype pill's VoiceOver and pointer handling (`PillPrototypeView`).

extension PillPrototypeView {
    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool {
        true
    }

    /// The buttons the look shows; the bars, words and symbols are in the pill's label.
    override func accessibilityChildren() -> [Any]? {
        stack.arrangedSubviews.filter { $0 is PillFillButtonHost && !$0.isHidden }
    }

    override func accessibilityPerformPress() -> Bool {
        guard accessibilityRole() == .button else { return false }
        onAction?(.click)
        return true
    }

    // MARK: Mouse

    /// Hover follows the capsule, with a margin of half its height around the idle bar, which is only 8 pt tall; not
    /// the whole view (the gallery's cell is far larger than the pill).
    private var hoverRect: NSRect {
        let margin = PillGeometry.height / 2
        return glass.frame.insetBy(dx: -margin, dy: -margin)
    }

    /// Hover is where the pointer is now, not a count of enter and exit events: the pill used to add its own area
    /// again at each glass move, and a lost exit left the idle row showing its keys (owner trial, round 2). Only the
    /// pointer's moves over the view call this; at idle with the pointer away nothing runs.
    private func updateHover(with event: NSEvent?) {
        let isInside = event.map { hoverRect.contains(convert($0.locationInWindow, from: nil)) } ?? false
        if isInside, look == .idle, !hoverKeys.isEmpty {
            look = .hover(keys: hoverKeys)
        } else if !isInside, look.isHover, !hoverKeys.isEmpty {
            look = .idle
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(with: nil)
    }

    override func mouseUp(with event: NSEvent) {
        if hoverRect.contains(convert(event.locationInWindow, from: nil)) {
            onAction?(.click)
        }
    }
}
