import Foundation

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

    /// A row was written or deleted: a status, a count or a text that lists show can differ.
    public var isRowChanged: Bool {
        switch self {
        case .saved, .deleted: true
        case .audioDeleted, .usageAdded: false
        }
    }

    /// The kept audio's size or its split between transcribed and waiting dictations can differ.
    public var isKeptAudioChanged: Bool {
        switch self {
        case .saved, .deleted, .audioDeleted: true
        case .usageAdded: false
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

    func transcribedRecord(_ id: DictationID) async throws -> DictationRecord? {
        try await base.transcribedRecord(id)
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

    /// Announced only when the record joined the queue: a Retry of a failed dictation writes nothing here.
    func queueForRetry(_ id: DictationID) async throws -> Bool {
        let isQueued = try await base.queueForRetry(id)
        if isQueued { changes.yield(.saved(id, isUsageAdded: false)) }
        return isQueued
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

    func setPolishedText(_ text: String?, of id: DictationID, usage: [UsageEntry]) async throws -> Bool {
        let isWritten = try await base.setPolishedText(text, of: id, usage: usage)
        if isWritten {
            changes.yield(.saved(id, isUsageAdded: !usage.isEmpty))
        } else if !usage.isEmpty {
            changes.yield(.usageAdded)
        }
        return isWritten
    }

    /// Not announced: no row changed.
    func markDiscarded(_ id: DictationID) async throws {
        try await base.markDiscarded(id)
    }
}
