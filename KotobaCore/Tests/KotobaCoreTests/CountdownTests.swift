import Testing

@testable import KotobaCore

/// An 8 s countdown that starts at 0 s; hold and resume times are seconds from the start.
struct CountdownTests {
    enum Step: Sendable {
        case hold(at: Double)
        case resume(at: Double)
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var startsHeld = false
        var steps: [Step] = []
        /// Seconds from the start.
        let checkAt: Double
        let remaining: Duration
        let isHeld: Bool

        var testDescription: String { name }
    }

    static let start = ContinuousClock.now
    static let duration = Duration.seconds(8)

    static func at(_ seconds: Double) -> ContinuousClock.Instant {
        start + .milliseconds(Int(seconds * 1000))
    }

    static let rows: [Row] = [
        Row(name: "runs down from the full duration", checkAt: 0, remaining: .seconds(8), isHeld: false),
        Row(name: "runs down with time", checkAt: 3, remaining: .seconds(5), isHeld: false),
        Row(name: "never goes below zero", checkAt: 12, remaining: .zero, isHeld: false),
        Row(
            name: "a hold keeps the time that was left", steps: [.hold(at: 2)], checkAt: 30, remaining: .seconds(6),
            isHeld: true),
        Row(
            name: "a resume continues from the held time", steps: [.hold(at: 2), .resume(at: 30)], checkAt: 31,
            remaining: .seconds(5), isHeld: false),
        Row(
            name: "two holds add up", steps: [.hold(at: 1), .resume(at: 5), .hold(at: 6), .resume(at: 20)],
            checkAt: 22, remaining: .seconds(4), isHeld: false),
        Row(
            name: "a second hold keeps the first", steps: [.hold(at: 2), .hold(at: 5)], checkAt: 9,
            remaining: .seconds(6), isHeld: true),
        Row(
            name: "a resume while running changes nothing", steps: [.resume(at: 3)], checkAt: 4, remaining: .seconds(4),
            isHeld: false),
        Row(name: "it can start held", startsHeld: true, checkAt: 20, remaining: .seconds(8), isHeld: true),
        Row(
            name: "a countdown that starts held runs from the resume", startsHeld: true, steps: [.resume(at: 10)],
            checkAt: 12, remaining: .seconds(6), isHeld: false),
        Row(
            name: "a hold after the end keeps zero", steps: [.hold(at: 9), .resume(at: 15)], checkAt: 16,
            remaining: .zero, isHeld: false),
    ]

    @Test(arguments: rows)
    func remainingTime(_ row: Row) {
        var countdown = Countdown(duration: Self.duration, startingAt: Self.start, isHeld: row.startsHeld)
        for step in row.steps {
            switch step {
            case .hold(let seconds): countdown.hold(at: Self.at(seconds))
            case .resume(let seconds): countdown.resume(at: Self.at(seconds))
            }
        }
        let now = Self.at(row.checkAt)
        #expect(countdown.remaining(at: now) == row.remaining)
        #expect(countdown.isHeld == row.isHeld)
        #expect(countdown.fraction(at: now) == row.remaining / Self.duration)
        #expect(countdown.isOver(at: now) == (row.remaining == .zero))
        // A held countdown has no deadline; a running one ends when the remaining time is gone.
        #expect(countdown.deadline == (row.isHeld ? nil : now + row.remaining) || row.remaining == .zero)
    }

    @Test func theFractionIsTheLengthOfTheBar() {
        let countdown = Countdown(duration: Self.duration, startingAt: Self.start)
        #expect(countdown.fraction(at: Self.at(0)) == 1)
        #expect(countdown.fraction(at: Self.at(2)) == 0.75)
        #expect(countdown.fraction(at: Self.at(8)) == 0)
        #expect(countdown.fraction(at: Self.at(20)) == 0)
    }

    @Test func aZeroDurationIsOverAtOnce() {
        let countdown = Countdown(duration: .zero, startingAt: Self.start)
        #expect(countdown.isOver(at: Self.start))
        #expect(countdown.fraction(at: Self.start) == 0)
    }
}
