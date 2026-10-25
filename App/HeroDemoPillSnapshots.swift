import AppKit
import KotobaCore
import SwiftUI

/// The pill in its own window, as the panel has it, over a copy of the frame under it, so its glass refracts the
/// frame. The demo moves its glass and fades its items between looks, and steps its Core Animation clock.
@MainActor
final class DemoPill {
    let view = PillView(frame: .zero)
    private let window: NSWindow
    private let backdrop = NSView()
    /// The window on the stage, in points from the stage's bottom left.
    private let frame: NSRect
    /// The pill's Core Animation time at the demo's start; the demo's time runs on from here (`step`).
    private let clock = CACurrentMediaTime()
    /// The last look change, while its glass and items still move.
    private var change: Change?
    /// Since when the check draws on, and the mask that uncovers it from its left.
    private var drawOn: (at: Double, mask: CALayer)?

    private struct Change {
        let at: Double
        let from: NSRect
        let to: NSRect
        let entering: [NSView]
        let leaving: [NSView]
    }

    init(on stage: NSRect, appearance: NSAppearance) {
        let room = NSRect(
            IndicatorPlacement.room(at: .bottomCenter, thickness: PillGeometry.height, in: ScreenRect(stage)))
        frame = IndicatorPanel.windowFrame(around: room)
        window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        backdrop.frame = NSRect(origin: .zero, size: frame.size)
        backdrop.wantsLayer = true
        window.contentView = backdrop
        view.frame = backdrop.bounds.insetBy(dx: PillGeometry.shadowMargin, dy: PillGeometry.shadowMargin)
        backdrop.addSubview(view)
        // The pill's animations (the bars settling and sweeping) run on the demo's clock, not the wall clock.
        view.layer?.speed = 0
        view.levelsPerSecond = HeroDemo.fps
    }

    /// The pill takes `look` at the demo's `time`; animated, its glass flows there with the pill's spring and its items
    /// fade as `PillView.morph` fades them. No item stays and moves in this demo's changes (the bars keep the centre),
    /// so there is no slide.
    func show(_ look: PillLook, at time: Double, isAnimated: Bool) {
        let places = view.stack.arrangedSubviews.map { ($0, view.stack.convert($0.frame, to: view.glassContent)) }
        let from = view.glass.frame
        // The animations the look adds start at its time.
        view.layer?.timeOffset = clock + time
        view.look = look
        // An item that faded out in an earlier change shows in full when a look takes it back.
        for item in view.stack.arrangedSubviews {
            item.alphaValue = 1
        }
        view.check.layer?.mask = nil
        drawOn = nil
        if look == .done {
            // The check's draw-on effect does not run in a window that is not on screen; this mask stands in for it.
            let mask = CALayer()
            mask.backgroundColor = CGColor(gray: 0, alpha: 1)
            view.check.layer?.mask = mask
            drawOn = (time, mask)
        }
        guard isAnimated else {
            change = nil
            return
        }
        let shown = view.stack.arrangedSubviews
        let leaving = places.filter { !shown.contains($0.0) }
        for (item, place) in leaving {
            view.park(item, at: place)
        }
        change = Change(
            at: time, from: from, to: view.glass.frame,
            entering: shown.filter { item in !places.contains { $0.0 === item } }, leaving: leaving.map(\.0))
    }

    /// The pill at the demo's `time`: its clock there, its glass on the spring's way, its items fading.
    func step(to time: Double) {
        view.layer?.timeOffset = clock + time
        if let drawOn {
            let check = view.check
            let symbol = check.image?.size.width ?? check.bounds.width
            let progress = UnitCurve.easeOut.value(at: min(1, (time - drawOn.at) / Self.drawOnLength))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            drawOn.mask.frame = NSRect(
                x: 0, y: 0, width: (check.bounds.width - symbol) / 2 + symbol * progress, height: check.bounds.height)
            CATransaction.commit()
        }
        guard let change else { return }
        let elapsed = time - change.at
        let progress = GlassSpring().spring.value(target: 1.0, time: elapsed)
        let from = change.from
        let to = change.to
        view.glass.frame = NSRect(
            x: from.minX + (to.minX - from.minX) * progress, y: from.minY + (to.minY - from.minY) * progress,
            width: from.width + (to.width - from.width) * progress,
            height: from.height + (to.height - from.height) * progress)
        for item in change.leaving {
            item.alphaValue = 1 - UnitCurve.easeIn.value(at: min(1, elapsed / PillView.fadeOutLength))
        }
        let fadeIn = (elapsed - PillView.fadeInDelay) / PillView.fadeInLength
        for item in change.entering {
            item.alphaValue = UnitCurve.easeOut.value(at: min(1, max(0, fadeIn)))
        }
    }

    /// How long the check takes to draw on, about as long as the symbol effect.
    private static let drawOnLength = 0.4

    /// `image` with the pill drawn over it at its place.
    func drawn(over image: CGImage) throws -> CGImage {
        let scale = HeroDemo.scale
        let pixels = CGRect(
            x: frame.minX * scale, y: (HeroDemo.stage.height - frame.maxY) * scale, width: frame.width * scale,
            height: frame.height * scale)
        guard let under = image.cropping(to: pixels) else { throw HeroDemo.DemoError.noBitmap }
        backdrop.layer?.contents = under
        window.layoutIfNeeded()
        let pill = try SnapshotCapture.image(of: window, scale: scale)
        let context = try HeroDemo.bitmap()
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.draw(
            pill,
            in: CGRect(
                x: pixels.minX, y: CGFloat(context.height) - pixels.maxY, width: pixels.width, height: pixels.height))
        guard let drawn = context.makeImage() else { throw HeroDemo.DemoError.noBitmap }
        return drawn
    }
}
