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
            selection, waitUntilQuiet: { await self.waitUntilQuiet() },
            beginSend: { await self.beginRetrySend(of: $0) }, endSend: { await self.retrySendEnded() })
        // The run stops at the route's wait, so it is the last result's.
        if let wait = results.last?.lastError?.retryAfter { scheduleRetry(after: wait) }
        for record in results {
            reportTerms(of: record)
            emitIfQuiet(.outcome(of: record))
        }
        // A recovered dictation is delivered too: retention's event (story 31).
        if results.contains(where: \.status.isTranscribed) { work.track { await self.deleteExpiredAudio() } }
    }

    /// The retry queue's send of `id` begins, in one step with the checks: only while nothing is live and before quit,
    /// and not for a dictation being sent live. It is live until `retrySendEnded`, so quit waits for its answer.
    private func beginRetrySend(of id: DictationID) -> RetryQueue.SendStart {
        if live.isQuitting { return .stopped }
        if live.isSending(id) { return .inFlight }
        return live.begin(.retrySend) ? .began(settings) : .busy
    }

    private func retrySendEnded() {
        live.end(.retrySend)
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

    /// A key, an endpoint or credit arrived: once the route has everything, the waiting dictations are sent once each,
    /// and the failed ones within their automatic attempts: a new endpoint fixes a host that was not found.
    public func setupChanged() async {
        guard await ports.missingSetup() == nil else { return }
        await retryPending(.all, isAutomatic: true)
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
        guard !isQuitting else { return }
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

/// Which kept dictations a retry sends again: the ones a rule picks, and the ones the owner chose.
public struct RetrySelection: Sendable, Equatable {
    enum Rule: Sendable, Equatable {
        case all
        case exceptNeedsSetup
        case onlyNeedsSetup

        func includes(_ record: DictationRecord) -> Bool {
            switch self {
            case .all: true
            case .exceptNeedsSetup: record.needsSetup == nil
            case .onlyNeedsSetup: record.needsSetup != nil
            }
        }
    }

    /// A dictation is sent at most this many times in all, live and retried, without the owner: each failed send
    /// that reached the route may have been billed (`DictationRecord.attempts`). Launch, a returning network, a live
    /// transcript and a route's wait skip it then; the owner's Retry (the menu, History) still sends it, and so does
    /// a setting the dictation waits for.
    public static let automaticAttempts = 3

    var rule: Rule?
    var ids: Set<DictationID> = []
    /// Launch or a returning network, not the owner: the rule skips dictations that used their automatic attempts.
    var isAutomatic = false

    /// The menu's Retry: every queued dictation.
    public static let all = Self(rule: .all)
    /// Launch without a key: dictations that wait for a key stay waiting.
    public static let exceptNeedsSetup = Self(rule: .exceptNeedsSetup)
    /// The owner saved a key: only the dictations that waited for one, once each.
    public static let onlyNeedsSetup = Self(rule: .onlyNeedsSetup)

    /// The History pane's Retry: the chosen queued dictations.
    public static func only(_ ids: Set<DictationID>) -> Self {
        Self(rule: nil, ids: ids)
    }

    func includes(_ record: DictationRecord) -> Bool {
        if ids.contains(record.id) { return true }
        guard rule?.includes(record) == true else { return false }
        // A dictation waiting for a setting was last refused before any work, which was not billed: it goes once its
        // setting is there, whatever its earlier attempts (lead, 2026-10-17).
        return !isAutomatic || record.needsSetup != nil || record.attempts < Self.automaticAttempts
    }

    /// Two requests in one: the dictations of each. Two different rules cover both only as `.all`; the rule is capped
    /// only when every request with a rule was automatic.
    func merged(with other: Self) -> Self {
        let (merged, isAutomatic): (Rule?, Bool) =
            switch (rule, other.rule) {
            case (nil, _): (other.rule, other.isAutomatic)
            case (_, nil): (rule, self.isAutomatic)
            case (let one?, let two?): (one == two ? one : .all, self.isAutomatic && other.isAutomatic)
            }
        return Self(rule: merged, ids: ids.union(other.ids), isAutomatic: isAutomatic)
    }
}
