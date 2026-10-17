import Foundation

@testable import KotobaCore

/// The history in memory.
actor FakeStore: Store {
    private(set) var records: [DictationRecord] = []
    /// Every status each dictation was saved with, in order.
    private(set) var history: [DictationID: [DictationRecord.Status]] = [:]
    /// The usage ledger: each entry once, kept when its dictation is deleted.
    private(set) var ledger: [UsageEntry] = []

    private func addToLedger(_ record: DictationRecord) {
        ledger += record.usage.filter { entry in !ledger.contains { $0.id == entry.id } }
    }

    func addUsage(_ entries: [UsageEntry]) async throws {
        ledger += entries.filter { entry in !ledger.contains { $0.id == entry.id } }
    }

    func setPolishedText(_ text: String?, of id: DictationID, usage: [UsageEntry]) async throws -> Bool {
        try await addUsage(usage)
        guard let index = records.firstIndex(where: { $0.id == id && $0.status.isTranscribed }) else { return false }
        records[index].polishedText = text
        return true
    }

    /// Discarded recordings whose file stayed (`markDiscarded`).
    private(set) var discarded: Set<DictationID> = []

    func markDiscarded(_ id: DictationID) async throws {
        discarded.insert(id)
    }

    func save(_ record: DictationRecord) async throws {
        addToLedger(record)
        records.removeAll { $0.id == record.id }
        records.append(record)
        history[record.id, default: []].append(record.status)
    }

    func update(_ record: DictationRecord) async throws -> Bool {
        if let updateError { throw updateError }
        addToLedger(record)
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return false }
        records[index] = record
        history[record.id, default: []].append(record.status)
        return true
    }

    func pendingRetries() async throws -> [DictationRecord] {
        records.filter { $0.status == .pending || $0.status == .failed }
    }

    func recovered(since cutoff: Date) async throws -> [DictationRecord] {
        records
            .filter { $0.status == .recovered && ($0.recoveredAt ?? .distantPast) >= cutoff }
            .sorted { ($0.recoveredAt ?? .distantPast) > ($1.recoveredAt ?? .distantPast) }
    }

    func lastDelivered() async throws -> DictationRecord? {
        records.filter { [.pasted, .copied, .notPasted].contains($0.status) }.max { $0.createdAt < $1.createdAt }
    }

    func status(of id: DictationID) async throws -> DictationRecord.Status? {
        records.first { $0.id == id }?.status
    }

    /// As the real store, which reads entries into the ledger and never back into a record.
    func queuedRecord(_ id: DictationID) async throws -> DictationRecord? {
        guard var record = records.first(where: { $0.id == id }), [.pending, .failed].contains(record.status)
        else { return nil }
        record.usage = []
        return record
    }

    func transcribedRecord(_ id: DictationID) async throws -> DictationRecord? {
        guard var record = records.first(where: { $0.id == id }), record.status.isTranscribed else { return nil }
        record.usage = []
        return record
    }

    func markCopied(_ id: DictationID) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = .copied
        history[id, default: []].append(.copied)
    }

    func queueForRetry(_ id: DictationID) async throws -> Bool {
        guard let index = records.firstIndex(where: { $0.id == id }),
            [.cancelled, .rejected].contains(records[index].status)
        else { return false }
        records[index].status = .failed
        records[index].rejectReason = nil
        history[id, default: []].append(.failed)
        return true
    }

    func delete(_ ids: Set<DictationID>) async throws -> Set<DictationID> {
        if let deleteError { throw deleteError }
        let kept = ids.intersection(undeletable)
        records.removeAll { ids.contains($0.id) && !kept.contains($0.id) }
        return kept
    }

    private var updateError: (any Error)?

    /// Every `update` throws `error` (nil: writes again), as a full disk does.
    func failUpdates(with error: (any Error)?) {
        updateError = error
    }

    private var deleteError: (any Error)?
    /// Dictations whose audio file cannot be removed: a delete keeps them.
    private var undeletable: Set<DictationID> = []

    func failDeletes(with error: any Error) {
        deleteError = error
    }

    func keepAudio(of ids: Set<DictationID>) {
        undeletable = ids
    }

    /// The cutoff of each `deleteAudio` batch, in order.
    private(set) var audioCutoffs: [Date] = []
    /// When set, each `deleteAudio` batch waits for this gate.
    private var audioGate: Gate?
    private var audioBatchSize = 500

    func holdAudioDeletion(at gate: Gate, batchSize: Int = 500) {
        audioGate = gate
        audioBatchSize = batchSize
    }

    /// As the real store: oldest text first, after `cursor`, up to a batch.
    func deleteAudio(transcribedBefore cutoff: Date, after cursor: AudioCursor?) async throws -> AudioBatch {
        audioCutoffs.append(cutoff)
        await audioGate?.pass()
        let expired = records.filter { $0.isAudioExpired(before: cutoff) }
            .compactMap { record in record.transcribedAt.map { AudioCursor(transcribedAt: $0, id: record.id) } }
            .sorted()
            .filter { next in cursor.map { next > $0 } ?? true }
            .prefix(audioBatchSize)
        for index in records.indices where expired.contains(where: { $0.id == records[index].id }) {
            records[index].isAudioDeleted = true
        }
        return AudioBatch(
            deleted: Set(expired.map(\.id)), next: expired.count == audioBatchSize ? expired.last : nil)
    }
}
