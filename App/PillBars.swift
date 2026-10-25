import AppKit

/// The pill's level: a scrolling waveform, as in Voice Memos. Each level event enters as a new bar at the trailing edge
/// (the bottom when vertical) and every bar moves one place toward the leading edge, where the oldest leaves. The bars
/// move only when a level arrives: one short Core Animation slide per event in the render server, no timer and no
/// display link. Custom because no system view draws a level as bars, and the pill stands vertical at a side edge.
///
/// While text is on its way (`isSweeping`), the bars settle to dots and one slow wave runs across them: a Core
/// Animation loop in the render server, removed when the sweep ends.
final class PillBars: NSView {
    static let count = PillGeometry.barCount
    static let thickness = PillGeometry.barThickness
    static let gap = PillGeometry.barGap
    /// The longest bar, along the capsule's short side; the capsule keeps `PillGeometry.inset` plus a bar's
    /// thickness free at each end.
    static var longest: CGFloat { PillGeometry.height - 2 * (PillGeometry.inset + thickness) }
    private static let sweepScale = PillGeometry.sweepScale
    private static let sweepKey = "sweep"
    /// From one bar's place to the next.
    private static var pitch: CGFloat { thickness + gap }
    /// The capture sends a level every 100 ms (`CaptureWriter.measureLevel`). A slide lasts as long as the time since
    /// the last level when that is within `slides`, so the bars move at one steady speed while levels come.
    private static let levelInterval: CFTimeInterval = 0.1
    private static let slides: ClosedRange<CFTimeInterval> = 0.05...0.15

    /// One bar more than the places that show: the spare waits just before the leading edge, out of view (the view
    /// clips), and the next level reuses it. Place `i` holds `order[i + 1]`, so `order[0]` is the spare.
    private var order = (0...count).map { _ in CALayer() }
    /// Each place's level, oldest first; place `count - 1` is the newest.
    private var levels = [CGFloat](repeating: 0, count: count)
    private var lastLevelTime: CFTimeInterval = 0

    var level: CGFloat = 0 {
        didSet {
            let next = max(0, min(1, level))
            // A muted mic sends the same 0 ten times a second: over a row of dots nothing moves, nothing redraws.
            guard !isSweeping, next > 0 || levels.contains(where: { $0 > 0 }) else { return }
            levels.removeFirst()
            levels.append(next)
            scroll()
        }
    }

    var isVertical = false {
        didSet {
            guard isVertical != oldValue else { return }
            invalidateIntrinsicContentSize()
            needsLayout = true
            restartSweep()
        }
    }

    /// The level's colour: the brand colour, the icon's coral caret (asset `Brand`; owner, 2026-10-25), deeper on light
    /// glass. Coral is close in hue to a warm backdrop under the glass, so it reads by brightness there: on light glass
    /// the plain shade and a lighter one blended into pink and orange, and a 0.15 lower brightness read best on the
    /// gallery's colour band. The dark shade is already at full brightness, so dark glass takes it as it is.
    static let level = NSColor(name: nil) { appearance in
        let brand = NSColor(named: "Brand") ?? .controlAccentColor
        guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua else { return brand }
        var rgb: NSColor?
        appearance.performAsCurrentDrawingAppearance { rgb = brand.usingColorSpace(.sRGB) }
        guard let rgb else { return brand }
        return NSColor(
            hue: rgb.hueComponent, saturation: rgb.saturationComponent,
            brightness: max(0, rgb.brightnessComponent - 0.15), alpha: rgb.alphaComponent)
    }

    /// The bars' fill: a system color, resolved again when the appearance changes.
    var color = PillBars.level {
        didSet { updateColors() }
    }

