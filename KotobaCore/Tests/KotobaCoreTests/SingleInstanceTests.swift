import Foundation
import Testing

@testable import KotobaCore

struct SingleInstanceTests {
    private static func copy(_ processID: Int32, launchedAt seconds: Double?) -> SingleInstance.Copy {
        SingleInstance.Copy(processID: processID, launchedAt: seconds.map { Date(timeIntervalSince1970: $0) })
    }

    @Test func theOnlyCopyKeepsRunning() {
        #expect(SingleInstance.handOver(from: Self.copy(501, launchedAt: 10), others: []) == nil)
    }

    @Test func aLaterCopyHandsOverToTheOneThatRuns() {
        let running = Self.copy(501, launchedAt: 10)
        #expect(SingleInstance.handOver(from: Self.copy(601, launchedAt: 20), others: [running]) == running)
    }

    @Test func theFirstCopyKeepsRunningWhenALaterOneStarts() {
        #expect(
            SingleInstance.handOver(from: Self.copy(501, launchedAt: 10), others: [Self.copy(601, launchedAt: 20)])
                == nil)
    }

    /// Two copies that launch together each see the other: they order the copies the same way, so one keeps running.
    @Test func twoCopiesLaunchedTogetherKeepOne() {
        let first = Self.copy(501, launchedAt: 10)
        let second = Self.copy(502, launchedAt: 10)
        #expect(SingleInstance.handOver(from: first, others: [second]) == nil)
        #expect(SingleInstance.handOver(from: second, others: [first]) == first)
    }

    /// A copy started from a terminal has no launch time; the order still holds for every copy.
    @Test func aCopyWithNoLaunchTimeComesFirst() {
        let terminal = Self.copy(700, launchedAt: nil)
        let finder = Self.copy(501, launchedAt: 10)
        #expect(SingleInstance.handOver(from: finder, others: [terminal]) == terminal)
        #expect(SingleInstance.handOver(from: terminal, others: [finder]) == nil)
    }

    @Test func itHandsOverToTheEarliestOfSeveral() {
        let earliest = Self.copy(501, launchedAt: 10)
        let others = [Self.copy(601, launchedAt: 30), earliest, Self.copy(602, launchedAt: 20)]
        #expect(SingleInstance.handOver(from: Self.copy(701, launchedAt: 40), others: others) == earliest)
    }
}
