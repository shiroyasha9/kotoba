import Synchronization

/// The text steps a live dictation and a retry share: transcribe with the dictionary terms, remove a submit phrase,
/// apply the replacements, and for a cleanup dictation clean the raw transcript.
struct TranscriptionSteps: Sendable {
    /// A transcript with the dictionary replacements applied.
    struct Transcribed: Sendable {
        /// What the provider heard, without a submit phrase and before replacements; the cleaner gets this.
        let raw: String
        let text: String
        /// It ended with a submit phrase: a live dictation sends Return after the paste; a retry never does.
        var submits = false
        /// The upload's moments, when the route measured them.
        var network: NetworkTiming?
    }

    /// Why a cleanup gave no text; the raw transcript is used then.
    enum CleanupMiss: Error {
        /// No cleaner, an error, or an answer with no words.
        case failed
        /// No answer within `Settings.cleanupDeadline`.
        case tooSlow
    }

    let provider: any TranscriptionProvider
    let cleaner: (any TextCleaner)?
    /// Dates each billed answer in the usage ledger, and times the cleanup deadline.
    let clock: any PipelineClock
    /// Where a cleanup answer that came after its deadline is billed.
    let store: any Store
    /// Holds the deadline and a cleanup request that outlives it.
    let work: PendingWork

    /// Sends the record's audio and keeps the answer in it: the model and a usage entry first (an answer with no words
    /// is billed too), then the transcript. Throws `ProviderError.emptyTranscript` when the provider heard no words;
    /// the pipeline owns that decision and the trim, whatever the route sends.
    func transcribe(_ record: inout DictationRecord, settings: DictationPipeline.Settings) async throws -> Transcribed {
        let transcript = try await provider.transcribe(settings.request(for: record.audio))
        record.model = transcript.model
        let heard = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Matched on what the owner said, before the replacements, so a rule can neither make nor break the phrase.
        let (raw, submits) = settings.isSubmitPhraseOn ? SubmitPhrase.split(heard) : (heard, false)
        let transcribed = Transcribed(
            raw: raw, text: settings.dictionary.applyReplacements(to: raw), submits: submits,
            network: transcript.network)
        let words = DictationRecord.wordCount(of: transcribed.text)
        record.usage.append(
            UsageEntry(
                time: clock.date, dictation: record.id, kind: .speech, model: transcript.model,
                audio: transcript.usage.audio, deliveredWords: words, spokenWords: words,
                cost: transcript.usage.cost, app: record.app))
        guard !heard.isEmpty else { throw ProviderError.emptyTranscript }
        record.transcript = transcribed.text
        return transcribed
    }

    /// Sets the record's cleaned text with replacements applied, or nil when there is no cleaner, it failed or it
    /// answered no words: the raw transcript is used then, and the cleanup is not retried. An answer's usage goes to
    /// the record, empty or not. The replacements run once, on the cleaner's output, so a rule such as
    /// "kotoba" -> "kotoba.app" does not grow twice.
    @discardableResult
    /// `deadline` bounds a live cleanup, whose paste waits on it; a retry passes nil, so its cleanup waits for the
    /// cleaner's own timeout.
    func clean(
        _ raw: String, in mode: AppMode, into record: inout DictationRecord, settings: DictationPipeline.Settings,
        deadline: Duration?
    ) async -> CleanupMiss? {
        switch await cleaned(raw, in: mode, record: &record, settings: settings, deadline: deadline) {
        case .success(let text):
            record.cleanedText = text
            return nil
        case .failure(let miss):
            record.cleanedText = nil
            return miss
        }
    }

    private func cleaned(
        _ raw: String, in mode: AppMode, record: inout DictationRecord, settings: DictationPipeline.Settings,
        deadline: Duration?
    ) async -> Result<String, CleanupMiss> {
        let id = record.id
        guard let cleaner else {
            Log.pipeline.error("Cleanup \(id.rawValue): no cleaner, using the raw transcript")
            return .failure(.failed)
        }
        let cleaned: CleanedText
        let terms = settings.dictionary.keyterms
        let request: @Sendable () async throws -> CleanedText = {
            try await cleaner.clean(raw, vocabulary: terms, mode: mode)
        }
        switch await answer(to: request, for: record, deadline: deadline) {
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
        let replaced = settings.dictionary.applyReplacements(to: text)
        // A used cleanup replaces the transcript's words with its own.
        let change =
            text.isEmpty
            ? 0 : DictationRecord.wordCount(of: replaced) - DictationRecord.wordCount(of: record.transcript ?? "")
        record.usage.append(
            UsageEntry(
                time: clock.date, dictation: id, kind: .cleanup, model: cleaned.model, deliveredWords: change,
                cost: cleaned.cost, app: record.app))
        guard !text.isEmpty else {
            Log.pipeline.error("Cleanup \(id.rawValue) answered no words, using the raw transcript")
            return .failure(.failed)
        }
        return .success(replaced)
    }

    private enum Answer: Sendable {
        case answered(Result<CleanedText, any Error>)
        case tooSlow
    }

    /// The cleaner's answer, or `.tooSlow` when `deadline` passes first on the pipeline clock. The request is not
    /// cancelled: a late answer was billed, so its cost goes to the ledger when it comes, with no words delivered.
    private func answer(
        to request: @escaping @Sendable () async throws -> CleanedText, for record: DictationRecord,
        deadline: Duration?
    ) async -> Answer {
        guard let deadline else {
            do {
                return .answered(.success(try await request()))
            } catch {
                return .answered(.failure(error))
            }
        }
        let first = FirstOf<Answer>()
        let timer = work.schedule(at: clock.now + deadline) { first.settle(.tooSlow) }
        work.track { [clock, store, id = record.id, app = record.app] in
            let result: Result<CleanedText, any Error>
            do {
                result = .success(try await request())
            } catch {
                result = .failure(error)
            }
            guard !first.settle(.answered(result)), case .success(let late) = result else { return }
            do {
                try await store.addUsage([
                    UsageEntry(
                        time: clock.date, dictation: id, kind: .cleanup, model: late.model, deliveredWords: 0,
                        cost: late.cost, app: app)
                ])
            } catch {
                Log.pipeline.error("Cleanup \(id.rawValue): cannot bill the late answer: \(error)")
            }
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
