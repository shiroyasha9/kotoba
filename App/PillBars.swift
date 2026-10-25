import AppKit

/// The pill's level: every bar answers the live level at once, each with its own weight, so the whole row breathes with
/// the voice, as the Siri glow does; no history and no centre origin. The weights drift slowly and smoothly across the
/// row, one small step per level event: humps that shift as the voice goes on, never a scroll and never random jitter.
/// The bars move only when a level arrives: one short additive Core Animation tween per bar and event in the render
/// server, no timer and no display link. Custom because no system view draws a level as bars, and the pill stands
/// vertical at a side edge.
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
    /// A room's own noise (a level of about 0.01) moves a bar by less than half a point: under this the row stays
    /// dots, and nothing redraws.
    private static let floor: CGFloat = 0.02
    /// The capture sends a level every 100 ms (`CaptureWriter.measureLevel`). A tween lasts two of them, so the next
    /// level's tween starts while this one runs; the tweens add, and the bars glide from level to level with no step.
    private static let tween: CFTimeInterval = 0.2

    private let bars = (0..<count).map { _ in CALayer() }
    /// The level the bars show: 0 under `floor`.
    private var shown: CGFloat = 0
    /// The level events shown so far: the weights' clock, so the drift needs no timer and a snapshot is the same on
    /// every run.
    private var beat = 0

    var level: CGFloat = 0 {
        didSet {
            let next = level < Self.floor ? 0 : min(1, level)
            // A muted mic sends the same 0 ten times a second: over a row of dots nothing moves, nothing redraws.
            guard !isSweeping, next > 0 || shown > 0 else { return }
            shown = next
            // Reduce Motion: the weights keep still, and the bars follow only the voice.
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                beat += 1
            }
            respond()
        }
    }

    var isVertical = false {
        didSet {
            guard isVertical != oldValue else { return }
            // A tween runs along a bar's long side, which turns with the pill.
            for bar in bars {
                bar.removeAllAnimations()
            }
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
                shown = 0
                for bar in bars {
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

    override func layout() {
        super.layout()
        CATransaction.begin()
        // The settle into the sweep's dots takes 0.25 s; a resize or a turn moves the bars at once.
        if isSweeping {
            CATransaction.setAnimationDuration(0.25)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (index, bar) in bars.enumerated() {
            bar.bounds = Self.bounds(length: length(of: index), isVertical: isVertical)
            let along = CGFloat(index) * (Self.thickness + Self.gap) + Self.thickness / 2
            // Top to bottom when vertical, as the eye reads a column.
            bar.position =
                isVertical
                ? CGPoint(x: bounds.midX, y: bounds.height - along)
                : CGPoint(x: along, y: bounds.midY)
        }
        CATransaction.commit()
    }

    /// One level in: every bar takes its new length, and a tween from the old length glides it there. The tween is
    /// additive, so a level that comes before the last tween ends adds its own and the bar keeps its speed. Offscreen
    /// (a snapshot) the bars take their lengths at once.
    private func respond() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let tweens = window?.isVisible == true
        let key = "level-\(CACurrentMediaTime())"
        let side = isVertical ? "bounds.size.width" : "bounds.size.height"
        for (index, bar) in bars.enumerated() {
            let old = isVertical ? bar.bounds.width : bar.bounds.height
            let new = length(of: index)
            guard new != old else { continue }
            bar.bounds = Self.bounds(length: new, isVertical: isVertical)
            guard tweens else { continue }
            let tween = CABasicAnimation(keyPath: side)
            tween.isAdditive = true
            tween.fromValue = old - new
            tween.toValue = 0
            tween.duration = Self.tween
            tween.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // Each tween has its own key: a new one must not end the one still running.
            bar.add(tween, forKey: key)
        }
        CATransaction.commit()
    }

    /// Bar `index`'s length at the shown level: a dot at silence, at most the longest bar.
    private func length(of index: Int) -> CGFloat {
        let share = min(1, shown * Self.weight(of: index, at: beat))
        return Self.thickness + (Self.longest - Self.thickness) * share
    }

    /// Bar `index`'s share of the level at `beat`, from 0.4 to 1.2: three slow waves across the row, two drifting one
    /// way and one the other, so the humps swell, fade and wander with no direction to follow. The slowest takes about
    /// 6 s to come round at ten levels a second, the fastest about 13 s; no two bars have the same weight for long.
    private static func weight(of index: Int, at beat: Int) -> CGFloat {
        let place = Double(index)
        let time = Double(beat)
        let sum =
            0.5 * sin(0.8 * place + 0.105 * time)
            + 0.3 * sin(1.9 * place - 0.07 * time + 2)
            + 0.2 * sin(3.1 * place + 0.048 * time + 4)
        return CGFloat(0.8 + 0.4 * sum)
    }

    private static func bounds(length: CGFloat, isVertical: Bool) -> CGRect {
        isVertical
            ? CGRect(x: 0, y: 0, width: length, height: thickness)
            : CGRect(x: 0, y: 0, width: thickness, height: length)
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
