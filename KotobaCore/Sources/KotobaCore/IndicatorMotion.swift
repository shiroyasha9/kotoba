import Foundation

/// The pill's motion (docs/research/siri-motion.md; owner pick 2026-10-25, QA 4 U8): Siri's measured timings at the
/// owner's pace. The pill grows out of the idle bar with no bounce, grows with a small overshoot and shrinks with none,
/// goes back into the idle bar; an item shows only where the glass covers it; the level rises at once and lets go
/// slowly. The app plays these values with Core Animation and the glass's spring; the choices live here.
public enum IndicatorMotion {
    /// The owner's pick: every measured timing at 0.75 of its speed, so each duration is the measured one ÷ 0.75.
    public static let pace = 0.75

    /// A spring by its perceptual duration and bounce, as SwiftUI's `Spring(duration:bounce:)`.
    public struct Spring: Equatable, Sendable {
        public let duration: Double
        public let bounce: Double

        init(_ duration: Double, bounce: Double = 0) {
            self.duration = duration / pace
            self.bounce = bounce
        }
    }

    /// Out of the idle bar: no bounce, as Siri opens out of the island.
    public static let opens = Spring(0.3)
    /// A longer capsule overshoots about 3%; a shorter one never does.
    public static let grows = Spring(0.38, bounce: 0.2)
    public static let shrinks = Spring(0.32)
    /// Reduce Motion: no bounce, a shorter change.
    public static let still = Spring(0.25)

    /// The glass's spring from `old` to `new`: out of the idle bar and back into it with no bounce, else by the
    /// capsule's long side. The check's circle is shorter than the idle bar's long side, yet going back into the bar is
    /// a shrink.
    public static func spring(from old: ScreenRect, to new: ScreenRect, reducesMotion: Bool) -> Spring {
        if reducesMotion { return still }
        if isIdleBar(old) { return opens }
        if isIdleBar(new) { return shrinks }
        return max(new.width, new.height) > max(old.width, old.height) ? grows : shrinks
    }

    private static func isIdleBar(_ shape: ScreenRect) -> Bool {
        min(shape.width, shape.height) <= IndicatorPlacement.idleBarThickness
    }

    // MARK: Items

    /// A new item fades in this long after the glass starts to open, words first; bars after them.
    public static func enterDelay(isBars: Bool) -> Double { (isBars ? 0.08 : 0.04) / pace }
    public static let enterLength = 0.15 / pace
    /// New words sharpen from this blur, and items that go blur out to it, in points.
    public static let blur = 4.0
    /// An item that goes fades, shrinks to `leaveScale` and blurs out where it was; faster before the check.
    public static func leaveLength(beforeCheck: Bool) -> Double { (beforeCheck ? 0.07 : 0.1) / pace }
    public static let leaveScale = 0.9

    /// How much of an item the glass covers along the capsule, 0 to 1: the item's centre `centre` from the capsule's
    /// middle, `extent` long, in glass `length` long that keeps `inset` free at each end. An item shows only as far as
    /// the glass has opened over it, so the shrinking glass never cuts words and new words never show outside it.
    public static func coverage(centre: Double, extent: Double, length: Double, inset: Double) -> Double {
        let half = length / 2 - inset
        let extent = max(1, extent)
        return min(1, max(0, (half - (abs(centre) + extent / 2)) / extent + 1))
    }

    /// An entering item's opacity `time` after the change began: its fade from `start`, held back to what the glass
    /// covers (`coverage`).
    public static func enterOpacity(at time: Double, delay: Double, from start: Double = 0, coverage: Double) -> Double
    {
        let step = min(1, max(0, (time - delay) / enterLength))
        // Ease out, as `CAMediaTimingFunction(name: .easeOut)` nearly does.
        let eased = 1 - (1 - step) * (1 - step)
        return min(start + (1 - start) * eased, coverage)
    }

    // MARK: Appear and go

    /// The glass fades in as it opens out of the idle bar; with Reduce Motion it fades in at its size.
    public static let appearFade = 0.12 / pace
    public static let stillFade = 0.15 / pace
    /// The glass shrinks into the idle bar and fades over the spring's end.
    public static let vanishFadeDelay = 0.2 / pace
    public static let vanishFade = 0.12 / pace

    // MARK: The check

    /// The check draws on once the glass is close to its circle, and bounces from `checkScale`, not the glass.
    public static let checkDelay = 0.05 / pace
    public static let checkDraw = 0.3 / pace
    public static let checkBounce = Spring(0.35, bounce: 0.25)
    public static let checkScale = 0.85
    /// The check fades as the glass leaves it.
    public static let checkLeave = 0.12 / pace

    // MARK: The level

    /// A level that rises shows fast; one that falls glides down.
    public static let riseTween = 0.08 / pace
    public static let fallTween = 0.2 / pace
    /// Halo on loud bars: a bar longer than this share of its range glows, up to `haloOpacity` at its longest.
    public static let haloFrom = 0.55
    public static let haloOpacity = 0.5

    /// The level the bars show after `level` comes in over `shown`: a rise shows at once; a fall lets go slowly, ×0.7
    /// each 100 ms at Siri's speed (a 280 ms time constant), as Siri's light follows the voice.
    public static func envelope(shown: Double, level: Double, levelsPerSecond: Double) -> Double {
        level >= shown ? level : max(level, shown * pow(0.7, 10 * pace / levelsPerSecond))
    }

    /// A bar's halo opacity at `share` of its range (0 a dot, 1 the longest).
    public static func halo(share: Double) -> Double {
        min(1, max(0, (share - haloFrom) / (1 - haloFrom))) * haloOpacity
    }

    // MARK: Loading

    /// The bars settle into dots this fast at the stop.
    public static let settle = 0.15 / pace
    /// The dots gather into three in `gather`; then the light starts its loop, to and fro once each `loop`.
    public static let gather = 0.3 / pace
    public static let loop = 2.2 / pace
    /// The light fades in as its loop starts, and out as the text lands.
    public static let lightFadeIn = 0.25 / pace
    public static let lightFadeOut = 0.15 / pace
    /// Reduce Motion: the dots dim and keep still, and the rim light breathes once each `stillBreath` there and back.
    public static let stillDim = 0.25 / pace
    public static let stillBreath = 1.6 / pace
    /// The light reaches 10 pt past each end dot, so it starts in the dark.
    public static let lightOvershoot = 10.0
    /// A dot within `lightReach` of the light brightens and grows, the more the closer.
    public static let lightReach = 12.0

    /// Where the light is `share` of the way through its loop: from `swing` before `middle` to `swing` past it and back,
    /// slow at each end.
    public static func light(at share: Double, middle: Double, swing: Double) -> Double {
        middle - swing * cos(2 * .pi * share)
    }

    /// How near the light is to a dot `distance` from it, 0 to 1: smooth, 0 beyond `lightReach`.
    public static func nearness(_ distance: Double) -> Double {
        let ratio = abs(distance) / lightReach
        return ratio < 1 ? pow(1 - ratio * ratio, 2) : 0
    }
}
