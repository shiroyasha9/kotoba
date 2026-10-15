import Foundation

/// Durable history: kept audio, the offline retry queue and latency logs.
public protocol Store: Sendable {
    func save(_ record: DictationRecord) async throws
    /// Records with status `.pending` or `.failed`: dictations whose audio has no transcript yet.
    func pendingRetries() async throws -> [DictationRecord]
    /// The stored status of one dictation, or nil when there is no row.
    func status(of id: DictationID) async throws -> DictationRecord.Status?
    /// Records with status `.recovered` and `recoveredAt` at or after `cutoff`, newest first. For
    /// the menu, so their latency logs may be left empty.
    func recovered(since cutoff: Date) async throws -> [DictationRecord]
    /// Sets one record's status to `.copied`, keeping everything else.
    func markCopied(_ id: DictationID) async throws
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

extension DictationRecord {
    /// The text kotoba pasted or offers to copy: the cleaned text of a cleanup dictation, else the transcript.
    public var deliveredText: String? { cleanedText ?? transcript }

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
}

/// Passes every call to `base` and announces each write, so the app reads its counts and lists again only then.
struct AnnouncingStore: Store {
    let base: any Store
    let changes: AsyncStream<Void>.Continuation

    func save(_ record: DictationRecord) async throws {
        defer { changes.yield() }
        try await base.save(record)
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
        defer { changes.yield() }
        try await base.markCopied(id)
    }

    func prune(olderThan cutoff: Date) async throws {
        defer { changes.yield() }
        try await base.prune(olderThan: cutoff)
    }
}
