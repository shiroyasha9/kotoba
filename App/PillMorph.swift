import AppKit
import SwiftUI

// The pill's look change (`PillView.apply`): the glass flows to the new shape and the content follows it.

extension PillView {
    /// What a look change does to each item of the content.
    struct Change {
        /// In the old look and the new: each slides from its old place, given from the content's centre.
        var staying: [(view: NSView, offset: CGPoint)]
        /// New in the look, or with new words: each fades in.
        var entering: [NSView]
        /// Entering items that were still fading out: they fade in from where their fade-out got to.
        var returning: [NSView]
        /// In the old look only: each fades out where it was, its frame in the glass's content.
        var leaving: [(view: NSView, frame: NSRect)]
    }

    /// The glass flows to the new shape with one spring, run in process so the glass lays itself out at each step and
    /// stays one capsule: a new change takes the spring over from where it is, at its speed (recording, then the sweep,
    /// then the check). The content does not reflow: items that stay slide to their new places, new items fade in as the
    /// glass opens, and items that go fade out where they were, inside the glass that clips them. The content's
    /// animations run in the render server. Offscreen everything takes its place at once.
    func morph(_ change: Change) {
        guard window?.isVisible == true else {
            // A hidden window may never end a fade-out: its items leave the glass now.
            for view in glassContent.subviews where view !== stack && view !== check {
                view.removeFromSuperview()
            }
            placeGlass()
            needsLayout = true
            return
        }
        // The new content takes its places in the stack; the glass has not moved yet.
        glassContent.layoutSubtreeIfNeeded()
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        for (view, offset) in change.staying where !reducesMotion {
            slide(view, from: offset)
        }
        for view in change.entering {
            fade(view, isReturning: change.returning.contains(view))
        }
        for (view, frame) in change.leaving {
            fadeOut(view, at: frame)
        }
        CATransaction.commit()
        let spring = reducesMotion ? GlassSpring(spring: Spring(duration: 0.25, bounce: 0)) : GlassSpring()
        NSAnimationContext.animate(Animation(spring)) {
            placeGlass()
        }
    }

    /// The item's centre from the content's centre: the content stays centred in the glass, so this is the item's place
    /// in the capsule.
    func offset(of view: NSView) -> CGPoint {
        CGPoint(x: view.frame.midX - stack.bounds.midX, y: view.frame.midY - stack.bounds.midY)
    }

    /// The item slides from its old place to its new one with the glass's spring. Additive, so a layout pass that sets
    /// its frame, or the next change's slide, does not cut it short.
    private func slide(_ view: NSView, from old: CGPoint) {
        let new = offset(of: view)
        guard let layer = view.layer, old != new else { return }
        let slide = CASpringAnimation(perceptualDuration: GlassSpring.duration, bounce: GlassSpring.bounce)
        slide.keyPath = "position"
        slide.isAdditive = true
        // The stack is flipped: a frame's y and its layer's y run the same way.
        slide.fromValue = NSValue(point: NSPoint(x: old.x - new.x, y: old.y - new.y))
        slide.toValue = NSValue(point: .zero)
        slide.duration = slide.settlingDuration
        layer.add(slide, forKey: "slide-\(CACurrentMediaTime())")
    }

    /// The new item fades in as the glass opens around it.
    private func fade(_ view: NSView, isReturning: Bool) {
        guard let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = isReturning ? (layer.presentation()?.opacity ?? 0) : 0
        fade.toValue = 1
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + (isReturning ? 0 : Self.fadeInDelay)
        fade.duration = Self.fadeInLength
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: Self.fadeKey)
    }

    /// The item that goes stays where it was, out of the stack, and fades out while the glass changes shape around it;
    /// then it leaves the glass, unless the next look took it back. It takes no click (`hitTest` passes only the
    /// stack's buttons) and VoiceOver does not see it.
    private func fadeOut(_ view: NSView, at frame: NSRect) {
        let opacity = view.layer?.presentation()?.opacity ?? 1
        park(view, at: frame)
        view.alphaValue = 0
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak view] in
            MainActor.assumeIsolated {
                guard let self, let view, view.superview === self.glassContent else { return }
                view.removeFromSuperview()
            }
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 0
        fade.duration = Self.fadeOutLength
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(fade, forKey: Self.fadeKey)
        CATransaction.commit()
    }

    /// The item that goes, out of the stack where it was, under the content, centred as the glass changes around it.
    func park(_ view: NSView, at frame: NSRect) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        view.frame = frame
        glassContent.addSubview(view, positioned: .below, relativeTo: stack)
    }

    private static let fadeKey = "fade"
    /// A new item fades in once the glass has begun to open; an item that goes fades out faster.
    static let fadeInDelay = 0.08
    static let fadeInLength = 0.2
    static let fadeOutLength = 0.12
}

/// The glass's spring: fluid with a small bounce, close to the system's own glass morphs. It ends once the glass is within
/// a quarter point of its place and slower than 20 pt/s: SwiftUI's own spring runs on for an invisible tail, about 105
/// frames over 0.86 s against about 65 over 0.54 s, at about 1 ms of glass layout per frame (2026-10-25,
/// `<runbooks>/2026-10-24-kotoba-ui-redesign/pill-real/qa1-pill/`).
struct GlassSpring: CustomAnimation {
    static let duration = 0.4
    static let bounce = 0.15
    var spring = Spring(duration: duration, bounce: bounce)

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let now = spring.value(target: value, time: time)
        var left = value
        left -= now
        let speed = spring.velocity(target: value, time: time)
        return left.magnitudeSquared < 0.25 * 0.25 && speed.magnitudeSquared < 20 * 20 ? nil : now
    }

    /// A change that takes over mid-way starts at the glass's speed.
    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(target: value, time: time)
    }
}

/// The pill's one glass, a capsule at every size: the radius follows the size at each step of a morph. The spring that
/// moves the frame in process does not move `cornerRadius` (a done circle shrank to the idle bar as a rounded square).
final class CapsuleGlass: NSGlassEffectView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cornerRadius = min(newSize.width, newSize.height) / 2
    }
}
