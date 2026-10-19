import Foundation
import Synchronization

/// The text steps a live dictation and a retry share: transcribe with the dictionary terms, remove a submit phrase,
/// make spoken line breaks, apply the replacements, and for a cleanup dictation clean the raw transcript.
struct TranscriptionSteps: Sendable {
    /// A transcript with the dictionary replacements applied.
    struct Transcribed: Sendable {
        /// What the provider heard, without a submit phrase, with spoken line breaks made (`LineBreakPhrase`) and
        /// before replacements; the cleaner gets this.
        let raw: String
        let text: String
        /// When the answer came: its ledger entry's time, which the cleanup's entry takes too.
        let answeredAt: Date
        /// It ended with a submit phrase: a live dictation sends Return after the paste; a retry never does.
        var submits = false
        /// The upload's moments, when the route measured them.
        var network: NetworkTiming?
    }

    /// Why a cleanup gave no text; the raw transcript is used then.
    enum CleanupMiss: Error {
        /// No cleaner, an error, an answer with no words, or a cut answer.
        case failed
        /// No answer within `Settings.cleanupDeadline`.
        case tooSlow
    }

    let provider: any TranscriptionProvider
    let cleaner: (any TextCleaner)?
    /// Dates each speech answer in the usage ledger, and times the cleanup deadline.
    let clock: any PipelineClock
    /// Where a cleanup answer that came after its deadline is billed.
    let store: any Store
    /// Holds the deadline and a cleanup request that outlives it.
    let work: PendingWork

    /// Sends the record's audio and keeps the answer in it: the model and a usage entry first (an answer with no words
    /// is billed too), then the transcript. Throws `ProviderError.emptyTranscript` when the provider heard no words;
    /// the pipeline owns that decision and the trim, whatever the route sends. A record with no audio is never sent:
    /// `ProviderError.noAudio`, so it is rejected at once, live or on a retry. `model` replaces the owner's choice of
    /// model for this request (`TranscriptionRequest.model`).
    func transcribe(
        _ record: inout DictationRecord, settings: DictationPipeline.Settings, model: String? = nil
    ) async throws -> Transcribed {
        guard record.audio.hasAudio else { throw ProviderError.noAudio }
        var request = settings.request(for: record.audio, at: clock.date)
        // The upload copy serves this request only: a retry, and History, send the FLAC.
        defer {
            AudioCapture.removeUploadCopy(request.upload)
            record.audio.upload = nil
        }
        request.model = model
        record.sentTerms = request.dictionaryTerms
        let transcript = try await answer(
            to: request, within: DictationPipeline.Settings.transcriptionTimeout(for: request.duration))
        record.model = transcript.model
        let heard = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Matched on what the owner said, before the replacements, so a rule can neither make nor break a command.
        let (said, submits) = settings.isSubmitPhraseOn ? SubmitPhrase.split(heard) : (heard, false)
        // Before the cleanup too: the cleaner gets the breaks, not words it could drop as noise.
        let raw =
            settings.isLineBreakPhraseOn
            ? LineBreakPhrase.apply(to: said, capitalizes: settings.modes.mode(for: record.app) != .code) : said
        let transcribed = Transcribed(
            raw: raw, text: settings.dictionary.applyReplacements(to: raw), answeredAt: clock.date, submits: submits,
            network: transcript.network)
        let words = DictationRecord.wordCount(of: transcribed.text)
        record.usage.append(
            UsageEntry(
                time: transcribed.answeredAt, dictation: record.id, kind: .speech, model: transcript.model,
                audio: transcript.usage.audio, deliveredWords: words, spokenWords: words,
                cost: transcript.usage.cost, app: record.app))
        guard !heard.isEmpty else { throw ProviderError.emptyTranscript }
        record.transcript = transcribed.text
        return transcribed
    }

    /// The provider's answer, or `ProviderError.timedOut` when `limit` passes first on the pipeline clock. A task group,
    /// not `FirstOf` as the cleanup's deadline: the request is cancelled then (no late answer is used), and the
    /// dictation stays queued.
    private func answer(to request: TranscriptionRequest, within limit: Duration) async throws -> Transcript {
        let deadline = clock.now + limit
        return try await withThrowingTaskGroup(of: Transcript?.self) { group in
            group.addTask { [provider] in try await provider.transcribe(request) }
            group.addTask { [clock] in
                try await clock.sleep(until: deadline)
                return nil
            }
            // The loser ends at once: the timer's sleep, or the request, which URLSession cancels.
            defer { group.cancelAll() }
            // `next()` is nil only for an empty group; the timer's own answer is nil.
            guard case .some(.some(let transcript)) = try await group.next() else {
                Log.pipeline.error("No answer within \(limit), the request is cancelled")
                throw ProviderError.timedOut
            }
            return transcript
        }
    }

    /// Sets the record's cleaned text with replacements applied, or nil when there is no cleaner, it failed, it
    /// answered no words or its answer was cut (`RewrittenText.isComplete`): the raw transcript is used then, and the
    /// cleanup is not retried. An answer's usage goes to the record, empty or not, dated with the transcript's answer:
    /// its word change counts on the same day as the words it changes, even when it comes after midnight. The replacements run once, on the cleaner's output, so a
    /// rule such as "kotoba" -> "kotoba.app" does not grow twice.
    /// `deadline` bounds a live cleanup, whose paste waits on it; a retry passes nil, so its cleanup waits for the
    /// cleaner's own timeout.
    @discardableResult
    func clean(
        _ transcribed: Transcribed, in mode: AppMode, into record: inout DictationRecord,
        settings: DictationPipeline.Settings, deadline: Duration?
    ) async -> CleanupMiss? {
        switch await cleaned(transcribed, in: mode, record: &record, settings: settings, deadline: deadline) {
        case .success(let text):
            record.cleanedText = text
            return nil
        case .failure(let miss):
            record.cleanedText = nil
            return miss
        }
    }

