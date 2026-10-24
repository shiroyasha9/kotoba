import Foundation
import Testing

/// Suspends callers until a test opens it, or until the caller's task is cancelled (as a cancelled request ends). A
/// gate never opened lets its callers go after 5 s and records an issue, so a wrong test fails instead of hanging the
/// run.
actor Gate {
    private static let limit = Duration.seconds(5)

    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Callers cancelled before they were parked.
    private var cancelled: Set<UUID> = []

    var hasWaiters: Bool { !waiters.isEmpty }

    func pass() async {
        guard !isOpen else { return }
        let id = UUID()
        Task {
            // Real time: the bound on a test that forgot to open, never a wait in a test that works.
            // swiftlint:disable:next no_wall_clock_in_tests
            try? await Task.sleep(for: Self.limit)
            self.expire(id)
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if cancelled.remove(id) != nil || Task.isCancelled {
                    continuation.resume()
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else {
            cancelled.insert(id)
            return
        }
        waiter.resume()
    }

    func open() {
        isOpen = true
        let waiting = waiters.values
        waiters = [:]
        for waiter in waiting {
            waiter.resume()
        }
    }

    private func expire(_ id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        Issue.record("A gate was never opened; released after \(Self.limit)")
        waiter.resume()
    }
}
