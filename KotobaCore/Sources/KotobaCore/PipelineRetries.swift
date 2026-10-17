import Foundation

// MARK: - Retries

extension DictationPipeline {
    /// The route's wait (`ProviderError.rateLimited`) is kept within these bounds: a wait of a second would wake kotoba
    /// every second while the route refuses, and after an hour launch or the network sends the dictations anyway.
    static let retryAfterBounds = Duration.seconds(10)...Duration.seconds(60 * 60)

    /// Transcribes kept dictations into the Recovered list, each send after no dictation is live. With no `selection`
    /// (the menu), dictations that wait for a setting are included only when the route has everything.
    public func retryPending(_ chosen: RetrySelection? = nil) async {
        await retryPending(chosen, isAutomatic: false)
    }

    /// Launch: the menu's Retry, except that a dictation that used its automatic attempts waits for the owner
    /// (`RetrySelection.automaticAttempts`).
    public func retryAtLaunch() async {
        await retryPending(nil, isAutomatic: true)
    }

    private func retryPending(_ chosen: RetrySelection?, isAutomatic: Bool) async {
        guard !isQuitting else { return }
        let isSetUp = await ports.missingSetup() == nil
        var selection = chosen ?? (isSetUp ? .all : .exceptNeedsSetup)
        selection.isAutomatic = isAutomatic
        let results = await retries.run(
            selection, settings: { await self.settings }, skipping: { await self.inFlight.contains($0) },
            waitUntilQuiet: { await self.waitUntilQuiet() })
        // The run stops at the route's wait, so it is the last result's.
        if let wait = results.last?.retryAfter { scheduleRetry(after: wait) }
        for record in results {
            reportTerms(of: record)
            emitIfQuiet(.outcome(of: record))
        }
        // A recovered dictation is delivered too: retention's event (story 31).
        if results.contains(where: \.status.isTranscribed) { work.track { await self.deleteExpiredAudio() } }
    }

    /// The History pane's Retry: sends the chosen kept dictations again, each after no dictation is live. A cancelled
    /// or rejected one joins the queue first (`DictationRecord.isRetryable`).
    public func retry(_ ids: Set<DictationID>) async {
        for id in ids {
            do {
                try await ports.store.queueForRetry(id)
            } catch {
                Log.pipeline.error("Cannot queue \(id.rawValue) for retry: \(error)")
            }
        }
        await retryPending(.only(ids))
    }

    /// A key, an endpoint or credit arrived: once the route has everything, the waiting dictations are sent once each.
    public func setupChanged() async {
        guard await ports.missingSetup() == nil else { return }
        await retryPending(.onlyNeedsSetup)
    }

    /// A live dictation got its text: the route works, credit included, so the dictations that waited for it are sent
    /// (decision 6), and so are the failed ones, as a server outage can end with the network up. Each
    /// within its automatic attempts.
    func routeAnswered() async {
        await retryPending(nil, isAutomatic: true)
    }

    /// The network monitor's report. When the network returns after an outage, the failed dictations are sent again
    /// (story 22), as tracked work: this returns at once, so the monitor never waits on a retry (review B7).
    public func networkChanged(isOnline: Bool) async {
        guard await retries.recordNetwork(isOnline: isOnline) else { return }
        work.track { await self.retryPending(.exceptNeedsSetup, isAutomatic: true) }
    }

    /// The route asked to wait `wait` before the next send: the waiting dictations go then, as tracked work on the
    /// pipeline clock, unless a newer wait replaced this one.
    func scheduleRetry(after wait: Duration) {
        let bounds = Self.retryAfterBounds
        let delay = min(max(wait, bounds.lowerBound), bounds.upperBound)
        retryTimer?.cancel()
        retryTimer = work.schedule(at: ports.clock.now + delay) { await self.retryTimerFired() }
    }

    /// From here a newer wait must not cancel this run: its request would end as offline.
    private func retryTimerFired() async {
        retryTimer = nil
        await retryPending(.exceptNeedsSetup, isAutomatic: true)
    }
}
