import AppKit
import KotobaCore
import SwiftUI

/// The glass's spring (`IndicatorMotion.spring`). It ends once the glass is within a quarter point of its place and
/// slower than 20 pt/s: SwiftUI's own spring runs on for an invisible tail, about 105 frames over 0.86 s against about
/// 65 over 0.54 s, at about 1 ms of glass layout per frame (2026-10-25,
/// `<runbooks>/2026-10-24-kotoba-ui-redesign/pill-real/qa1-pill/`).
struct GlassSpring: CustomAnimation {
    let spring: Spring

    init(_ spring: IndicatorMotion.Spring) {
        self.spring = spring.swiftUI
    }

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let now = spring.value(target: value, time: time)
        var left = value
        left -= now
        let speed = spring.velocity(target: value, time: time)
        return left.magnitudeSquared < 0.25 * 0.25 && speed.magnitudeSquared < 20 * 20 ? nil : now
    }

    /// A change that takes over mid-way starts at the glass's speed.
    func velocity<V: VectorArithmetic>(value: V, time: TimeInterval, context: AnimationContext<V>) -> V? {
        spring.velocity(target: value, time: time)
    }
}

extension IndicatorMotion.Spring {
    var swiftUI: Spring { Spring(duration: duration, bounce: bounce) }
}

extension PillView.GlassMove {
    /// The glass's frame `time` into the move, from rest: what the in-process spring shows then, for a pill on another
    /// clock (its clips, the hero demo).
    func frame(at time: Double) -> NSRect {
        let progress = spring.swiftUI.value(target: 1.0, time: time)
        func blend(_ start: CGFloat, _ end: CGFloat) -> CGFloat { start + (end - start) * progress }
        return NSRect(
            x: blend(from.minX, to.minX), y: blend(from.minY, to.minY), width: max(0, blend(from.width, to.width)),
            height: max(0, blend(from.height, to.height)))
    }
}

extension CAKeyframeAnimation {
    /// Key times at `shares` of the animation, 0 to 1.
    func keyTimes(_ shares: [Double]) {
        // Core Animation takes its key times as NSNumbers.
        // swiftlint:disable:next legacy_objc_type
        keyTimes = shares.map { NSNumber(value: $0) }
    }
}

/// The pill's one glass, a capsule at every size: the radius follows the size at each step of a morph. The spring that
/// moves the frame in process does not move `cornerRadius` (a done circle shrank to the idle bar as a rounded square).
final class CapsuleGlass: NSGlassEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        cornerRadius = min(frame.width, frame.height) / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CapsuleGlass is built in code")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cornerRadius = min(newSize.width, newSize.height) / 2
    }
}
