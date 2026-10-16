import Foundation

/// Durable history: kept audio, the offline retry queue and latency logs.
public protocol Store: Sendable {
    func save(_ record: DictationRecord) async throws
    /// Writes a record whose row still exists and returns true; returns false and writes nothing when the row is gone
    /// (the owner deleted it while a retry ran), so a late write never brings a deleted dictation back.
    func update(_ record: DictationRecord) async throws -> Bool
    /// Records with status `.pending` or `.failed`: dictations whose audio has no transcript yet.
    func pendingRetries() async throws -> [DictationRecord]
    /// The stored record, latency marks included, while it is `.pending` or `.failed`; nil otherwise. A retry sends
    /// this fresh copy, so it keeps what a live try wrote after the queue was read.
    func queuedRecord(_ id: DictationID) async throws -> DictationRecord?
    /// Records with status `.recovered` and `recoveredAt` at or after `cutoff`, newest first. For
    /// the menu, so their latency logs may be left empty.
    func recovered(since cutoff: Date) async throws -> [DictationRecord]
    /// The newest dictation whose text reached the owner (`.pasted` or `.copied`), by `createdAt`, with no latency
    /// log; nil when there is none. "Paste Last Dictation" pastes its `deliveredText`.
    func lastDelivered() async throws -> DictationRecord?
    /// Sets one record's status to `.copied`, keeping everything else.
    func markCopied(_ id: DictationID) async throws
    /// Puts a `.cancelled` or `.rejected` record in the retry queue as `.failed`; a record with any other status keeps
    /// it.
    func queueForRetry(_ id: DictationID) async throws
    /// Deletes the records, their latency logs and their audio files (the History pane's Delete), each audio file
    /// first: a record whose file cannot be removed stays, with its file, so no deleted dictation leaves audio with no
    /// record (`OrphanAudio` would bring it back). Returns the ids that stay for that reason.
    func delete(_ ids: Set<DictationID>) async throws -> Set<DictationID>
    /// One batch of audio retention: of the dictations whose audio expired before `cutoff`
    /// (`DictationRecord.isAudioExpired(before:)`), oldest text first and after `cursor`, deletes the files and marks
    /// the rows `isAudioDeleted`; rows, their text and the usage ledger stay. Only a file inside the audio folder, found by
    /// its name, is removed; a row whose file cannot be removed stays unmarked, so a later run tries it again. Audio
    /// retention calls it on its events (`AudioRetention.swift`), never before a paste.
    func deleteAudio(transcribedBefore cutoff: Date, after cursor: AudioCursor?) async throws -> AudioBatch
    /// Adds billed answers to the usage ledger, each once (by `UsageEntry.id`), with no row write: a cleanup answer that
    /// came after its deadline was dropped, but it was billed.
    func addUsage(_ entries: [UsageEntry]) async throws
    /// Remembers a discarded recording whose audio file stayed on disk (`AudioSource.discardCapture`), with no row: the
    /// launch never takes its file for an orphan, and removes it (`OrphanAudio.discardedFiles`).
    func markDiscarded(_ id: DictationID) async throws
}

public struct DictationID: Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct DictationRecord: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable, CaseIterable {
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

