import Testing

@testable import KotobaCore

struct InstallYieldTests {
    /// Each step's launched and quit release processes, and whether `isYielding` changed then.
    private static func changes(
        isRelease: Bool = false, _ steps: [(launched: [Int32], quit: [Int32])]
    ) -> (changes: [Bool], isYielding: Bool) {
        var yield = InstallYield(isRelease: isRelease)
        let changes = steps.map { yield.releaseChanged(launched: $0.launched, quit: $0.quit) }
        return (changes, yield.isYielding)
    }

    @Test func aDevelopmentBuildGivesWayWhileTheReleaseRuns() {
        #expect(!InstallYield(isRelease: false).isYielding)
        #expect(Self.changes([([501], [])]) == ([true], true))
        #expect(Self.changes([([501], []), ([], [501])]) == ([true, true], false))
    }

    @Test func theReleaseNeverGivesWay() {
        #expect(Self.changes(isRelease: true, [([501], [])]) == ([false], false))
    }

    @Test func itGivesWayUntilTheLastReleaseInstanceQuits() {
        #expect(Self.changes([([501, 502], []), ([], [501])]) == ([true, false], true))
        #expect(Self.changes([([501, 502], []), ([], [501]), ([], [502])]) == ([true, false, true], false))
    }

    @Test func aRepeatedLaunchOrAnUnknownQuitChangesNothing() {
        #expect(Self.changes([([501], []), ([501], []), ([], [999])]) == ([true, false, false], true))
    }

    /// The whole list replaced at once: the old instance quits and a new one runs, so the build keeps giving way
    /// with no moment of hotkeys on in between.
    @Test func aReplacedListKeepsGivingWay() {
        #expect(Self.changes([([501], []), ([601], [501])]) == ([true, false], true))
    }
}
