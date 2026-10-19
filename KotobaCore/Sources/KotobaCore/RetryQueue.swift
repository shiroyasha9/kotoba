import Foundation

/// Sends kept dictations that have no transcript again, and lists the recovered ones for 24 h.
/// A retried transcript goes to the store only, never to the clipboard: the owner copies it from
/// the menu.
public actor RetryQueue {
    static let recoveredWindow: TimeInterval = 24 * 60 * 60

    private let steps: TranscriptionSteps
    private let store: any Store
    private let clock: any PipelineClock
    private let paste: ClipboardPaste
    private var isRunning = false
    /// Asked for while a run was going; it runs right after, so no request is lost.
    private var requested: RetrySelection?
    /// Whether the last network report was offline.
    private var isOffline = false
    /// Quit began: no send starts from here (`stop`).
    private var isStopped = false
    /// A send is on its way: marked in the same step as the `isStopped` check, so `stop` never misses it.
    private var isSending = false
    /// Quit, waiting for the send on its way to save its answer (`sendEnded`).
    private(set) var sendEndWaiters = Waiters()
    /// Recovered transcripts the store could not write (a full disk): the menu lists them until the owner copies
    /// them, and no run in this process sends them again. The next launch does, as their rows are still queued.
    private var unsaved: [DictationRecord] = []

    init(steps: TranscriptionSteps, store: any Store, clock: any PipelineClock, paste: ClipboardPaste) {
        self.steps = steps
        self.store = store
        self.clock = clock
        self.paste = paste
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
        while let current = next, !isStopped {
            let (records, isEnded) = await runOnce(
                current, settings: settings, skipping: isInFlight, waitUntilQuiet: waitUntilQuiet)
            results += records
            // The store cannot write: the selection asked for meanwhile would lose its answers the same way.
            next = isEnded ? nil : requested
            requested = nil
        }
        return results
    }

    /// Quit: no run or send starts from here. Returns whether a send is on its way (`sendEnded` waits for it).
    func stop() -> Bool {
        isStopped = true
        requested = nil
        return isSending
    }

    /// Returns once the send on its way, if any, saved its answer, so the next launch does not send it again.
    func sendEnded() async {
        guard isSending else { return }
        await withCheckedContinuation { sendEndWaiters.add($0) }
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
    ) async -> (records: [DictationRecord], isEnded: Bool) {
        let queued: [DictationRecord]
        do {
            queued = try await store.pendingRetries()
        } catch {
            Log.pipeline.error("Retry: cannot read the queue: \(error)")
            return ([], false)
        }
        var results: [DictationRecord] = []
        for record in queued where selection.includes(record) {
            await waitUntilQuiet()
            guard let fresh = await stillQueued(record.id, isInFlight: isInFlight) else { continue }
            let settings = await settings()
            // Read last before the send: quit can begin during the awaits above.
            guard !isStopped else { break }
            isSending = true
            let (retried, error) = await retry(fresh, settings: settings)
            let update = await store.updateOrLog(retried)
            isSending = false
            sendEndWaiters.resumeAll()
            switch update {
            case .written:
                results.append(retried)
            case .rowGone:
                // Deleted from the History pane during the request: it stays deleted and shows no outcome.
                break
            case .failed:
                if retried.status == .recovered {
                    unsaved.append(retried)
                    results.append(retried)
                }
                Log.pipeline.error("Retry: stopped, the store cannot write; the next answer would be lost the same way")
                return (results, true)
            }
            if error?.isSharedByEveryRequest == true {
                Log.pipeline.info(
                    "Retry: stopped, the next sends would fail the same way: \(String(describing: error))")
                break
            }
        }
        return (results, false)
    }

    /// The record as stored now, when it is still queued. A live dictation saves a `.pending` row while it uploads,
    /// so the queue read can hold it; by its turn it may be in flight, already pasted, or failed with a new model and
    /// new latency marks that the copy from the queue read lacks.
    private func stillQueued(
        _ id: DictationID,
        isInFlight: @Sendable (DictationID) async -> Bool
    ) async -> DictationRecord? {
        guard !unsaved.contains(where: { $0.id == id }), await !isInFlight(id) else { return nil }
        do {
            return try await store.queuedRecord(id)
        } catch {
            Log.pipeline.error("Retry: cannot read \(id.rawValue): \(error)")
            return nil
        }
    }

    /// The record after the send, and the error when it failed.
    private func retry(
        _ record: DictationRecord, settings: DictationPipeline.Settings
    ) async -> (DictationRecord, ProviderError?) {
        var record = record
        var failure: ProviderError?
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
            failure = error as? ProviderError
        }
        return (record, failure)
    }

    /// Recovered transcripts from the last 24 h, newest first, the unsaved ones included.
    public func recovered() async -> [DictationRecord] {
        let cutoff = clock.date - Self.recoveredWindow
        let stored: [DictationRecord]
        do {
            stored = try await store.recovered(since: cutoff)
        } catch {
            Log.pipeline.error("Cannot read recovered transcripts: \(error)")
            stored = []
        }
        unsaved.removeAll { ($0.recoveredAt ?? .distantPast) < cutoff }
        guard !unsaved.isEmpty else { return stored }
        return (unsaved + stored).sorted { ($0.recoveredAt ?? .distantPast) > ($1.recoveredAt ?? .distantPast) }
    }

    /// Puts a recovered transcript (the cleaned one, for a cleanup dictation) on the clipboard and
    /// takes it off the Recovered list.
    public func copy(_ record: DictationRecord) async {
        guard let text = record.deliveredText else { return }
        await paste.copy(text)
        unsaved.removeAll { $0.id == record.id }
        do {
            try await store.markCopied(record.id)
        } catch {
            Log.pipeline.error("Cannot mark \(record.id.rawValue) copied: \(error)")
        }
    }
}
