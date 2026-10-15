import Foundation

/// Time for the pipeline: tap-vs-hold, the 10-minute warning, clipboard restore, latency marks,
/// and wall-clock dates for records. Tests inject a manual clock; the app injects `SystemClock`.
public protocol PipelineClock: Sendable {
    var now: ContinuousClock.Instant { get }
    /// Wall-clock time, for `createdAt` and the 24 h window of recovered transcripts.
    var date: Date { get }
    /// Returns at once when `deadline` has passed. Throws `CancellationError` when cancelled.
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

public struct SystemClock: PipelineClock {
    public init() {}

    public var now: ContinuousClock.Instant { .now }

    public var date: Date { .now }

    public func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await ContinuousClock().sleep(until: deadline)
    }
}
