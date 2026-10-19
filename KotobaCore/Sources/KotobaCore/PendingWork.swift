import Foundation
import Synchronization

/// The pipeline's background tasks: timers on the pipeline clock and the work after a stop. It
/// keeps them so that `settle()` can wait for the ones that are due, and quit for the billed ones (`bill`).
final class PendingWork: Sendable {
    private struct Entry {
        /// Nil for work that finishes on its own; otherwise the clock time it waits for.
        let deadline: ContinuousClock.Instant?
        let task: Task<Void, Never>
        let isBilled: Bool
    }

    private let clock: any PipelineClock
    private struct State {
        var entries: [UUID: Entry] = [:]
        var endedEarly: Set<UUID> = []
        /// Quits waiting in `billsEnded`, by waiter.
        var billWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
        /// Waiters whose bound passed before they parked.
        var releasedEarly: Set<UUID> = []

        var hasBilledWork: Bool { entries.values.contains(where: \.isBilled) }
    }

    private let state = Mutex(State())

    init(clock: any PipelineClock) {
        self.clock = clock
    }

    /// Runs `body` now, on its own isolation (the pipeline actor for the pipeline's closures).
    @discardableResult
    func track(
        until deadline: ContinuousClock.Instant? = nil,
        _ body: sending @escaping @isolated(any) () async -> Void
    ) -> Task<Void, Never> {
        track(until: deadline, isBilled: false, body)
    }

    /// Runs `body` now as tracked work that sends a billed request or writes the usage ledger: quit waits for it
    /// (`billsEnded`), so the cost it brings is counted. A send of a live dictation or a job is in `LiveDictations`.
    @discardableResult
    func bill(_ body: sending @escaping @isolated(any) () async -> Void) -> Task<Void, Never> {
        track(until: nil, isBilled: true, body)
    }

    private func track(
        until deadline: ContinuousClock.Instant?, isBilled: Bool,
        _ body: sending @escaping @isolated(any) () async -> Void
    ) -> Task<Void, Never> {
        let token = UUID()
        let task = Task {
            await body()
            let waiters = self.state.withLock { state in
                if state.entries.removeValue(forKey: token) == nil {
                    state.endedEarly.insert(token)
                }
                guard !state.billWaiters.isEmpty, !state.hasBilledWork else {
                    return [CheckedContinuation<Void, Never>]()
                }
                defer { state.billWaiters = [:] }
                return Array(state.billWaiters.values)
            }
            for waiter in waiters { waiter.resume() }
        }
        state.withLock { state in
            // A task that ended before this line left its token here instead of an entry to remove.
            if state.endedEarly.remove(token) == nil {
                state.entries[token] = Entry(deadline: deadline, task: task, isBilled: isBilled)
            }
        }
        return task
    }

    /// Returns once no billed work runs (`bill`), or at `deadline` on the clock: quit must not hang on a slow route
    /// or disk.
    func billsEnded(by deadline: ContinuousClock.Instant) async {
        let waiter = UUID()
        let bound = schedule(at: deadline) { self.release(waiter) }
        await withCheckedContinuation { continuation in
            let isEnded = state.withLock { state in
                guard state.releasedEarly.remove(waiter) == nil, state.hasBilledWork else { return true }
                state.billWaiters[waiter] = continuation
                return false
            }
            if isEnded { continuation.resume() }
        }
        bound.cancel()
        state.withLock { _ = $0.releasedEarly.remove(waiter) }
    }

    /// The bound of `waiter` passed.
    private func release(_ waiter: UUID) {
        let parked = state.withLock { state in
            guard let parked = state.billWaiters.removeValue(forKey: waiter) else {
                state.releasedEarly.insert(waiter)
                return CheckedContinuation<Void, Never>?.none
            }
            return parked
        }
        parked?.resume()
    }

    /// Test seam: quits that wait in `billsEnded`.
    var billWaiterCount: Int { state.withLock { $0.billWaiters.count } }

    /// Runs `body` at `deadline` on the pipeline clock, unless the returned task is cancelled first.
    @discardableResult
    func schedule(
        at deadline: ContinuousClock.Instant,
        _ body: sending @escaping @isolated(any) () async -> Void
    ) -> Task<Void, Never> {
        track(until: deadline) { [clock] in
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            await body()
        }
    }

    /// Waits for all work that can finish now: stopped dictations, and timers whose deadline has
    /// passed on the clock. Tests call it after each step.
    func settle() async {
        while let task = state.withLock({ state in
            state.entries.values.first { $0.deadline.map { $0 <= clock.now } ?? true }?.task
        }) {
            await task.value
        }
    }
}
