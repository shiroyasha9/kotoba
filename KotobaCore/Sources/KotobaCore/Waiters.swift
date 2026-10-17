/// Tasks parked until a condition holds, resumed together; the owner checks the condition.
struct Waiters {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    /// Test seam: how many tasks are parked.
    var count: Int { continuations.count }

    var isEmpty: Bool { continuations.isEmpty }

    mutating func add(_ continuation: CheckedContinuation<Void, Never>) {
        continuations.append(continuation)
    }

    mutating func resumeAll() {
        let waiting = continuations
        continuations = []
        for continuation in waiting {
            continuation.resume()
        }
    }
}
