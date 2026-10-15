import Testing

@testable import KotobaCore

/// The no-sound warning over meter levels, one level each 100 ms as the meter sends them at 48 kHz.
///
/// Levels come from the owner's recordings (App/CaptureWriter.swift scale, RMS x 8): a quiet room metered 0.0053 to
/// 0.012 before the first word, speech 0.25 to 1, a muted mic 0.
struct NoSoundPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        /// One level each 100 ms, the first at 0.1 s after the recording started.
        let levels: [Float]
        /// Each change of the warning: the time of the level that changed it, and the new value.
        let changes: [(at: Duration, isWarning: Bool)]

        var testDescription: String { name }
    }

    static func run(_ step: Float, for duration: Duration) -> [Float] {
        Array(repeating: step, count: Int(duration / .milliseconds(100)))
    }

    static let cases: [Case] = [
        Case(name: "a muted mic warns after 2 s", levels: run(0, for: .seconds(3)), changes: [(.seconds(2), true)]),
        Case(
            name: "near silence under the floor warns", levels: run(0.0015, for: .seconds(3)),
            changes: [(.seconds(2), true)]),
        Case(
            name: "a quiet room never warns",
            levels: run(0.0053, for: .seconds(10)) + run(0.012, for: .seconds(10)), changes: []),
        Case(name: "a level at the floor is sound", levels: run(NoSoundPolicy.floor, for: .seconds(5)), changes: []),
        Case(
            name: "speech that starts before 2 s never warns",
            levels: run(0, for: .milliseconds(1_900)) + run(0.4, for: .seconds(3)), changes: []),
        Case(
            name: "speech that starts late clears the warning",
            levels: run(0, for: .seconds(3)) + run(0.4, for: .seconds(1)),
            changes: [(.seconds(2), true), (.milliseconds(3_100), false)]),
        Case(
            name: "a mic that goes silent mid-recording warns 2 s after its last sound",
            levels: run(0.4, for: .seconds(5)) + run(0, for: .seconds(3)), changes: [(.seconds(7), true)]),
        Case(
            name: "one level of sound starts the count again",
            levels: run(0, for: .milliseconds(1_900)) + [0.3] + run(0, for: .seconds(2)),
            changes: [(.seconds(4), true)]),
        Case(
            name: "a hold shorter than 2 s never warns", levels: run(0, for: .milliseconds(1_900)), changes: []),
    ]

    @Test(arguments: cases)
    func warning(_ example: Case) {
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        var changes: [(at: Duration, isWarning: Bool)] = []
        var isWarning = false
        for (index, level) in example.levels.enumerated() {
            let at = Duration.milliseconds(100) * (index + 1)
            let next = policy.level(level, at: start + at)
            if next != isWarning {
                changes.append((at, next))
                isWarning = next
            }
        }
        #expect(changes.map(\.at) == example.changes.map(\.at))
        #expect(changes.map(\.isWarning) == example.changes.map(\.isWarning))
    }

    @Test func aSlowerMeterWarnsAtTheFirstLevelAfterTheDelay() {
        // AirPods in the call profile run at 24 kHz: the meter sends a level each 200 ms.
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.level(0, at: start + .milliseconds(1_800)) == false)
        #expect(policy.level(0, at: start + .milliseconds(2_000)) == true)
    }

    @Test func noLevelsForAWhileThenSoundNeverWarns() {
        // A Bluetooth mic that sends nothing while it starts, then room noise.
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.level(0.006, at: start + .milliseconds(2_500)) == false)
    }

    @Test func noLevelByTheDeadlineWarns() {
        // A mic that opened but sends nothing: the pipeline's one deadline at start + delay.
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.deadlinePassed(at: start + .seconds(2)) == true)
    }

    @Test func soundBeforeTheDeadlineKeepsItQuiet() {
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.level(0.006, at: start + .seconds(1)) == false)
        #expect(policy.deadlinePassed(at: start + .seconds(2)) == false)
    }

    @Test func theDeadlineFollowsTheLastSound() {
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.deadline == start + .seconds(2))

        _ = policy.level(0.4, at: start + .seconds(1))
        _ = policy.level(0, at: start + .milliseconds(1_100))
        #expect(policy.deadline == start + .seconds(3))

        _ = policy.deadlinePassed(at: start + .seconds(3))
        #expect(policy.deadline == nil)
    }

    @Test func aLostMicWarnsAtOnceUntilSoundArrives() {
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.level(0.4, at: start + .seconds(1)) == false)

        #expect(policy.inputLost() == true)
        #expect(policy.level(0, at: start + .milliseconds(1_100)) == true)
        #expect(policy.level(0.4, at: start + .milliseconds(1_200)) == false)
    }

    @Test func restartCountsFromTheRestart() {
        let start = ContinuousClock.now
        var policy = NoSoundPolicy(delay: .seconds(2), startingAt: start)
        #expect(policy.level(0, at: start + .seconds(3)) == true)

        policy.restart(at: start + .seconds(10))

        #expect(policy.isWarning == false)
        #expect(policy.level(0, at: start + .milliseconds(11_900)) == false)
        #expect(policy.level(0, at: start + .seconds(12)) == true)
    }
}
