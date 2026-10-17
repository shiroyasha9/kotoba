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
    /// The stored record, latency marks included, while it has its text (`Status.isTranscribed`); nil otherwise.
    /// History's "Transcribe Again" sends this fresh copy, so its write keeps the marks.
    func transcribedRecord(_ id: DictationID) async throws -> DictationRecord?
    /// Records with status `.recovered` and `recoveredAt` at or after `cutoff`, newest first. For
    /// the menu, so their latency logs may be left empty.
    func recovered(since cutoff: Date) async throws -> [DictationRecord]
    /// The newest dictation whose text reached the owner (`.pasted` or `.copied`), by `createdAt`, with no latency
    /// log; nil when there is none. "Paste Last Dictation" pastes its `latestText`.
    func lastDelivered() async throws -> DictationRecord?
    /// Sets one record's status to `.copied`, keeping everything else.
    func markCopied(_ id: DictationID) async throws
    /// Puts a `.cancelled` or `.rejected` record in the retry queue as `.failed` and returns true; a record with any
    /// other status keeps it, and a missing one stays missing: false, nothing written.
    @discardableResult
    func queueForRetry(_ id: DictationID) async throws -> Bool
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
    /// Sets Polish's text of a dictation that has its text (nil removes it) and adds Polish's billed answers to the
    /// ledger, in one write that leaves every other column as it is, so a Polish never writes back a transcript it read
    /// before its request. False when the row is gone or has no text; the answers are billed either way.
    func setPolishedText(_ text: String?, of id: DictationID, usage: [UsageEntry]) async throws -> Bool
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
    /// Polish's rewrite of `deliveredText`, once the owner polished it; `deliveredText` stays the dictation's own text.
    public var polishedText: String?
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
    /// Failed sends that reached the route (`ProviderError.usesAttempt`), live and retried. At
    /// `RetrySelection.automaticAttempts` launch and a returning network stop sending the dictation; the owner's
    /// Retry still does.
    public var attempts = 0
    /// The last failed send timed out (`ProviderError.timedOut`), since this record was read from the store; the store
    /// does not keep it. The pill says so.
    public var hasTimedOut = false
    /// How long the route asked to wait before the next send (`ProviderError.rateLimited`), for the last failed send
    /// since this record was read from the store; the store does not keep it. The pipeline sends again then.
    public var retryAfter: Duration?
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

    /// The newest text the owner got: the polished text once Polish ran, else `deliveredText`. Paste Last, Copy Last,
    /// History's Copy and Paste Again, and the next Polish use it.
    public var latestText: String? { polishedText ?? deliveredText }

    /// There is text to copy, paste again or fix: `deliveredText` is there and not empty.
    public var hasText: Bool { deliveredText?.isEmpty == false }

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

    /// The audio file is kept: the dictation has audio and retention did not delete it.
    public var isAudioKept: Bool {
        audio.hasAudio && !isAudioDeleted
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
    /// or `.rejected` when the same request cannot succeed, an empty transcript included: the same audio gets the
    /// same answer. Errors that are not `ProviderError` count as transient. A send that reached the route uses an
    /// attempt, as does an error that is not `ProviderError` (a missing audio file fails the same way each time).
    mutating func markFailed(by error: any Error) {
        let providerError = error as? ProviderError
        if providerError?.usesAttempt ?? true { attempts += 1 }
        hasTimedOut = providerError == .timedOut
        retryAfter = providerError?.retryAfter
        needsSetup = providerError?.setupItem
        switch providerError?.recovery ?? .transient {
        case .transient, .needsSetup:
            status = .failed
        case .permanent:
            status = .rejected
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

    /// Adds billed answers to the ledger and logs a failure.
    func addUsageOrLog(_ entries: [UsageEntry], of id: DictationID) async {
        guard !entries.isEmpty else { return }
        do {
            try await addUsage(entries)
        } catch {
            Log.pipeline.error("Cannot bill the answers of \(id.rawValue): \(error)")
        }
    }

    /// Sets Polish's text and logs a failure. False when the row is gone or the store failed: nothing is pasted then.
    func setPolishedTextOrLog(_ text: String?, of id: DictationID, usage: [UsageEntry]) async -> Bool {
        do {
            return try await setPolishedText(text, of: id, usage: usage)
        } catch {
            Log.pipeline.error("Cannot save the polished text of \(id.rawValue): \(error)")
            return false
        }
    }

    /// Updates and logs a failure.
    func updateOrLog(_ record: DictationRecord) async -> StoreUpdate {
        do {
            return try await update(record) ? .written : .rowGone
        } catch {
            Log.pipeline.error("Cannot save dictation \(record.id.rawValue): \(error)")
            return .failed
        }
    }
}

/// What `Store.updateOrLog` did.
enum StoreUpdate {
    case written
    /// The owner deleted the dictation: it has no outcome.
    case rowGone
    /// The store failed (a full disk): nothing was written.
    case failed
}
