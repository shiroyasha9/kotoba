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
    }

    let provider: any TranscriptionProvider
    let cleaner: (any TextCleaner)?
    /// Dates each billed answer in the usage ledger.
    let clock: any PipelineClock

    /// Sends the record's audio and keeps the answer in it: the model and a usage entry first (an answer with no words
    /// is billed too), then the transcript. Throws `ProviderError.emptyTranscript` when the provider heard no words;
    /// the pipeline owns that decision and the trim, whatever the route sends.
    func transcribe(_ record: inout DictationRecord, settings: DictationPipeline.Settings) async throws -> Transcribed {
        let transcript = try await provider.transcribe(settings.request(for: record.audio))
        record.model = transcript.model
        let heard = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Matched on what the owner said, before the replacements, so a rule can neither make nor break the phrase.
        let (raw, submits) = settings.isSubmitPhraseOn ? SubmitPhrase.split(heard) : (heard, false)
        let transcribed = Transcribed(raw: raw, text: settings.dictionary.applyReplacements(to: raw), submits: submits)
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
    func clean(
        _ raw: String, in mode: AppMode, into record: inout DictationRecord, settings: DictationPipeline.Settings
    ) async {
        record.cleanedText = await cleaned(raw, in: mode, record: &record, settings: settings)
    }

    private func cleaned(
        _ raw: String, in mode: AppMode, record: inout DictationRecord, settings: DictationPipeline.Settings
    ) async -> String? {
        let id = record.id
        guard let cleaner else {
            Log.pipeline.error("Cleanup \(id.rawValue): no cleaner, using the raw transcript")
            return nil
        }
        let cleaned: CleanedText
        do {
            cleaned = try await cleaner.clean(raw, vocabulary: settings.dictionary.keyterms, mode: mode)
        } catch {
            Log.pipeline.error("Cleanup \(id.rawValue) failed, using the raw transcript: \(error)")
            return nil
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
            return nil
        }
        return replaced
    }
}
