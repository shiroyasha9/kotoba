import Foundation

/// Story 31: how long kotoba keeps a dictation's audio once the dictation has its text. Only the audio file goes: the
/// row, its text and the usage ledger stay. A dictation without text (queued, failed, cancelled, refused) keeps its
/// audio until it is transcribed or the owner deletes it, so a retry always has it.
public enum AudioRetention: Int, CaseIterable, Sendable {
    // The raw value is the number of days, as UserDefaults keeps it; 0 is forever.
    case oneDay = 1
    case sevenDays = 7
    case thirtyDays = 30
    case forever = 0

    public static let standard = Self.sevenDays

    /// The period of an install with no stored choice: 7 days for a new install, and Forever for one whose history
    /// comes from a build without retention, so an update never deletes audio the owner did not choose to lose.
    public static func firstChoice(hasEarlierHistory: Bool) -> Self {
        hasEarlierHistory ? .forever : .standard
    }

    /// A change to `self` from `other` deletes audio that `other` keeps: Settings asks first.
    public func keepsLess(than other: Self) -> Bool {
        switch (self, other) {
        case (.forever, _): false
        case (_, .forever): true
        default: rawValue < other.rawValue
        }
    }

    /// Audio of dictations transcribed before this goes; nil keeps all. A day is 24 hours from the transcription, not a
    /// calendar day: audio from 23:59 lives as long as audio from 00:01. Dates are absolute, so time zones and DST do
    /// not matter. A wall clock set forward deletes early, and nothing here can tell without a trusted time source;
    /// accepted. A clock set back keeps audio longer, the safe side.
    public func cutoff(at now: Date) -> Date? {
        self == .forever ? nil : now - TimeInterval(rawValue) * 24 * 60 * 60
    }

    /// Whether `record`'s audio is past the period at `now`.
    public func isExpired(_ record: DictationRecord, at now: Date) -> Bool {
        cutoff(at: now).map(record.isAudioExpired(before:)) ?? false
    }
}

/// One run at a time, in batches (`Store.deleteAudio`). A request during a run asks for one more run after it; each
/// batch takes its cutoff from the setting as it is then, so "Forever" chosen during a run stops it after the batch in
/// progress. Launch, a dictation and a Settings change never delete the same files twice.
struct AudioDeletion: Sendable {
    enum Scope: Sendable {
        /// Past `Settings.audioRetention`.
        case expired
        /// "Delete Audio Now…": every transcribed dictation's audio.
        case all
    }

    var isRunning = false
    /// Asked for during the run; `.all` wins.
    var due: Scope?

    mutating func ask(_ scope: Scope) {
        due = due == .all ? .all : scope
    }
}

// MARK: - When retention runs

/// Event-driven, never on a timer: at launch, after each dictation that got its text (live or by a retry), and when
/// the owner changes the period. Each run is one indexed read when nothing expired.
extension DictationPipeline {
    /// Deletes the audio past `Settings.audioRetention`.
    public func deleteExpiredAudio() async {
        await deleteAudio(.expired)
    }

    /// The owner chose another period: it applies at once, also to a run in progress.
    public func updateAudioRetention(_ retention: AudioRetention) async {
        settings.audioRetention = retention
        await deleteAudio(.expired)
    }

    /// "Delete Audio Now…": the audio of every dictation that has its text, whatever its age.
    public func deleteTranscribedAudio() async {
        await deleteAudio(.all)
    }

    private func deleteAudio(_ scope: AudioDeletion.Scope) async {
        audioDeletion.ask(scope)
        guard !audioDeletion.isRunning else { return }
        audioDeletion.isRunning = true
        defer { audioDeletion.isRunning = false }
        while let scope = audioDeletion.due {
            audioDeletion.due = nil
            var cursor: AudioCursor?
            repeat {
                let cutoff = scope == .all ? .distantFuture : settings.audioRetention.cutoff(at: ports.clock.date)
                guard let cutoff else { break }
                do {
                    cursor = try await ports.store.deleteAudio(transcribedBefore: cutoff, after: cursor).next
                } catch {
                    Log.pipeline.error("Cannot delete old audio: \(error)")
                    break
                }
            } while cursor != nil
        }
    }
}

/// Where a batch of audio retention stopped: the last row it read, in `transcribedAt` then id order.
public struct AudioCursor: Sendable, Comparable {
    public var transcribedAt: Date
    public var id: DictationID

    public init(transcribedAt: Date, id: DictationID) {
        self.transcribedAt = transcribedAt
        self.id = id
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.transcribedAt != rhs.transcribedAt
            ? lhs.transcribedAt < rhs.transcribedAt : lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }
}

public struct AudioBatch: Sendable, Equatable {
    /// The rows marked `isAudioDeleted`.
    public var deleted: Set<DictationID>
    /// Where the next batch starts; nil when this one was the last.
    public var next: AudioCursor?

    public init(deleted: Set<DictationID>, next: AudioCursor?) {
        self.deleted = deleted
        self.next = next
    }
}
