import Testing

@testable import KotobaCore

/// When a main-window pane reads from the stores: only while shown, and at most one read after a burst of writes.
@MainActor
struct PaneReadsTests {
    /// A pane whose reads return their number, each held at `gate` while one is set.
    @MainActor
    final class FakePane {
        private(set) var reads = 0
        /// Reads that returned or threw, delivered or not.
        private(set) var finished = 0
        private(set) var delivered: [Int] = []
        private(set) var failures = 0
        var gate: Gate?
        var error: (any Error)?

        func read() async throws -> Int {
            reads += 1
            let number = reads
            await gate?.pass()
            finished += 1
            if let error { throw error }
            return number
        }

        func deliver(_ result: Result<Int, any Error>) {
            switch result {
            case .success(let number): delivered.append(number)
            case .failure: failures += 1
            }
        }

        func schedule() -> PaneReads<Int> {
            PaneReads(read: read, deliver: deliver)
        }
    }

    @Test func aShownPaneReadsOnce() async {
        let pane = FakePane()
        let reads = pane.schedule()

        reads.show()

        #expect(await eventually { pane.delivered == [1] })
        #expect(pane.reads == 1)
    }

    @Test func aHiddenPaneReadsNothingOnAWrite() {
        let pane = FakePane()
        let reads = pane.schedule()

        reads.changed()

        #expect(pane.reads == 0)
    }

    @Test func aBurstOfWritesDuringAReadCostsOneMoreRead() async {
        let pane = FakePane()
        let gate = Gate()
        pane.gate = gate
        let reads = pane.schedule()
        reads.show()
        #expect(await eventually { await gate.hasWaiters })

        reads.changed()
        reads.changed()
        reads.changed()
        pane.gate = nil
        await gate.open()

        #expect(await eventually { pane.delivered == [1, 2] })
        #expect(pane.reads == 2)
    }

    @Test func hidingDropsTheReadAndLaterWrites() async {
        let pane = FakePane()
        let gate = Gate()
        pane.gate = gate
        let reads = pane.schedule()
        reads.show()
        #expect(await eventually { await gate.hasWaiters })

        reads.hide()
        reads.changed()
        await gate.open()

        #expect(await eventually { pane.finished == 1 })
        #expect(pane.delivered.isEmpty)
        #expect(pane.reads == 1)
    }

    @Test func aPaneShownAgainReadsAgain() async {
        let pane = FakePane()
        let reads = pane.schedule()
        reads.show()
        #expect(await eventually { pane.delivered == [1] })

        reads.hide()
        reads.show()

        #expect(await eventually { pane.delivered == [1, 2] })
    }

    /// "Try Again" after a failed read is `show()` again.
    @Test func aFailedReadIsDeliveredAndTriedAgain() async {
        let pane = FakePane()
        pane.error = FakeError()
        let reads = pane.schedule()
        reads.show()
        #expect(await eventually { pane.failures == 1 })

        pane.error = nil
        reads.show()

        #expect(await eventually { pane.delivered == [2] })
    }
}
