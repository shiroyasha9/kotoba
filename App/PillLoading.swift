import AppKit
import KotobaCore

/// The light of the loading dots (`PillBars.isLoading`; owner pick "Dots + Rim", 2026-10-25): a soft coral spot goes
/// to and fro along the capsule under the dots, seen faintly inside the glass and brightly through a thin stroke of the
/// rim beside it, coral fading through pink. With Reduce Motion it keeps still: two arcs of coral, pink and purple on
/// the rim breathe slowly. It lies over the pill's content, clipped to the capsule as the glass changes shape, and takes
/// no click. Its loops start once the dots have gathered, run in the render server, and go with the light (`end`).
final class PillLoadingLight: NSView {
    /// The shares of the light's loop at which keyframes sit, 40 a second: the light's and the dots' loops share them.
    static let shares: [Double] = {
        let steps = Int(IndicatorMotion.loop * 40)
        return (0...steps).map { Double($0) / Double(steps) }
    }()
    private static let spot: CGFloat = 30
    private static let spotOpacity: CGFloat = 0.28
    private static let rimSpot: CGFloat = 50
    private static let rimWidth: CGFloat = 2
    private static let stillRimWidth: CGFloat = 1.6
    /// The rim's stroke sits this far inside the glass's edge, its edge feathered by this blur.
    private static let rimInset: CGFloat = 1
    private static let rimFeather: CGFloat = 1.2
    private static let stillLowest: Float = 0.35

    /// The capsule at rest, centred in the light: the spots' places along it.
    private let track = CALayer()
    private let rimTrack = CALayer()
    /// The rim: what shows through `edge`, a thin stroke of the capsule.
    private let ring = CALayer()
    private let edge = CAShapeLayer()
    private let inner = CAGradientLayer()
    private let outer = CAGradientLayer()
    /// Reduce Motion's rim: two arcs of a conic gradient.
    private let arcs = CAGradientLayer()
    private let isStill: Bool
    private let isVertical: Bool
    private let shape: NSSize
    private var laidOut: NSSize?

