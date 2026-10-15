import Foundation

@testable import KotobaCore

/// The history in memory.
actor FakeStore: Store {
    private(set) var records: [DictationRecord] = []
    /// Every status each dictation was saved with, in order.
    private(set) var history: [DictationID: [DictationRecord.Status]] = [:]

    func save(_ record: DictationRecord) async throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
        history[record.id, default: []].append(record.status)
    }

    func update(_ record: DictationRecord) async throws -> Bool {
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

    func status(of id: DictationID) async throws -> DictationRecord.Status? {
        records.first { $0.id == id }?.status
    }

    func markCopied(_ id: DictationID) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].status = .copied
        history[id, default: []].append(.copied)
    }

    func queueForRetry(_ id: DictationID) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }),
            [.cancelled, .rejected].contains(records[index].status)
        else { return }
        records[index].status = .failed
        records[index].rejectReason = nil
        history[id, default: []].append(.failed)
    }

    func delete(_ ids: Set<DictationID>) async throws {
        if let deleteError { throw deleteError }
        records.removeAll { ids.contains($0.id) }
    }

    private var deleteError: (any Error)?

    func failDeletes(with error: any Error) {
        deleteError = error
    }

    func prune(olderThan cutoff: Date) async throws {
        records.removeAll { $0.createdAt < cutoff && $0.status != .pending && $0.status != .failed }
    }
}
