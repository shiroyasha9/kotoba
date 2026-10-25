import AppKit
import KotobaCore

/// The pill's level: every bar answers the live level at once, each with its own weight, so the whole row breathes with
/// the voice, as the Siri glow does; no history and no centre origin. The weights drift slowly and smoothly across the
/// row, one small step per level event: humps that shift as the voice goes on, never a scroll and never random jitter.
/// A rise shows fast and a fall lets go slowly (`IndicatorMotion.envelope`), and the loudest bars glow. The bars move
/// only when a level arrives: one short additive Core Animation tween per bar and event in the render server, no timer
/// and no display link. Custom because no system view draws a level as bars, and the pill stands vertical at a side
/// edge.
///
/// While text is on its way (`isLoading`), the bars settle to dots and gather into three, and a light goes to and fro
/// under them (`PillLoadingLight`): each dot brightens and grows as the light nears it. Core Animation loops in the
/// render server, worked out once as the loading starts and removed when it ends.
final class PillBars: NSView {
    static let count = PillGeometry.barCount
    static let thickness = PillGeometry.barThickness
    static let gap = PillGeometry.barGap
    /// The longest bar, along the capsule's short side; the capsule keeps `PillGeometry.inset` plus a bar's
    /// thickness free at each end.
    static var longest: CGFloat { PillGeometry.height - 2 * (PillGeometry.inset + thickness) }
    private static let loadingKey = "loading"
    /// A room's own noise (a level of about 0.01) moves a bar by less than half a point: under this the row stays
    /// dots, and nothing redraws.
    private static let floor: CGFloat = 0.02
    /// The level tweens' curve, made once: up to 27 animations take it at each level.
    private static let easeInEaseOut = CAMediaTimingFunction(name: .easeInEaseOut)
    /// The halo's blur on a loud bar.
    private static let haloRadius: CGFloat = 2.5

    private let bars = (0..<count).map { _ in CALayer() }
    /// The level the bars show: 0 under `floor`.
    private var shown: CGFloat = 0
    /// The level events shown so far, in steps of the capture's (`levelsPerSecond`): the weights' clock, so the drift
    /// needs no timer and a snapshot is the same on every run.
    private var beat: Double = 0
    /// How many levels a second come in: the capture sends ten. A source that sends more (a video frame by frame) takes
    /// a smaller step at each, so the humps wander at the same pace.
    var levelsPerSecond = Double(captureLevelsPerSecond)
    private static let captureLevelsPerSecond = 10

