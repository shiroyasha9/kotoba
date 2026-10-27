import AppKit
import KotobaCore
import SwiftUI

// The pill's look change (`PillView.apply`): the glass flows to the new shape and the content follows it, with Siri's
// motion at the owner's pace (`IndicatorMotion`, docs/research/siri-motion.md).

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
        /// The pill comes from hidden, or goes.
        var fade: Fade?
    }

    enum Fade {
        /// The glass fades in as it opens out of the idle bar (`appear`).
        case appear
        /// The glass fades as it shrinks into the idle bar (`vanish`).
        case vanish
    }

    /// The glass's way for one look change: from its frame now to the look's capsule, with its spring.
    struct GlassMove {
        let from: NSRect
        let to: NSRect
        let spring: IndicatorMotion.Spring
    }

    /// Reduce Motion, from System Settings; the pill's clips also ask for it (`PillClips`).
    static var reducesMotion: Bool {
        prefersStill || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// The glass flows to the new shape with its spring (`IndicatorMotion.spring`: out of the idle bar and back into it
    /// with no bounce, a small overshoot as it grows, none as it shrinks), run in process so the glass lays itself out at
    /// each step and stays one capsule: a new change takes the spring over from where it is, at its speed. The content
    /// does not reflow: items that stay slide to their new places; new items fade in and sharpen, each only as far as
    /// the glass has opened over it; items that go shrink, blur and fade where they were, inside the glass that clips
    /// them. The content's animations run in the render server. Offscreen everything takes its place at once. Reduce
    /// Motion: no slide, scale or blur, and the pill fades in and out at its size.
    func morph(_ change: Change) {
        guard window?.isVisible == true else {
            placeAtOnce(change)
            return
        }
        // The new content takes its places in the stack; the glass has not moved yet.
        glassContent.layoutSubtreeIfNeeded()
        let reducesMotion = Self.reducesMotion
        let to = capsuleFrame
        let move = GlassMove(from: glass.frame, to: to, reducesMotion: reducesMotion)
        // With Reduce Motion the pill fades in and out at its size: the glass is at once where it ends, or stays.
        let movesGlass = !reducesMotion || change.fade == nil
        CATransaction.begin()
        for (view, offset) in change.staying where !reducesMotion {
            slide(view, from: offset, spring: move.spring)
        }
        for view in change.entering {
            let from = change.returning.contains(view) ? CGFloat(view.layer?.presentation()?.opacity ?? 0) : 0
            enter(view, from: from, glass: movesGlass ? move : GlassMove(from: to, to: to, spring: move.spring))
        }
        for (view, frame) in change.leaving {
            leave(view, at: frame, beforeCheck: look == .done)
        }
        if let fade = change.fade {
            fadeGlass(fade)
        }
        CATransaction.commit()
        guard movesGlass else {
            if change.fade == .appear {
                placeGlass()
            }
            return
        }
        if let glassClock {
            glassClock(move)
            return
        }
        NSAnimationContext.animate(Animation(GlassSpring(move.spring))) {
            placeGlass()
        }
    }

    /// Offscreen: the glass and every item at their places now. A hidden window may never end a fade-out, so its items
    /// leave the glass now; nor end a fade or its blur, so every item rests as it is, with no filter to draw.
    private func placeAtOnce(_ change: Change) {
        for view in glassContent.subviews where view !== stack && view !== check {
            view.removeFromSuperview()
            endLoading(of: view)
        }
        for layer in (stack.arrangedSubviews + change.leaving.map(\.view)).compactMap(\.layer) {
            layer.removeAnimation(forKey: Self.enterKey)
            layer.removeAnimation(forKey: Self.leaveKey)
            layer.filters = nil
        }
        placeGlass()
        needsLayout = true
    }

    /// The pill's time now. An item's own layer may not be in the pill's layer tree yet as it enters the stack, so its
    /// time could be another clock's (the clips'); in the tree it runs on the pill's.
    var now: CFTimeInterval {
        layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
    }

    /// The pill comes from hidden: the glass sits on the idle bar's place, see-through, before its window shows.
    func prepareToAppear() {
        placeGlass()
        glass.alphaValue = 0
    }

    /// Shows `look` as the pill appears (after `prepareToAppear`, its window on screen) or comes back as it goes: the
    /// glass opens out of the idle bar, or from where it is, and fades in.
    func appear(_ look: PillLook) {
        vanished = nil
        fadeToken += 1
        guard look != self.look else {
            fadeGlass(.appear)
            return
        }
        pendingFade = .appear
        self.look = look
    }

    /// The pill goes: the glass shrinks into the idle bar and fades over the end, its items going as in any change; with
    /// Reduce Motion it fades at its size. `done` runs once it has gone (at once offscreen), unless a look takes it back
    /// first (`appear`).
    func vanish(then done: @escaping () -> Void) {
        guard window?.isVisible == true else {
            look = .idle
            done()
            return
        }
        vanished = done
        fadeToken += 1
        guard look != .idle else {
            fadeGlass(.vanish)
            return
        }
        pendingFade = .vanish
        look = .idle
    }

    /// The pill is going (`vanish`) and has not gone yet.
    var isVanishing: Bool { vanished != nil }

    /// A glass fade ended (`fadeGlass`): the pill has gone if it was going and nothing took it back.
    func faded(_ token: Int) {
        guard token == fadeToken, let done = vanished else { return }
        vanished = nil
        done()
    }

    /// An item left the glass: the bars' loading dots and the loading light end with it.
    func endLoading(of view: NSView) {
        if view === bars, !look.isProcessing {
            bars.isLoading = false
        }
    }

    /// The item's centre from the content's centre: the content stays centred in the glass, so this is the item's place
    /// in the capsule.
    func offset(of view: NSView) -> CGPoint {
        CGPoint(x: view.frame.midX - stack.bounds.midX, y: view.frame.midY - stack.bounds.midY)
    }

    /// The item slides from its old place to its new one with the glass's spring. Additive, so a layout pass that sets
    /// its frame, or the next change's slide, does not cut it short.
    private func slide(_ view: NSView, from old: CGPoint, spring: IndicatorMotion.Spring) {
        let new = offset(of: view)
        guard let layer = view.layer, old != new else { return }
        let slide = CASpringAnimation(perceptualDuration: spring.duration, bounce: spring.bounce)
        slide.keyPath = "position"
        slide.isAdditive = true
        // The stack is flipped: a frame's y and its layer's y run the same way.
        slide.fromValue = NSValue(point: NSPoint(x: old.x - new.x, y: old.y - new.y))
        slide.toValue = NSValue(point: .zero)
        slide.duration = slide.settlingDuration
        slide.beginTime = now
        layer.add(slide, forKey: "slide-\(CACurrentMediaTime())")
    }

    /// The new item fades in from `from` after its delay (words first, then bars) and sharpens from a blur, but only as
    /// far as the glass on its way covers it (`IndicatorMotion.coverage`): worked out once from the glass's spring, as
    /// keyframes the render server runs. Never cut off by the glass's end, never outside it.
    private func enter(_ view: NSView, from start: CGFloat, glass move: GlassMove) {
        guard let layer = view.layer else { return }
        layer.removeAnimation(forKey: Self.leaveKey)
        let isHorizontal = move.to.width >= move.to.height
        let centre = Double(isHorizontal ? offset(of: view).x : offset(of: view).y)
        let extent = Double(isHorizontal ? view.frame.width : view.frame.height)
        let spring = move.spring.swiftUI
        let (from, to) = isHorizontal ? (move.from.width, move.to.width) : (move.from.height, move.to.height)
        let delay = IndicatorMotion.enterDelay(isBars: view is PillBars)
        // Long enough for the fade, and for the glass to have opened over the item.
        let length = max(delay + IndicatorMotion.enterLength, from < to ? spring.settlingDuration : 0)
        let steps = max(1, Int((length * Self.keyframesPerSecond).rounded(.up)))
        let times = (0...steps).map { length * Double($0) / Double(steps) }
        let opacities = times.map { time in
            let glass = Double(from) + Double(to - from) * spring.value(target: 1.0, time: time)
            let covered = IndicatorMotion.coverage(
                centre: centre, extent: extent, length: glass, inset: Double(PillGeometry.inset))
            return IndicatorMotion.enterOpacity(at: time, delay: delay, from: Double(start), coverage: covered)
        }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacities
        var parts: [CAAnimation] = [fade]
        // Words sharpen from a blur; bars only fade.
        if !Self.reducesMotion, !(view is PillBars) {
            let sharpen = CAKeyframeAnimation(keyPath: Self.blurPath)
            sharpen.values = opacities.map { IndicatorMotion.blur * (1 - $0) }
            parts.append(sharpen)
        }
        for part in parts {
            if let keyframes = part as? CAKeyframeAnimation {
                keyframes.keyTimes(times.map { $0 / length })
                keyframes.calculationMode = .linear
            }
        }
        run(parts, on: view, duration: length, key: Self.enterKey)
    }

    /// The item that goes stays where it was, out of the stack, and shrinks, blurs and fades while the glass changes
    /// shape around it; faster before the check, so the check never draws over it. Then it leaves the glass, unless the
    /// next look took it back. It takes no click (`hitTest` passes only the stack's buttons) and VoiceOver does not see
    /// it.
    private func leave(_ view: NSView, at frame: NSRect, beforeCheck: Bool) {
        let opacity = view.layer?.presentation()?.opacity ?? 1
        park(view, at: frame)
        view.alphaValue = 0
        guard let layer = view.layer else { return }
        layer.removeAnimation(forKey: Self.enterKey)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 0
        var parts: [CAAnimation] = [fade]
        if !Self.reducesMotion {
            let shrink = CABasicAnimation(keyPath: "transform")
            shrink.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
            shrink.toValue = NSValue(caTransform3D: Self.scale(layer, by: IndicatorMotion.leaveScale))
            let blur = CABasicAnimation(keyPath: Self.blurPath)
            blur.fromValue = 0
            blur.toValue = IndicatorMotion.blur
            parts += [shrink, blur]
        }
        let gone: @MainActor () -> Void = { [weak self, weak view] in
            guard let self, let view, view.superview === self.glassContent else { return }
            view.removeFromSuperview()
            self.endLoading(of: view)
        }
        run(
            parts, on: view, duration: IndicatorMotion.leaveLength(beforeCheck: beforeCheck), key: Self.leaveKey,
            then: gone)
    }

    /// Runs `parts` together on the item's layer from now. A blur needs its filter on the layer while it runs; the
    /// filter goes once no blur runs, so a still item draws with none.
    private func run(
        _ parts: [CAAnimation], on view: NSView, duration: Double, key: String,
        then done: (@MainActor () -> Void)? = nil
    ) {
        guard let layer = view.layer else { return }
        let blurs = parts.contains { ($0 as? CAPropertyAnimation)?.keyPath == Self.blurPath }
        if blurs, layer.filters?.isEmpty ?? true, let filter = CIFilter(name: "CIGaussianBlur") {
            filter.name = Self.blurName
            filter.setValue(0, forKey: kCIInputRadiusKey)
            layer.filters = [filter]
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in
            MainActor.assumeIsolated {
                if let layer, layer.animation(forKey: Self.enterKey) == nil,
                    layer.animation(forKey: Self.leaveKey) == nil
                {
                    layer.filters = nil
                }
                done?()
            }
        }
        for part in parts {
            part.duration = duration
        }
        let group = CAAnimationGroup()
        group.animations = parts
        group.duration = duration
        group.beginTime = now
        group.fillMode = .backwards
        layer.add(group, forKey: key)
        CATransaction.commit()
    }

    /// The pill's glass fades in as it opens, or fades over the end of its shrink into the idle bar; with Reduce Motion
    /// it fades at its size. A fade that goes ends the pill (`vanish`) when it is done.
    func fadeGlass(_ fade: Fade) {
        let from = glass.layer?.presentation()?.opacity ?? Float(glass.alphaValue)
        glass.alphaValue = fade == .appear ? 1 : 0
        // A glass with no layer yet draws nothing to fade.
        guard let layer = glass.layer else {
            faded(fadeToken)
            return
        }
        let reducesMotion = Self.reducesMotion
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        switch fade {
        case .appear:
            animation.duration = reducesMotion ? IndicatorMotion.stillFade : IndicatorMotion.appearFade
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animation.beginTime = now
        case .vanish:
            animation.duration = reducesMotion ? IndicatorMotion.stillFade : IndicatorMotion.vanishFade
            animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animation.beginTime = now + (reducesMotion ? 0 : IndicatorMotion.vanishFadeDelay)
        }
        animation.fillMode = .backwards
        CATransaction.begin()
        let token = fadeToken
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.faded(token) }
        }
        layer.add(animation, forKey: Self.glassFadeKey)
        CATransaction.commit()
    }

    /// The item that goes, out of the stack where it was, under the content, centred as the glass changes around it.
    func park(_ view: NSView, at frame: NSRect) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        view.frame = frame
        glassContent.addSubview(view, positioned: .below, relativeTo: stack)
    }

    /// A scale about the layer's middle: a view's layer turns about its corner.
    private static func scale(_ layer: CALayer, by scale: CGFloat) -> CATransform3D {
        let bounds = layer.bounds
        let middle = CGPoint(
            x: bounds.midX - (bounds.minX + layer.anchorPoint.x * bounds.width),
            y: bounds.midY - (bounds.minY + layer.anchorPoint.y * bounds.height))
        return CATransform3DConcat(
            CATransform3DMakeScale(scale, scale, 1),
            CATransform3DMakeTranslation(middle.x * (1 - scale), middle.y * (1 - scale), 0))
    }

    private static let enterKey = "enter"
    private static let leaveKey = "leave"
    private static let glassFadeKey = "fade"
    private static let blurName = "blur"
    private static let blurPath = "filters.\(blurName).inputRadius"
    /// The entering items' keyframes: about one a display frame.
    private static let keyframesPerSecond = 60.0
}

extension PillView.GlassMove {
    /// The glass's move from `from` to `to` with its spring for that change (`IndicatorMotion.spring`).
    init(from: NSRect, to: NSRect, reducesMotion: Bool) {
        self.init(
            from: from, to: to,
            spring: IndicatorMotion.spring(from: ScreenRect(from), to: ScreenRect(to), reducesMotion: reducesMotion))
    }
}