    var isSweeping = false {
        didSet {
            guard isSweeping != oldValue else { return }
            if isSweeping {
                levels = levels.map { _ in 0 }
                for bar in order {
                    bar.removeAllAnimations()
                }
                needsLayout = true
            }
            restartSweep()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // The bar that leaves past the leading edge and the next one before it slides in stay out of view.
        layer?.masksToBounds = true
        for bar in order {
            bar.cornerRadius = Self.thickness / 2
            layer?.addSublayer(bar)
        }
        updateColors()
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillBars is built in code")
    }

    override var intrinsicContentSize: NSSize {
        let span = CGFloat(Self.count) * Self.thickness + CGFloat(Self.count - 1) * Self.gap
        return isVertical ? NSSize(width: Self.longest, height: span) : NSSize(width: span, height: Self.longest)
    }

    /// The bars in place order, leading edge first.
    private var bars: ArraySlice<CALayer> { order.dropFirst() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        // The settle into the sweep's dots takes 0.25 s; a resize or a turn moves the bars at once.
        if isSweeping {
            CATransaction.setAnimationDuration(0.25)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (place, bar) in order.enumerated() {
            setLength(of: bar, to: place == 0 ? 0 : levels[place - 1])
            bar.position = position(at: place - 1)
        }
        CATransaction.commit()
    }

    /// One level in: the spare bar jumps behind the trailing edge with the new level's length, and every bar slides
    /// one place toward the leading edge. The slide is additive, so a level that comes before the last slide ends adds
    /// its own and the speed stays even. Offscreen (a snapshot) the bars take their places at once.
    private func scroll() {
        let spare = order.removeFirst()
        order.append(spare)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The spare was out of view past the leading edge; its last slide no longer matters.
        spare.removeAllAnimations()
        setLength(of: spare, to: levels[Self.count - 1])
        for (place, bar) in order.enumerated() {
            bar.position = position(at: place - 1)
        }
        let now = CACurrentMediaTime()
        let since = now - lastLevelTime
        lastLevelTime = now
        // Reduce Motion: the levels step from place to place, with no slide.
        if window?.isVisible == true, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let slide = CABasicAnimation(keyPath: "position")
            slide.isAdditive = true
            let back = isVertical ? CGPoint(x: 0, y: -Self.pitch) : CGPoint(x: Self.pitch, y: 0)
            slide.fromValue = NSValue(point: back)
            slide.toValue = NSValue(point: .zero)
            slide.duration = Self.slides.contains(since) ? since : Self.levelInterval
            slide.timingFunction = CAMediaTimingFunction(name: .linear)
            for bar in order {
                // Each slide has its own key: a new one must not end the one still running.
                bar.add(slide, forKey: "slide-\(now)")
            }
        }
        CATransaction.commit()
    }

    private func setLength(of bar: CALayer, to level: CGFloat) {
        let length = Self.thickness + (Self.longest - Self.thickness) * level
        bar.bounds =
            isVertical
            ? CGRect(x: 0, y: 0, width: length, height: Self.thickness)
            : CGRect(x: 0, y: 0, width: Self.thickness, height: length)
    }

    /// The centre of place `place` (-1 is the spare's, before the leading edge): left to right, or top to bottom when
    /// vertical, as the eye reads a column.
    private func position(at place: Int) -> CGPoint {
        let along = CGFloat(place) * Self.pitch + Self.thickness / 2
        return isVertical ? CGPoint(x: bounds.midX, y: bounds.height - along) : CGPoint(x: along, y: bounds.midY)
    }

    /// One wave across the dots, left to right (top to bottom): each bar runs the same pulse a little after the one
    /// before it. Reduce Motion keeps the bars still and fades them in turn.
    private func restartSweep() {
        for bar in order {
            bar.removeAnimation(forKey: Self.sweepKey)
        }
        guard isSweeping else { return }
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // The settle (0.25 s in `layout`) ends before the wave starts.
        let start = CACurrentMediaTime() + 0.25
        for (index, bar) in bars.enumerated() {
            let fade = CABasicAnimation(keyPath: "opacity")
            // Dimmer between pulses, but still a clear row of dots on light and dark glass.
            fade.fromValue = 0.6
            fade.toValue = 1
            var parts: [CAAnimation] = [fade]
            if !reducesMotion {
                let grow = CABasicAnimation(keyPath: isVertical ? "transform.scale.x" : "transform.scale.y")
                grow.fromValue = 1
                grow.toValue = Self.sweepScale
                parts.append(grow)
            }
            let pulse = CAAnimationGroup()
            pulse.animations = parts
            pulse.duration = 0.6
            pulse.autoreverses = true
            // Every bar repeats the same pulse; the start offsets make the pulses one wave.
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.beginTime = start + Double(index) * 0.09
            pulse.fillMode = .backwards
            bar.add(pulse, forKey: Self.sweepKey)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for bar in order {
                bar.backgroundColor = color.cgColor
            }
        }
    }

    /// Every bar layer with a running animation, for the idle-cost check.
    var animatedLayers: [CALayer] {
        order.filter { !($0.animationKeys() ?? []).isEmpty }
    }
}