    var level: CGFloat = 0 {
        didSet {
            let held = IndicatorMotion.envelope(
                shown: Double(shown), level: Double(min(1, level)), levelsPerSecond: levelsPerSecond)
            let next = held < Self.floor ? 0 : CGFloat(held)
            // A muted mic sends the same 0 ten times a second: over a row of dots nothing moves, nothing redraws.
            guard !isLoading, next > 0 || shown > 0 else { return }
            shown = next
            // Reduce Motion: the weights keep still, and the bars follow only the voice.
            if !PillView.reducesMotion {
                beat += Double(Self.captureLevelsPerSecond) / levelsPerSecond
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
            restartLoading()
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

    /// Text is on its way: the dots and their light (`PillBars` above). The pill ends it once the bars have left.
    var isLoading = false {
        didSet {
            guard isLoading != oldValue else { return }
            if isLoading {
                shown = 0
                for bar in bars {
                    bar.removeAllAnimations()
                }
            }
            isGathered = isLoading && !PillView.reducesMotion
            needsLayout = true
            restartLoading()
        }
    }
    /// The dots stand in three groups while loading; with Reduce Motion they keep their places.
    private var isGathered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.cornerRadius = Self.thickness / 2
            // The halo on loud bars (`respond`): off until a bar is loud.
            bar.shadowRadius = Self.haloRadius
            bar.shadowOffset = .zero
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
        // The settle into the loading dots takes `IndicatorMotion.settle`; a resize or a turn moves the bars at once.
        if isLoading {
            CATransaction.setAnimationDuration(IndicatorMotion.settle)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (index, bar) in bars.enumerated() {
            bar.bounds = Self.bounds(length: length(of: index), isVertical: isVertical)
            CATransaction.begin()
            // The gather moves the dots with its own animation (`restartLoading`).
            CATransaction.setDisableActions(true)
            bar.position = position(of: isGathered ? Self.group(of: index) : index)
            CATransaction.commit()
        }
        CATransaction.commit()
    }

    /// Where bar `index` sits: top to bottom when vertical, as the eye reads a column.
    private func position(of index: Int) -> CGPoint {
        let along = Self.along(index)
        return isVertical ? CGPoint(x: bounds.midX, y: bounds.height - along) : CGPoint(x: along, y: bounds.midY)
    }

    /// The middle of bar `index` from the row's start.
    private static func along(_ index: Int) -> CGFloat {
        CGFloat(index) * (thickness + gap) + thickness / 2
    }

    /// The bar whose place bar `index` takes in the loading dots: the middle one of its three.
    private static func group(of index: Int) -> Int { index / 3 * 3 + 1 }

    /// One level in: every bar takes its new length, and a tween from the old length glides it there, fast up and slower
    /// down. The tween is additive, so a level that comes before the last tween ends adds its own and the bar keeps its
    /// speed. A loud bar glows: a soft shadow in its colour, its path set so it draws with no offscreen pass. Offscreen
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
            let halo = Self.halo(length: new)
            let oldHalo = bar.shadowOpacity
            let shown = halo > 0 || oldHalo > 0 ? bar.presentation() : nil
            let oldPath = shown?.shadowPath ?? bar.shadowPath
            bar.bounds = Self.bounds(length: new, isVertical: isVertical)
            bar.shadowOpacity = halo
            bar.shadowPath = halo > 0 || oldHalo > 0 ? Self.path(of: bar.bounds) : nil
            guard tweens else { continue }
            let duration = new > old ? IndicatorMotion.riseTween : IndicatorMotion.fallTween
            let tween = CABasicAnimation(keyPath: side)
            tween.isAdditive = true
            tween.fromValue = old - new
            tween.toValue = 0
            tween.duration = duration
            tween.timingFunction = Self.easeInEaseOut
            // Each tween has its own key: a new one must not end the one still running.
            bar.add(tween, forKey: key)
            guard halo > 0 || oldHalo > 0 else { continue }
            // The halo follows the bar: one animation each, which the next level's takes over from where it is.
            let glow = CABasicAnimation(keyPath: "shadowOpacity")
            glow.fromValue = shown?.shadowOpacity ?? oldHalo
            let path = CABasicAnimation(keyPath: "shadowPath")
            path.fromValue = oldPath ?? Self.path(of: bar.bounds)
            for animation in [glow, path] {
                animation.duration = duration
                animation.timingFunction = Self.easeInEaseOut
                bar.add(animation, forKey: animation.keyPath)
            }
        }
        CATransaction.commit()
    }

    /// A bar's halo at `length`: only the loud bars glow.
    private static func halo(length: CGFloat) -> Float {
        Float(IndicatorMotion.halo(share: Double((length - thickness) / (longest - thickness))))
    }

    private static func path(of bounds: CGRect) -> CGPath {
        CGPath(roundedRect: bounds, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil)
    }

    /// Bar `index`'s length at the shown level: a dot at silence, at most the longest bar.
    private func length(of index: Int) -> CGFloat {
        let share = min(1, shown * Self.weight(of: index, at: beat))
        return Self.thickness + (Self.longest - Self.thickness) * share
    }

    /// Bar `index`'s share of the level at `beat`, from 0.4 to 1.2: three slow waves across the row, two drifting one
    /// way and one the other, so the humps swell, fade and wander with no direction to follow. The slowest takes about
    /// 6 s to come round at ten levels a second, the fastest about 13 s; no two bars have the same weight for long.
    private static func weight(of index: Int, at beat: Double) -> CGFloat {
        let place = Double(index)
        let sum =
            0.5 * sin(0.8 * place + 0.105 * beat)
            + 0.3 * sin(1.9 * place - 0.07 * beat + 2)
            + 0.2 * sin(3.1 * place + 0.048 * beat + 4)
        return CGFloat(0.8 + 0.4 * sum)
    }

    private static func bounds(length: CGFloat, isVertical: Bool) -> CGRect {
        isVertical
            ? CGRect(x: 0, y: 0, width: length, height: thickness)
            : CGRect(x: 0, y: 0, width: thickness, height: length)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            for bar in bars {
                bar.backgroundColor = color.cgColor
                bar.shadowColor = color.cgColor
            }
        }
    }

    /// Every bar layer with a running animation, for the idle-cost check.
    var animatedLayers: [CALayer] {
        bars.filter { !($0.animationKeys() ?? []).isEmpty }
    }
}

// MARK: Loading

