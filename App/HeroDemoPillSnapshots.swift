import AppKit
import KotobaCore
import SwiftUI

/// The pill in its own window, as the panel has it, over a copy of the frame under it, so its glass refracts the
/// frame. The pill runs its own look changes (`PillView.morph`) on the demo's clock, as the pill's clips do
/// (`PillClips`): its layers' time and its glass's spring step with the demo.
@MainActor
final class DemoPill {
    let view = PillView(frame: .zero)
    private let window: DemoPillWindow
    private let backdrop = NSView()
    /// The window on the stage, in points from the stage's bottom left.
    private let frame: NSRect
    /// The pill's Core Animation time at the demo's start; the demo's time runs on from here (`step`).
    private let clock = CACurrentMediaTime()
    /// The demo's time now.
    private var time: Double = 0
    /// The glass's way since the last look change, while it still moves.
    private var move: (at: Double, move: PillView.GlassMove)?

    init(on stage: NSRect, appearance: NSAppearance) {
        let room = NSRect(
            IndicatorPlacement.room(at: .bottomCenter, thickness: PillGeometry.height, in: ScreenRect(stage)))
        frame = IndicatorPanel.windowFrame(around: room)
        window = DemoPillWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        backdrop.frame = NSRect(origin: .zero, size: frame.size)
        backdrop.wantsLayer = true
        window.contentView = backdrop
        view.frame = backdrop.bounds.insetBy(dx: PillGeometry.shadowMargin, dy: PillGeometry.shadowMargin)
        backdrop.addSubview(view)
        // The pill's animations (the bars settling, the loading dots, a look change) run on the demo's clock, not the
        // wall clock; so does its glass. The view has no layer until it asks for one.
        view.wantsLayer = true
        view.layer?.speed = 0
        view.levelsPerSecond = HeroDemo.fps
        view.glassClock = { [weak self] move in
            guard let self else { return }
            self.move = (self.time, move)
        }
    }

    /// The pill takes `look` at the demo's `time`; animated, it changes as on screen (`PillView.morph`), else it takes
    /// the look at once.
    func show(_ look: PillLook, at time: Double, isAnimated: Bool) {
        // The animations the look adds start at its time.
        setTime(time)
        window.isPlaying = isAnimated
        view.look = look
        window.isPlaying = true
        if !isAnimated {
            move = nil
        }
    }

    /// The pill at the demo's `time`: its clock there, its glass on the spring's way.
    func step(to time: Double) {
        setTime(time)
        guard let move else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.glass.frame = move.move.frame(at: time - move.at)
        CATransaction.commit()
        if time - move.at > move.move.spring.swiftUI.settlingDuration {
            self.move = nil
        }
    }

    private func setTime(_ time: Double) {
        self.time = max(self.time, time)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.layer?.timeOffset = clock + self.time
        CATransaction.commit()
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

/// The pill's window, never ordered in: while the demo plays it, the pill takes it as on screen and runs its look
/// changes; a look the pill takes at once comes while it is not.
private final class DemoPillWindow: NSWindow {
    var isPlaying = false
    override var isVisible: Bool { isPlaying }
}