    /// The light for a capsule of `shape` (vertical at a side edge); `isStill` with Reduce Motion.
    init(shape: NSSize, isVertical: Bool, isStill: Bool) {
        self.shape = shape
        self.isVertical = isVertical
        self.isStill = isStill
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
        edge.fillColor = nil
        edge.strokeColor = CGColor(gray: 0, alpha: 1)
        edge.lineWidth = isStill ? Self.stillRimWidth : Self.rimWidth
        edge.shadowColor = CGColor(gray: 0, alpha: 1)
        edge.shadowOpacity = 1
        edge.shadowRadius = Self.rimFeather
        edge.shadowOffset = .zero
        ring.mask = edge
        track.bounds = CGRect(origin: .zero, size: shape)
        rimTrack.bounds = track.bounds
        if isStill {
            arcs.type = .conic
            arcs.startPoint = CGPoint(x: 0.5, y: 0.5)
            arcs.endPoint = CGPoint(x: 0.5, y: 0)
            // swiftlint:disable:next legacy_objc_type
            arcs.locations = [0, 0.1, 0.2, 0.3, 0.42, 0.5, 0.6, 0.7, 0.8, 0.92].map { NSNumber(value: $0) }
            ring.addSublayer(arcs)
        } else {
            for (spot, side) in [(inner, Self.spot), (outer, Self.rimSpot)] {
                spot.type = .radial
                spot.startPoint = CGPoint(x: 0.5, y: 0.5)
                spot.endPoint = CGPoint(x: 1, y: 1)
                // swiftlint:disable:next legacy_objc_type
                spot.locations = [0, 0.5, 1].map { NSNumber(value: $0) }
                spot.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            }
            track.addSublayer(inner)
            rimTrack.addSublayer(outer)
            ring.addSublayer(rimTrack)
            layer?.addSublayer(track)
        }
        layer?.addSublayer(ring)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillLoadingLight is built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The light was made for a capsule of `shape` standing this way, and still lights it.
    func fits(shape: NSSize, isVertical: Bool) -> Bool {
        superview != nil && shape == self.shape && isVertical == self.isVertical
    }

    /// Starts the light's loops at the pill's time `now`, so a pill on another clock (its clips) runs them on that clock:
    /// the spot's way from when the dots have gathered, or the still rim's breath from when they have settled.
    func start(at now: CFTimeInterval) {
        guard let layer else { return }
        updateColors()
        let start = now + (isStill ? IndicatorMotion.settle : IndicatorMotion.gather)
        // Offscreen (a snapshot) the light is there at once.
        if window?.isVisible == true {
            let fadeIn = CABasicAnimation(keyPath: "opacity")
            fadeIn.fromValue = 0
            fadeIn.duration = IndicatorMotion.lightFadeIn
            fadeIn.beginTime = start
            fadeIn.fillMode = .backwards
            layer.add(fadeIn, forKey: "fade")
        }
        if isStill {
            let breath = CABasicAnimation(keyPath: "opacity")
            breath.fromValue = Self.stillLowest
            breath.toValue = 1
            breath.duration = IndicatorMotion.stillBreath
            breath.autoreverses = true
            breath.repeatCount = .infinity
            breath.beginTime = start
            breath.fillMode = .backwards
            ring.add(breath, forKey: "breath")
            return
        }
        let length = isVertical ? shape.height : shape.width
        let places = Self.shares.map { share -> NSValue in
            let along = CGFloat(
                IndicatorMotion.light(at: share, middle: Double(length / 2), swing: PillBars.lightSwing))
            return NSValue(
                point: isVertical
                    ? CGPoint(x: shape.width / 2, y: shape.height - along) : CGPoint(x: along, y: shape.height / 2))
        }
        for spot in [inner, outer] {
            let way = CAKeyframeAnimation(keyPath: "position")
            way.values = places
            way.keyTimes(Self.shares)
            way.calculationMode = .linear
            way.duration = IndicatorMotion.loop
            way.repeatCount = .infinity
            way.beginTime = start
            way.fillMode = .backwards
            spot.add(way, forKey: "way")
        }
    }

    /// The text landed: the light fades out with the look change, then leaves the glass.
    func end() {
        guard let layer, window?.isVisible == true else {
            removeFromSuperview()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated { self?.removeFromSuperview() }
        }
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = layer.presentation()?.opacity ?? 1
        fadeOut.toValue = 0
        fadeOut.duration = IndicatorMotion.lightFadeOut
        layer.opacity = 0
        layer.add(fadeOut, forKey: "fade")
        CATransaction.commit()
    }

    /// The rim follows the glass's edge at every step of a change; the spots keep to the capsule at rest, centred.
    override func layout() {
        super.layout()
        // Each step of a morph lays the light out; a step with the same size has nothing new.
        guard bounds.size != laidOut else { return }
        laidOut = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        track.position = middle
        ring.frame = bounds
        rimTrack.position = middle
        edge.frame = bounds
        let rim = bounds.insetBy(dx: Self.rimInset, dy: Self.rimInset)
        let radius = max(0, min(rim.width, rim.height) / 2)
        let path = CGPath(roundedRect: rim, cornerWidth: radius, cornerHeight: radius, transform: nil)
        edge.path = path
        // The feather's shadow has its path set, so it needs no offscreen pass of its own.
        edge.shadowPath = path.copy(strokingWithWidth: edge.lineWidth, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        let side = hypot(bounds.width, bounds.height) + 2 * Self.rimWidth
        arcs.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        arcs.position = middle
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    /// The brand's coral fading through pink; the still rim's arcs in coral, pink and purple.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let (coral, pink, purple) = (PillBars.level, NSColor.systemPink, NSColor.systemPurple)
            for (spot, opacity) in [(inner, Self.spotOpacity), (outer, 1)] {
                spot.colors = [
                    coral.withAlphaComponent(opacity).cgColor, pink.withAlphaComponent(opacity * 0.6).cgColor,
                    purple.withAlphaComponent(0).cgColor,
                ]
            }
            let clear = coral.withAlphaComponent(0).cgColor
            let arc = [coral, pink, purple].map(\.cgColor)
            arcs.colors = [clear] + arc + [clear, clear] + arc + [clear]
        }
    }
}

/// The check after a paste: a stroke that draws itself once the glass is close to its circle, with a small bounce of
/// its own (the glass does not bounce), about the size of the `checkmark` symbol beside body text. Offscreen it shows
/// whole at once.
final class PillCheck: NSView {
    private let stroke = CAShapeLayer()
    private static let lineWidth: CGFloat = 2.4

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
        stroke.fillColor = nil
        stroke.lineWidth = Self.lineWidth
        stroke.lineCap = .round
        stroke.lineJoin = .round
        layer?.addSublayer(stroke)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillCheck is built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows or hides the check; `animated`, it draws itself on from the pill's time `now`, or fades as the glass leaves
    /// it. Reduce Motion: it draws on with no bounce.
    func show(_ isShown: Bool, animated: Bool, at now: CFTimeInterval) {
        guard let layer, (layer.opacity > 0) != isShown else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = isShown ? 1 : 0
        stroke.removeAllAnimations()
        layer.removeAllAnimations()
        guard animated else { return }
        guard isShown else {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.beginTime = now
            fade.duration = IndicatorMotion.checkLeave
            fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(fade, forKey: "fade")
            return
        }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.duration = IndicatorMotion.checkDraw
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let bounce = CASpringAnimation(
            perceptualDuration: IndicatorMotion.checkBounce.duration, bounce: IndicatorMotion.checkBounce.bounce)
        bounce.keyPath = "transform.scale"
        bounce.fromValue = IndicatorMotion.checkScale
        bounce.toValue = 1
        bounce.duration = bounce.settlingDuration
        for animation in PillView.reducesMotion ? [draw] : [draw, bounce] {
            animation.beginTime = now + IndicatorMotion.checkDelay
            animation.fillMode = .backwards
            stroke.add(animation, forKey: animation.keyPath)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stroke.frame = bounds
        // About the `checkmark` symbol's stroke at body size, from the middle.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.midX - 5.6, y: bounds.midY + 0.4))
        path.addLine(to: CGPoint(x: bounds.midX - 1.9, y: bounds.midY - 3.6))
        path.addLine(to: CGPoint(x: bounds.midX + 5.7, y: bounds.midY + 4.7))
        stroke.path = path
        effectiveAppearance.performAsCurrentDrawingAppearance {
            stroke.strokeColor = NSColor.systemGreen.cgColor
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }
}
