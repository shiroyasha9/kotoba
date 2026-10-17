import Foundation
import Synchronization

@testable import KotobaCore

/// Time moves only when a test calls `advance(by:)`; sleepers whose deadline passes wake then.
final class ManualClock: PipelineClock {
    private struct Sleeper {
        let id: UUID
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = ContinuousClock.Instant.now
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var sleepers: [Sleeper] = []
        /// Sleeps cancelled before they registered.
        var cancelled: Set<UUID> = []
    }

    private let state = Mutex(State())

    var now: ContinuousClock.Instant {
        state.withLock { $0.now }
    }

    var date: Date {
        state.withLock { $0.date }
    }

    func sleep(until deadline: ContinuousClock.Instant) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let resumeNow = state.withLock { state in
                    guard deadline > state.now, !state.cancelled.contains(id) else { return true }
                    state.sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return false
                }
                if resumeNow {
                    continuation.resume()
                }
            }
        } onCancel: {
            let sleeper = state.withLock { state -> Sleeper? in
                guard let index = state.sleepers.firstIndex(where: { $0.id == id }) else {
                    state.cancelled.insert(id)
                    return nil
                }
                return state.sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    /// The deadlines of the timers waiting on this clock.
    var deadlines: [ContinuousClock.Instant] {
        state.withLock { $0.sleepers.map(\.deadline) }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now += duration
            state.date += duration / .seconds(1)
            let now = state.now
            let due = state.sleepers.filter { $0.deadline <= now }
            state.sleepers.removeAll { $0.deadline <= now }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}
