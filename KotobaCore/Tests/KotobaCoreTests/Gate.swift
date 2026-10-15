import Foundation
import Testing

/// Suspends callers until a test opens it. A gate never opened lets its callers go after 5 s and
/// records an issue, so a wrong test fails instead of hanging the run.
actor Gate {
    private static let limit = Duration.seconds(5)

    private var isOpen = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    var hasWaiters: Bool { !waiters.isEmpty }

    func pass() async {
        guard !isOpen else { return }
        let id = UUID()
        Task {
            try? await Task.sleep(for: Self.limit)  // Real time: the bound on a test that forgot to open.
            self.expire(id)
        }
        await withCheckedContinuation { waiters[id] = $0 }
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
