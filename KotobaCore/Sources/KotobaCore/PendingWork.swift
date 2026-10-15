import Foundation
import Synchronization

/// The pipeline's background tasks: timers on the pipeline clock and the work after a stop. It
/// keeps them so that `settle()` can wait for the ones that are due.
final class PendingWork: Sendable {
    private struct Entry {
        /// Nil for work that finishes on its own; otherwise the clock time it waits for.
        let deadline: ContinuousClock.Instant?
        let task: Task<Void, Never>
    }

    private let clock: any PipelineClock
    private struct State {
        var entries: [UUID: Entry] = [:]
        var endedEarly: Set<UUID> = []
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
        let token = UUID()
        let task = Task {
            await body()
            self.state.withLock { state in
                if state.entries.removeValue(forKey: token) == nil {
                    state.endedEarly.insert(token)
                }
            }
        }
        state.withLock { state in
            // A task that ended before this line left its token here instead of an entry to remove.
            if state.endedEarly.remove(token) == nil {
                state.entries[token] = Entry(deadline: deadline, task: task)
            }
        }
        return task
    }

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