        /// The dictation has its text, so its audio is no longer needed: pasted, copied or recovered. The other
        /// statuses keep their audio until the owner deletes the dictation.
        public var isTranscribed: Bool {
            switch self {
            case .pasted, .copied, .recovered: true
            case .pending, .failed, .cancelled, .rejected: false
            }
        }
    }

    public var id: DictationID
    public var createdAt: Date
    public var audio: RecordedAudio
    public var transcript: String?
    /// The provider's model for the last request; nil when no request was sent.
    public var model: String?
    public var status: Status
    /// Cleanup dictations also run the cleaner, in the same mode, when they are retried.
    public var output = DictationOutput.transcript
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
    /// Audio retention deleted the audio file; the row keeps its text. Only `Store.deleteAudio` sets it.
    public var isAudioDeleted = false
    /// The answers billed since this record was read from the store: the store adds each one to the usage ledger once
    /// (by `UsageEntry.id`), so saving the record again adds nothing. A record read back has none.
    public var usage: [UsageEntry] = []
    /// The keyterms the last request sent, since this record was read from the store; the store does not keep them.
    /// The pipeline reports them once the dictation has its text (`TermReport`).
    public var sentTerms: [String]?
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

    /// The words of `deliveredText`, as the History pane counts them; the usage ledger counts each answer's text
    /// the same way. Nil when there is no text.
    public var wordCount: Int? {
        deliveredText.map(Self.wordCount(of:))
    }

    /// Runs of non-space characters, counted without building them, over Unicode scalars with an ASCII fast path:
    /// about 0.4 µs for 50 words against 11 µs over characters (release build, 100,000 runs). It runs before Cmd-V,
    /// for each speech answer's ledger entry.
    public static func wordCount(of text: String) -> Int {
        var count = 0
        var isInWord = false
        for scalar in text.unicodeScalars {
            let isSpace =
                scalar.isASCII ? scalar == " " || (9...13).contains(scalar.value) : scalar.properties.isWhitespace
            if isSpace {
                isInWord = false
            } else if !isInWord {
                isInWord = true
                count += 1
            }
        }
        return count
    }

    /// A dictation with no text yet that the History pane's Retry can send, while its audio is kept: queued, failed,
    /// cancelled or rejected (`DictationPipeline.retry(_:)` queues the last two first). A rejected one can succeed once
    /// the owner fixed the cause, for example added credit. One with no audio cannot (`RecordedAudio.hasAudio`).
    public var isRetryable: Bool {
        !status.isTranscribed && audio.hasAudio
    }

    /// When the dictation got its text: the retry that recovered it, else the dictation itself (its paste or copy
    /// comes seconds after `createdAt`). Nil while it has none. Audio retention counts from here.
    public var transcribedAt: Date? {
        status.isTranscribed ? recoveredAt ?? createdAt : nil
    }

    /// The audio is still on disk and the dictation got its text before `cutoff`: audio retention deletes it.
    /// `Store.deleteAudio` applies this rule to many rows (in SQL in the app's store).
    public func isAudioExpired(before cutoff: Date) -> Bool {
        guard let transcribedAt, !isAudioDeleted else { return false }
        return transcribedAt < cutoff
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
    /// The dictation's row was written: a new dictation, a new status, a retry's transcript. `isUsageAdded` when the
    /// same write took billed answers to the usage ledger (`DictationRecord.usage`).
    case saved(DictationID, isUsageAdded: Bool)
    case deleted(Set<DictationID>)
    /// Audio retention deleted the audio of these rows (`DictationRecord.isAudioDeleted`); the rows stay.
    case audioDeleted(Set<DictationID>)
    /// Billed answers went to the usage ledger with no row write (`Store.addUsage`).
    case usageAdded

    /// The write took billed answers to the usage ledger; a row write with no answer (the pending save at upload
    /// start, a status change) and a delete leave the ledger as it was.
    public var isUsageAdded: Bool {
        switch self {
        case .saved(_, let isUsageAdded): isUsageAdded
        case .usageAdded: true
        case .deleted, .audioDeleted: false
        }
    }
}

/// Passes every call to `base` and announces each write, so the app reads its counts and lists again only then.
struct AnnouncingStore: Store {
    let base: any Store
    let changes: AsyncStream<HistoryChange>.Continuation

    func save(_ record: DictationRecord) async throws {
        defer { changes.yield(.saved(record.id, isUsageAdded: !record.usage.isEmpty)) }
        try await base.save(record)
    }

    /// A record whose row is gone still adds its billed answers to the ledger.
    func update(_ record: DictationRecord) async throws -> Bool {
        let isWritten = try await base.update(record)
        if isWritten {
            changes.yield(.saved(record.id, isUsageAdded: !record.usage.isEmpty))
        } else if !record.usage.isEmpty {
            changes.yield(.usageAdded)
        }
        return isWritten
    }

    func pendingRetries() async throws -> [DictationRecord] {
        try await base.pendingRetries()
    }

    func queuedRecord(_ id: DictationID) async throws -> DictationRecord? {
        try await base.queuedRecord(id)
    }

    func recovered(since cutoff: Date) async throws -> [DictationRecord] {
        try await base.recovered(since: cutoff)
    }

    func lastDelivered() async throws -> DictationRecord? {
        try await base.lastDelivered()
    }

    func markCopied(_ id: DictationID) async throws {
        defer { changes.yield(.saved(id, isUsageAdded: false)) }
        try await base.markCopied(id)
    }

    func queueForRetry(_ id: DictationID) async throws {
        defer { changes.yield(.saved(id, isUsageAdded: false)) }
        try await base.queueForRetry(id)
    }

    /// Announced only once done, and only the rows that went: a window that hides rows the store still has would show
    /// the wrong history.
    func delete(_ ids: Set<DictationID>) async throws -> Set<DictationID> {
        let kept = try await base.delete(ids)
        let deleted = ids.subtracting(kept)
        if !deleted.isEmpty { changes.yield(.deleted(deleted)) }
        return kept
    }

    /// Announced only when a file went: retention runs after each dictation, and many runs delete nothing.
    func deleteAudio(transcribedBefore cutoff: Date, after cursor: AudioCursor?) async throws -> AudioBatch {
        let batch = try await base.deleteAudio(transcribedBefore: cutoff, after: cursor)
        if !batch.deleted.isEmpty { changes.yield(.audioDeleted(batch.deleted)) }
        return batch
    }

    func addUsage(_ entries: [UsageEntry]) async throws {
        defer { changes.yield(.usageAdded) }
        try await base.addUsage(entries)
    }

    /// Not announced: no row changed.
    func markDiscarded(_ id: DictationID) async throws {
        try await base.markDiscarded(id)
    }
}
