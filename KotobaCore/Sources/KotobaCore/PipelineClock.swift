/// Time for the pipeline: tap-vs-hold, the 10-minute warning, clipboard restore, latency marks.
/// Tests inject a manual clock; the app injects `SystemClock`.
public protocol PipelineClock: Sendable {
    var now: ContinuousClock.Instant { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: PipelineClock {
    public init() {}

    public var now: ContinuousClock.Instant { .now }

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}
