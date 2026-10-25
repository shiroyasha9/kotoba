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
        NSAnimationContext.animate(reducesMotion ? .smooth(duration: 0.25) : Self.morphSpring) {
            placeGlass()
        }
    }

    /// Fluid with a small bounce, close to the system's own glass morphs; the content's slide takes the same curve.
    private static let morphSpring = Animation.spring(duration: 0.4, bounce: 0.15)

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
        let slide = CASpringAnimation(perceptualDuration: 0.4, bounce: 0.15)
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
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + (isReturning ? 0 : 0.08)
        fade.duration = 0.2
        fade.fillMode = .backwards
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.alphaValue = 1
        layer.add(fade, forKey: Self.fadeKey)
    }

    /// The item that goes stays where it was, out of the stack, and fades out while the glass changes shape around it;
    /// then it leaves the glass, unless the next look took it back. It takes no click (`hitTest` passes only the
    /// stack's buttons) and VoiceOver does not see it.
    private func fadeOut(_ view: NSView, at frame: NSRect) {
        let opacity = view.layer?.presentation()?.opacity ?? 1
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        view.frame = frame
        glassContent.addSubview(view, positioned: .below, relativeTo: stack)
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
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(fade, forKey: Self.fadeKey)
        CATransaction.commit()
    }

    private static let fadeKey = "fade"
}

/// The pill's one glass, a capsule at every size: the radius follows the size at each step of a morph. The spring that
/// moves the frame in process does not move `cornerRadius` (a done circle shrank to the idle bar as a rounded square).
final class CapsuleGlass: NSGlassEffectView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cornerRadius = min(newSize.width, newSize.height) / 2
    }
}
