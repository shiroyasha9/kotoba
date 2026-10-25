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

    private struct Change {
        let at: Double
        let move: PillView.GlassMove
        let isCheck: Bool
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
        // The pill's animations (the bars settling, the loading dots) run on the demo's clock, not the wall clock.
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
        if look == .done {
            // Offscreen the check shows whole at once; it draws itself on at the demo's time.
            view.check.show(false, animated: false, at: view.now)
            view.check.show(true, animated: true, at: view.now)
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
        let spring = IndicatorMotion.spring(
            from: ScreenRect(from), to: ScreenRect(view.glass.frame), reducesMotion: false)
        change = Change(
            at: time, move: PillView.GlassMove(from: from, to: view.glass.frame, spring: spring),
            isCheck: look == .done,
            entering: shown.filter { item in !places.contains { $0.0 === item } }, leaving: leaving.map(\.0))
    }

    /// The pill at the demo's `time`: its clock there, its glass on the spring's way, its items fading.
    func step(to time: Double) {
        view.layer?.timeOffset = clock + time
        guard let change else { return }
        let elapsed = time - change.at
        view.glass.frame = change.move.frame(at: elapsed)
        for item in change.leaving {
            let length = IndicatorMotion.leaveLength(beforeCheck: change.isCheck)
            item.alphaValue = 1 - UnitCurve.linear.value(at: min(1, elapsed / length))
        }
        for item in change.entering {
            let fadeIn = (elapsed - IndicatorMotion.enterDelay(isBars: item is PillBars)) / IndicatorMotion.enterLength
            item.alphaValue = UnitCurve.easeOut.value(at: min(1, max(0, fadeIn)))
        }
    }

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
