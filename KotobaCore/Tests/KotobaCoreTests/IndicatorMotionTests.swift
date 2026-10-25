import Foundation
import Testing

@testable import KotobaCore

struct IndicatorMotionTests {
    private static let idleBar = ScreenRect(x: 0, y: 0, width: 40, height: 8)
    private static let handsFree = ScreenRect(x: 0, y: 0, width: 180, height: 36.5)
    private static let sweep = ScreenRect(x: 0, y: 0, width: 68, height: 36.5)
    private static let check = ScreenRect(x: 0, y: 0, width: 36.5, height: 36.5)

    @Test func theOwnersPaceSlowsEveryMeasuredTiming() {
        // Siri's measured 0.38 s grow at 0.75×.
        #expect(abs(IndicatorMotion.grows.duration - 0.38 / 0.75) < 1e-9)
        #expect(IndicatorMotion.grows.bounce == 0.2)
        #expect(abs(IndicatorMotion.loop - 2.2 / 0.75) < 1e-9)
    }

    @Test func theGlassOpensOutOfTheIdleBarWithNoBounce() {
        let spring = IndicatorMotion.spring(from: Self.idleBar, to: Self.handsFree, reducesMotion: false)
        #expect(spring == IndicatorMotion.opens)
        #expect(spring.bounce == 0)
        // Standing at a side edge too.
        let column = ScreenRect(x: 0, y: 0, width: 8, height: 40)
        #expect(IndicatorMotion.spring(from: column, to: Self.handsFree, reducesMotion: false) == IndicatorMotion.opens)
    }

    @Test func aLongerCapsuleOvershootsAndAShorterOneNever() {
        #expect(
            IndicatorMotion.spring(from: Self.sweep, to: Self.handsFree, reducesMotion: false) == IndicatorMotion.grows)
        #expect(
            IndicatorMotion.spring(from: Self.handsFree, to: Self.sweep, reducesMotion: false)
                == IndicatorMotion.shrinks)
        #expect(
            IndicatorMotion.spring(from: Self.sweep, to: Self.check, reducesMotion: false) == IndicatorMotion.shrinks)
        // Back into the idle bar: a shrink.
        #expect(
            IndicatorMotion.spring(from: Self.check, to: Self.idleBar, reducesMotion: false) == IndicatorMotion.shrinks)
        #expect(IndicatorMotion.shrinks.bounce == 0)
    }

    @Test func reduceMotionHasOneSpringWithNoBounce() {
        for (old, new) in [(Self.idleBar, Self.handsFree), (Self.sweep, Self.handsFree), (Self.handsFree, Self.check)] {
            #expect(IndicatorMotion.spring(from: old, to: new, reducesMotion: true) == IndicatorMotion.still)
        }
        #expect(IndicatorMotion.still.bounce == 0)
    }

    /// Words 40 pt long whose centre is 50 pt from the capsule's middle, in glass that keeps 6 pt free at each end.
    @Test func anItemShowsOnlyAsFarAsTheGlassCoversIt() {
        func covered(_ length: Double) -> Double {
            IndicatorMotion.coverage(centre: 50, extent: 40, length: length, inset: 6)
        }
        // The idle bar covers none of it; the glass reaches its near end at 2 × (30 + 6) and its far end at 2 × (70 + 6).
        #expect(covered(40) == 0)
        #expect(covered(72) == 0)
        #expect(abs(covered(112) - 0.5) < 1e-9)
        #expect(covered(152) == 1)
        #expect(covered(300) == 1)
        // The same on the other side of the middle.
        #expect(IndicatorMotion.coverage(centre: -50, extent: 40, length: 112, inset: 6) == covered(112))
    }

    @Test func aNewItemFadesInAfterItsDelayAndNeverPastTheGlass() {
        let delay = IndicatorMotion.enterDelay(isBars: false)
        #expect(IndicatorMotion.enterOpacity(at: delay, delay: delay, coverage: 1) == 0)
        #expect(IndicatorMotion.enterOpacity(at: delay + IndicatorMotion.enterLength, delay: delay, coverage: 1) == 1)
        #expect(IndicatorMotion.enterOpacity(at: 10, delay: delay, coverage: 0.3) == 0.3)
        // An item that was fading out comes back from where it got to.
        #expect(IndicatorMotion.enterOpacity(at: 0, delay: 0, from: 0.4, coverage: 1) == 0.4)
        // Bars come after words.
        #expect(IndicatorMotion.enterDelay(isBars: true) > delay)
    }

    @Test func theLevelRisesAtOnceAndLetsGoSlowly() {
        #expect(IndicatorMotion.envelope(shown: 0.2, level: 0.8, levelsPerSecond: 10) == 0.8)
        // At the capture's 10 levels a second a fall keeps 0.7 ^ 0.75 of the level each event.
        let fallen = IndicatorMotion.envelope(shown: 0.8, level: 0, levelsPerSecond: 10)
        #expect(abs(fallen - 0.8 * pow(0.7, 0.75)) < 1e-9)
        // A fall never goes under the new level.
        #expect(IndicatorMotion.envelope(shown: 0.8, level: 0.7, levelsPerSecond: 10) == 0.7)
        // A source with more levels a second lets go at the same pace in time.
        var shown = 0.8
        for _ in 0..<3 {
            shown = IndicatorMotion.envelope(shown: shown, level: 0, levelsPerSecond: 30)
        }
        #expect(abs(shown - fallen) < 1e-9)
    }

    @Test func onlyLoudBarsGlow() {
        #expect(IndicatorMotion.halo(share: 0) == 0)
        #expect(IndicatorMotion.halo(share: 0.55) == 0)
        #expect(IndicatorMotion.halo(share: 1) == IndicatorMotion.haloOpacity)
        #expect(IndicatorMotion.halo(share: 2) == IndicatorMotion.haloOpacity)
    }

    @Test func theLoadingLightGoesToAndFroAndBrightensTheDotItReaches() {
        #expect(IndicatorMotion.light(at: 0, middle: 34, swing: 25) == 9)
        #expect(abs(IndicatorMotion.light(at: 0.5, middle: 34, swing: 25) - 59) < 1e-9)
        #expect(abs(IndicatorMotion.light(at: 1, middle: 34, swing: 25) - 9) < 1e-9)
        #expect(IndicatorMotion.nearness(0) == 1)
        #expect(IndicatorMotion.nearness(IndicatorMotion.lightReach) == 0)
        #expect(IndicatorMotion.nearness(-6) == IndicatorMotion.nearness(6))
        #expect(IndicatorMotion.nearness(6) > IndicatorMotion.nearness(9))
    }
}