    private func cleaned(
        _ transcribed: Transcribed, in mode: AppMode, record: inout DictationRecord,
        settings: DictationPipeline.Settings, deadline: Duration?
    ) async -> Result<String, CleanupMiss> {
        let id = record.id
        let raw = transcribed.raw
        guard let cleaner else {
            Log.pipeline.error("Cleanup \(id.rawValue): no cleaner, using the raw transcript")
            return .failure(.failed)
        }
        let cleaned: RewrittenText
        // The keyterms the transcription sent, so the cleaner's list stays within the same cap.
        let terms =
            record.sentTerms ?? TermRanking.keyterms(of: settings.dictionary, use: settings.termUse, at: clock.date)
        let request: @Sendable () async throws -> RewrittenText = {
            try await cleaner.clean(raw, vocabulary: terms, mode: mode)
        }
        switch await answer(to: request, for: record, at: transcribed.answeredAt, deadline: deadline) {
        case .answered(.success(let answer)):
            cleaned = answer
        case .answered(.failure(let error)):
            Log.pipeline.error("Cleanup \(id.rawValue) failed, using the raw transcript: \(error)")
            return .failure(.failed)
        case .tooSlow:
            Log.pipeline.error("Cleanup \(id.rawValue) passed its deadline, using the raw transcript")
            return .failure(.tooSlow)
        }
        let text = cleaned.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An answer that did not end on its own is partial: pasting it would drop the end of what the owner said.
        let replaced = cleaned.isComplete && !text.isEmpty ? settings.dictionary.applyReplacements(to: text) : nil
        // A used cleanup replaces the transcript's words with its own.
        let change = replaced.map {
            DictationRecord.wordCount(of: $0) - DictationRecord.wordCount(of: record.transcript ?? "")
        }
        record.usage.append(
            UsageEntry(
                time: transcribed.answeredAt, dictation: id, kind: .cleanup, model: cleaned.model,
                deliveredWords: change ?? 0,
                cost: cleaned.cost, app: record.app))
        guard let replaced else {
            let answered = cleaned.isComplete ? "no words" : "a text that did not end on its own"
            Log.pipeline.error("Cleanup \(id.rawValue) answered \(answered), using the raw transcript")
            return .failure(.failed)
        }
        return .success(replaced)
    }

    /// The cleaner's answer, or `.tooSlow` when `deadline` passes first on the pipeline clock. The request is not
    /// cancelled: a late answer was billed, so its cost goes to the ledger when it comes, with no words delivered,
    /// dated `time` (its transcript's answer).
    private func answer(
        to request: @escaping @Sendable () async throws -> RewrittenText, for record: DictationRecord, at time: Date,
        deadline: Duration?
    ) async -> Deadlined<RewrittenText> {
        guard let deadline else {
            do {
                return .answered(.success(try await request()))
            } catch {
                return .answered(.failure(error))
            }
        }
        let (store, id, app) = (store, record.id, record.app)
        return await work.answer(to: request, within: deadline, on: clock) { late in
            do {
                try await store.addUsage([
                    UsageEntry(
                        time: time, dictation: id, kind: .cleanup, model: late.model, deliveredWords: 0,
                        cost: late.cost, app: app)
                ])
            } catch {
                Log.pipeline.error("Cleanup \(id.rawValue): cannot bill the late answer: \(error)")
            }
        }
    }
}

/// A request's answer, or the deadline that passed first (`PendingWork.answer`).
enum Deadlined<Value: Sendable>: Sendable {
    case answered(Result<Value, any Error>)
    case tooSlow
}

extension PendingWork {
    /// `request`'s answer, or `.tooSlow` when `deadline` passes first on `clock`: a live cleanup and Polish, whose
    /// paste waits. The request is not cancelled: a late answer was billed, so it goes to `late` when it comes.
    func answer<Value: Sendable>(
        to request: @escaping @Sendable () async throws -> Value, within deadline: Duration,
        on clock: any PipelineClock,
        late: @escaping @Sendable (Value) async -> Void
    ) async -> Deadlined<Value> {
        let first = FirstOf<Deadlined<Value>>()
        let timer = schedule(at: clock.now + deadline) { first.settle(.tooSlow) }
        track {
            let result: Result<Value, any Error>
            do {
                result = .success(try await request())
            } catch {
                result = .failure(error)
            }
            guard !first.settle(.answered(result)), case .success(let value) = result else { return }
            await late(value)
        }
        let answer = await first.value
        timer.cancel()
        return answer
    }
}

/// The first of two events, such as an answer and its deadline: the first value settles it; a later one is told it lost.
final class FirstOf<Value: Sendable>: Sendable {
    private enum State {
        case open(waiter: CheckedContinuation<Value, Never>?)
        case settled(Value)
    }

    private let state = Mutex(State.open(waiter: nil))

    /// True when `value` came first.
    @discardableResult
    func settle(_ value: Value) -> Bool {
        let won = state.withLock { state -> (isFirst: Bool, waiter: CheckedContinuation<Value, Never>?) in
            guard case .open(let waiter) = state else { return (false, nil) }
            state = .settled(value)
            return (true, waiter)
        }
        won.waiter?.resume(returning: value)
        return won.isFirst
    }

    /// The first value, once one came. One waiter only.
    var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                let settled = state.withLock { state -> Value? in
                    switch state {
                    case .settled(let value): return value
                    case .open:
                        state = .open(waiter: continuation)
                        return nil
                    }
                }
                if let settled { continuation.resume(returning: settled) }
            }
        }
    }
}