extension PillBars {
    /// The loading dots (`isLoading`): the dots gather into three, dimmed, as they settle; then a light goes to and fro
    /// under them from beyond one end to beyond the other, once each `IndicatorMotion.loop`, and each dot brightens and
    /// grows as the light nears it. Each dot's loop is worked out once, here, as keyframes the render server runs.
    /// Reduce Motion: the dots keep their places and dim, and only the rim light breathes (`PillLoadingLight`).
    private func restartLoading() {
        for bar in bars {
            bar.removeAnimation(forKey: Self.loadingKey)
            bar.removeAnimation(forKey: Self.lightKey)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // The gather's end, kept while loading; a dot rests at full size and opacity otherwise.
        for bar in bars {
            bar.opacity = isLoading ? (isGathered ? Self.gatheredOpacity : Self.stillOpacity) : 1
            bar.setAffineTransform(
                isGathered ? CGAffineTransform(scaleX: Self.gatheredScale, y: Self.gatheredScale) : .identity)
            bar.shadowOpacity = 0
        }
        guard isLoading else { return }
        // Offscreen (a snapshot) the dots are gathered or dimmed at once; only the light's loop runs.
        let moves = window?.isVisible == true
        // In the bars' own time, so a pill on another clock (its clips) starts the loading on that clock.
        let now = layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
        guard isGathered else {
            for bar in bars where moves {
                let dim = CABasicAnimation(keyPath: "opacity")
                dim.fromValue = 1
                dim.duration = IndicatorMotion.stillDim
                dim.beginTime = now
                dim.fillMode = .backwards
                bar.add(dim, forKey: Self.loadingKey)
            }
            return
        }
        let start = now + IndicatorMotion.gather
        let shares = PillLoadingLight.shares
        for (index, bar) in bars.enumerated() {
            if moves {
                bar.add(gather(index, at: now), forKey: Self.loadingKey)
            }
            // How near the light is to this dot at each step of its loop.
            let place = Double(Self.along(Self.group(of: index)))
            let nearness = shares.map {
                IndicatorMotion.nearness(
                    place - IndicatorMotion.light(at: $0, middle: Double(Self.middle), swing: Self.lightSwing))
            }
            let light = CAAnimationGroup()
            light.animations = [
                Self.rise("opacity", by: Self.lightOpacity, nearness: nearness, at: shares),
                Self.rise("transform.scale", by: Self.lightScale, nearness: nearness, at: shares),
            ]
            light.duration = IndicatorMotion.loop
            light.timingFunction = CAMediaTimingFunction(name: .linear)
            light.beginTime = start
            light.repeatCount = .infinity
            bar.add(light, forKey: Self.lightKey)
        }
    }

    /// Dot `index`'s move into its group's place as it dims and grows: from where the bars lay it, onto the gather's end
    /// that `restartLoading` keeps.
    private func gather(_ index: Int, at time: CFTimeInterval) -> CAAnimation {
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = NSValue(point: position(of: index))
        move.toValue = NSValue(point: position(of: Self.group(of: index)))
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        let dim = CABasicAnimation(keyPath: "opacity")
        dim.fromValue = 1
        let gather = CAAnimationGroup()
        gather.animations = [move, grow, dim]
        gather.duration = IndicatorMotion.gather
        gather.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gather.beginTime = time
        gather.fillMode = .backwards
        return gather
    }

    /// An additive rise of `keyPath` by up to `amount`, as near as the light is at each share of its loop.
    private static func rise(_ keyPath: String, by amount: Double, nearness: [Double], at shares: [Double])
        -> CAKeyframeAnimation
    {
        let rise = CAKeyframeAnimation(keyPath: keyPath)
        rise.values = nearness.map { $0 * amount }
        rise.keyTimes(shares)
        rise.calculationMode = .linear
        rise.isAdditive = true
        rise.duration = IndicatorMotion.loop
        return rise
    }

    /// The row's middle from its start, and how far the light goes each way from it: past the end dots.
    private static let middle = (along(0) + along(count - 1)) / 2
    static let lightSwing = Double(along(group(of: count - 1)) - middle) + IndicatorMotion.lightOvershoot
    private static let lightKey = "light"
    /// The gathered dots: three bars on each, each bar 1.8 times a dot and at half opacity; the light adds up to half
    /// an opacity and 0.8 of a dot's size.
    private static let gatheredScale: CGFloat = 1.8
    private static let gatheredOpacity: Float = 0.5
    private static let lightOpacity = 0.5
    private static let lightScale = 0.8
    /// Reduce Motion's dots: dimmed, still.
    private static let stillOpacity: Float = 0.6
}
