import AppKit

/// The 0.5.0 pill prototype's level: nine mirrored bars. Each level event enters at the centre bar and moves one bar
/// outward with the next event, so the bars move only when a level arrives: no timer and no display link. Custom
/// because no system view draws a level as bars, and the pill stands vertical at a side edge.
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

    private let bars = (0..<count).map { _ in CALayer() }
    /// The newest level first; bar `i` shows the level `|i - centre|` events old.
    private var history = [CGFloat](repeating: 0, count: count / 2 + 1)

    var level: CGFloat = 0 {
        didSet {
            let next = [max(0, min(1, level))] + history.dropLast()
            // A muted mic sends the same 0 ten times a second: nothing moves, nothing redraws.
            guard next != history, !isSweeping else { return }
            history = next
            needsLayout = true
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

    /// The level's colour: the accent, brighter on light glass (owner, 2026-10-24). Light glass over a warm backdrop
    /// dulls the plain accent; mixing in white washed it out, and a brightness lift of 0.2 kept its hue and read best
    /// on the gallery's colour band (0.35 went pink on pink).
    static let accent = NSColor(name: nil) { appearance in
        let accent = NSColor.controlAccentColor
        guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua, let rgb = accent.usingColorSpace(.sRGB) else {
            return accent
        }
        return NSColor(
            hue: rgb.hueComponent, saturation: rgb.saturationComponent,
            brightness: min(1, rgb.brightnessComponent + 0.2), alpha: rgb.alphaComponent)
    }

    /// The bars' fill: a system color, resolved again when the appearance changes.
    var color = PillBars.accent {
        didSet { updateColors() }
    }

    var isSweeping = false {
        didSet {
            guard isSweeping != oldValue else { return }
            if isSweeping {
                history = history.map { _ in 0 }
                needsLayout = true
            }
            restartSweep()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
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

    /// The share of a level that bar `distance` from the centre shows: a mirrored hump, highest in the middle.
    private static func envelope(_ distance: Int) -> CGFloat {
        1 - CGFloat(distance * distance) / 32
    }

    override func layout() {
        super.layout()
        let centre = Self.count / 2
        CATransaction.begin()
        // Short enough to follow speech, long enough that a level step does not jump.
        CATransaction.setAnimationDuration(isSweeping ? 0.25 : 0.08)
        for (index, bar) in bars.enumerated() {
            let distance = abs(index - centre)
            let share = history[distance] * Self.envelope(distance)
            let length = Self.thickness + (Self.longest - Self.thickness) * share
            let along = CGFloat(index) * (Self.thickness + Self.gap) + Self.thickness / 2
            bar.bounds =
                isVertical
                ? CGRect(x: 0, y: 0, width: length, height: Self.thickness)
                : CGRect(x: 0, y: 0, width: Self.thickness, height: length)
            // Top to bottom when vertical, as the eye reads a column.
            bar.position =
                isVertical
                ? CGPoint(x: bounds.midX, y: bounds.height - along)
                : CGPoint(x: along, y: bounds.midY)
        }
        CATransaction.commit()
    }

    /// One wave across the dots, left to right (top to bottom): each bar runs the same pulse a little after the one
    /// before it. Reduce Motion keeps the bars still and fades them in turn.
    private func restartSweep() {
        for bar in bars {
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
            for bar in bars {
                bar.backgroundColor = color.cgColor
            }
        }
    }

    /// Every bar layer with a running animation, for the idle-cost check.
    var animatedLayers: [CALayer] {
        bars.filter { !($0.animationKeys() ?? []).isEmpty }
    }
}
