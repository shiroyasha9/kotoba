import Foundation

/// Durable history: kept audio, the offline retry queue and latency logs.
public protocol Store: Sendable {
    func save(_ record: DictationRecord) async throws
    /// Writes a record whose row still exists and returns true; returns false and writes nothing when the row is gone
    /// (the owner deleted it while a retry ran), so a late write never brings a deleted dictation back.
    func update(_ record: DictationRecord) async throws -> Bool
    /// Records with status `.pending` or `.failed`: dictations whose audio has no transcript yet.
    func pendingRetries() async throws -> [DictationRecord]
    /// The stored status of one dictation, or nil when there is no row.
    func status(of id: DictationID) async throws -> DictationRecord.Status?
    /// Records with status `.recovered` and `recoveredAt` at or after `cutoff`, newest first. For
    /// the menu, so their latency logs may be left empty.
    func recovered(since cutoff: Date) async throws -> [DictationRecord]
    /// Sets one record's status to `.copied`, keeping everything else.
    func markCopied(_ id: DictationID) async throws
    /// Puts a `.cancelled` or `.rejected` record in the retry queue as `.failed`; a record with any other status keeps
    /// it.
    func queueForRetry(_ id: DictationID) async throws
    /// Deletes the records, their latency logs and their audio files (the History window's Delete).
    func delete(_ ids: Set<DictationID>) async throws
    /// Deletes records and their audio created before `cutoff` (retention period), except
    /// `.pending`, `.failed` and `.rejected` ones. Runs at launch or when idle, never on the dictation path.
    func prune(olderThan cutoff: Date) async throws
}

public struct DictationID: Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct DictationRecord: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable {
        /// Saved at stop, before transcription, so a crash keeps the audio queued.
        case pending
        case pasted
        /// The transcript is on the clipboard but was not pasted.
        case copied
        /// A retry transcribed it. It waits in the menu until the owner copies it.
        case recovered
        case cancelled
        /// Audio kept; retried at launch and from the menu.
        case failed
        /// The route refused the request (for example a bad key or no credits). Sending the same
        /// request again gives the same answer, so it is not retried. Audio kept.
        case rejected

    }

    public var id: DictationID
    public var createdAt: Date
    public var audio: RecordedAudio
    public var transcript: String?
    /// The provider's model for the last request; nil when no request was sent.
    public var model: String?
    public var status: Status
    /// Cleanup dictations also run the cleaner when they are retried.
    public var mode = DictationMode.transcript
    /// The cleaned text that was pasted, for a cleanup dictation; `transcript` stays the raw text.
    public var cleanedText: String?
    /// A `.failed` dictation that waits for the owner to set a key or an endpoint; retried then, not on its own.
    public var needsSetup: SetupItem?
    /// Why a `.rejected` dictation was refused; nil for every other status.
    public var rejectReason: RejectReason?
    /// When a retry transcribed it; the menu lists it for 24 h after this.
    public var recoveredAt: Date?
    /// The app in front at the stop, where the text went; nil when unknown (and for dictations kept before this).
    public var app: DictationApp?
    public var latency: LatencyLog

    public init(
        id: DictationID,
        createdAt: Date,
        audio: RecordedAudio,
        transcript: String?,
        model: String? = nil,
        status: Status,
        recoveredAt: Date? = nil,
        latency: LatencyLog
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audio = audio
        self.transcript = transcript
        self.model = model
        self.status = status
        self.recoveredAt = recoveredAt
        self.latency = latency
    }
}

/// The app a dictation went to. Usage and per-app modes group dictations by `bundleID`.
public struct DictationApp: Sendable, Hashable {
    public var bundleID: String
    /// The app's name at the stop, so the history still names an app that is gone.
    public var name: String?

    public init(bundleID: String, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }
}

extension DictationRecord {
    /// The text kotoba pasted or offers to copy: the cleaned text of a cleanup dictation, else the transcript.
    public var deliveredText: String? { cleanedText ?? transcript }

    /// A dictation with no text yet that the History window's Retry can send, while its audio is kept: queued, failed,
    /// cancelled or rejected (`DictationPipeline.retry(_:)` queues the last two first). A rejected one can succeed once
    /// the owner fixed the cause, for example added credit.
    public var isRetryable: Bool {
        switch status {
        case .pending, .failed, .cancelled, .rejected: true
        case .pasted, .copied, .recovered: false
        }
    }

    /// Records a failed request: `.failed` (retried), with `needsSetup` when only a setting can help,
    /// or `.rejected` when the same request cannot succeed. An empty transcript gets one retry
    /// before it counts as rejected. Errors that are not `ProviderError` count as transient.
    mutating func markFailed(by error: any Error, onRetry: Bool = false) {
        let providerError = error as? ProviderError
        needsSetup = providerError?.setupItem
        switch providerError?.recovery ?? .transient {
        case .transient, .needsSetup:
            status = .failed
        case .permanent:
            status = providerError == .emptyTranscript && !onRetry ? .failed : .rejected
        }
        rejectReason = status == .rejected ? providerError?.rejectReason : nil
    }
}

extension Store {
    /// Saves and logs a failure; the dictation goes on, and its audio file is kept either way.
    func saveOrLog(_ record: DictationRecord) async {
        do {
            try await save(record)
        } catch {
            Log.pipeline.error("Cannot save dictation \(record.id.rawValue): \(error)")
        }
    }

    /// Updates and logs a failure. False only when the row is gone: the dictation was deleted, so it has no outcome.
    func updateOrLog(_ record: DictationRecord) async -> Bool {
        do {
            return try await update(record)
        } catch {
            Log.pipeline.error("Cannot save dictation \(record.id.rawValue): \(error)")
            return true
        }
    }
}

/// One write to the history, as `DictationPipeline.historyChanges` reports it, so a reader updates only what changed.
public enum HistoryChange: Sendable, Equatable {
    /// The dictation's row was written: a new dictation, a new status, a retry's transcript.
    case saved(DictationID)
    case deleted(Set<DictationID>)
    /// Rows past the retention period were deleted; which ones is not reported.
    case pruned
}

/// Passes every call to `base` and announces each write, so the app reads its counts and lists again only then.
struct AnnouncingStore: Store {
    let base: any Store
    let changes: AsyncStream<HistoryChange>.Continuation

    func save(_ record: DictationRecord) async throws {
        defer { changes.yield(.saved(record.id)) }
        try await base.save(record)
    }

    func update(_ record: DictationRecord) async throws -> Bool {
        let isWritten = try await base.update(record)
        if isWritten { changes.yield(.saved(record.id)) }
        return isWritten
    }

    func pendingRetries() async throws -> [DictationRecord] {
        try await base.pendingRetries()
    }

    func status(of id: DictationID) async throws -> DictationRecord.Status? {
        try await base.status(of: id)
    }

    func recovered(since cutoff: Date) async throws -> [DictationRecord] {
        try await base.recovered(since: cutoff)
    }

    func markCopied(_ id: DictationID) async throws {
        defer { changes.yield(.saved(id)) }
        try await base.markCopied(id)
    }

    func queueForRetry(_ id: DictationID) async throws {
        defer { changes.yield(.saved(id)) }
        try await base.queueForRetry(id)
    }

    /// Announced only once done: a window that hides rows the store still has would show the wrong history.
    func delete(_ ids: Set<DictationID>) async throws {
        try await base.delete(ids)
        changes.yield(.deleted(ids))
    }

    func prune(olderThan cutoff: Date) async throws {
        defer { changes.yield(.pruned) }
        try await base.prune(olderThan: cutoff)
    }
}
