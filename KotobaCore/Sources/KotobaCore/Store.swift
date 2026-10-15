import Foundation

/// Durable history: kept audio, the offline retry queue and latency logs.
public protocol Store: Sendable {
    func save(_ record: DictationRecord) async throws
    func pendingRetries() async throws -> [DictationRecord]
    /// Deletes records and their audio created before `cutoff` (retention period).
    /// Runs at launch or when idle, never on the dictation path.
    func prune(olderThan cutoff: Date) async throws
}

public struct DictationID: Hashable, Sendable {
    public var rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct DictationRecord: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case pasted
        case cancelled
        /// Audio kept; retried when the network returns.
        case failed
    }

    public var id: DictationID
    public var createdAt: Date
    public var audio: RecordedAudio
    public var transcript: String?
    public var status: Status
    public var latency: LatencyLog

    public init(
        id: DictationID,
        createdAt: Date,
        audio: RecordedAudio,
        transcript: String?,
        status: Status,
        latency: LatencyLog
    ) {
        self.id = id
        self.createdAt = createdAt
        self.audio = audio
        self.transcript = transcript
        self.status = status
        self.latency = latency
    }
}
