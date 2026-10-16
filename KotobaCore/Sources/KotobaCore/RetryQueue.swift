import Foundation

/// Sends kept dictations that have no transcript again, and lists the recovered ones for 24 h.
/// A retried transcript goes to the store only, never to the clipboard: the owner copies it from
/// the menu.
public actor RetryQueue {
    static let recoveredWindow: TimeInterval = 24 * 60 * 60

    private let steps: TranscriptionSteps
    private let store: any Store
    private let clock: any PipelineClock
    private let clipboard: ClipboardGuard
    private var isRunning = false
    /// Asked for while a run was going; it runs right after, so no request is lost.
    private var requested: RetrySelection?
    /// Whether the last network report was offline.
    private var isOffline = false

    init(steps: TranscriptionSteps, store: any Store, clock: any PipelineClock, clipboard: ClipboardGuard) {
        self.steps = steps
        self.store = store
        self.clock = clock
        self.clipboard = clipboard
    }

    /// Retries the queued dictations that `selection` picks, one at a time, and returns the updated
    /// records in order. Before each send it waits until no dictation is live (`waitUntilQuiet`), and
    /// it skips a dictation that is in flight or no longer queued. A call during a run returns at
    /// once; its selection runs after the current one, in the same call.
    func run(
        _ selection: RetrySelection,
        settings: @Sendable () async -> DictationPipeline.Settings,
        skipping isInFlight: @Sendable (DictationID) async -> Bool,
        waitUntilQuiet: @Sendable () async -> Void = {}
    ) async -> [DictationRecord] {
        guard !isRunning else {
            requested = requested.map { $0.merged(with: selection) } ?? selection
            return []
        }
        isRunning = true
        defer { isRunning = false }

        var results: [DictationRecord] = []
        var next: RetrySelection? = selection
        while let current = next {
            results += await runOnce(current, settings: settings, skipping: isInFlight, waitUntilQuiet: waitUntilQuiet)
            next = requested
            requested = nil
        }
        return results
    }

    /// Records a network report. Returns true when the report ends an outage; the first report is not a return,
    /// because launch already retries.
    func recordNetwork(isOnline: Bool) -> Bool {
        defer { isOffline = !isOnline }
        return isOnline && isOffline
    }

    private func runOnce(
        _ selection: RetrySelection,
        settings: @Sendable () async -> DictationPipeline.Settings,
        skipping isInFlight: @Sendable (DictationID) async -> Bool,
        waitUntilQuiet: @Sendable () async -> Void
    ) async -> [DictationRecord] {
        let queued: [DictationRecord]
        do {
            queued = try await store.pendingRetries()
        } catch {
            Log.pipeline.error("Retry: cannot read the queue: \(error)")
            return []
        }
        var results: [DictationRecord] = []
        for record in queued where selection.includes(record) {
            await waitUntilQuiet()
            guard let fresh = await stillQueued(record.id, isInFlight: isInFlight) else { continue }
            let retried = await retry(fresh, settings: await settings())
            // Deleted from the History pane during the request: it stays deleted and shows no outcome.
            guard await store.updateOrLog(retried) else { continue }
            results.append(retried)
        }
        return results
    }

    /// The record as stored now, when it is still queued. A live dictation saves a `.pending` row while it uploads,
    /// so the queue read can hold it; by its turn it may be in flight, already pasted, or failed with a new model and
    /// new latency marks that the copy from the queue read lacks.
    private func stillQueued(
        _ id: DictationID,
        isInFlight: @Sendable (DictationID) async -> Bool
    ) async -> DictationRecord? {
        guard await !isInFlight(id) else { return nil }
        do {
            return try await store.queuedRecord(id)
        } catch {
            Log.pipeline.error("Retry: cannot read \(id.rawValue): \(error)")
            return nil
        }
    }

    private func retry(_ record: DictationRecord, settings: DictationPipeline.Settings) async -> DictationRecord {
        var record = record
        do {
            let transcribed = try await steps.transcribe(&record, settings: settings)
            if let mode = record.output.cleanupMode {
                // No paste waits on a retry: no deadline.
                await steps.clean(transcribed, in: mode, into: &record, settings: settings, deadline: nil)
            }
            record.status = .recovered
            record.needsSetup = nil
            record.recoveredAt = clock.date
        } catch {
            Log.pipeline.error("Retry \(record.id.rawValue) on \(record.model ?? "no answer") failed: \(error)")
            record.markFailed(by: error)
        }
        return record
    }

    /// Recovered transcripts from the last 24 h, newest first.
    public func recovered() async -> [DictationRecord] {
        do {
            return try await store.recovered(since: clock.date - Self.recoveredWindow)
        } catch {
            Log.pipeline.error("Cannot read recovered transcripts: \(error)")
            return []
        }
    }

    /// Puts a recovered transcript (the cleaned one, for a cleanup dictation) on the clipboard and
    /// takes it off the Recovered list.
    public func copy(_ record: DictationRecord) async {
        guard let text = record.deliveredText else { return }
        await clipboard.copy(text)
        do {
            try await store.markCopied(record.id)
        } catch {
            Log.pipeline.error("Cannot mark \(record.id.rawValue) copied: \(error)")
        }
    }
}
