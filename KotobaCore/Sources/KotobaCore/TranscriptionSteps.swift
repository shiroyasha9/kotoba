/// The text steps a live dictation and a retry share: transcribe with the dictionary terms, apply
/// the replacements, and for a cleanup dictation clean the raw transcript.
struct TranscriptionSteps: Sendable {
    /// A transcript with the dictionary replacements applied.
    struct Transcribed: Sendable {
        /// What the provider heard, before replacements; the cleaner gets this.
        let raw: String
        let text: String
        let model: String
    }

    let provider: any TranscriptionProvider
    let cleaner: (any TextCleaner)?

    func transcribe(_ audio: RecordedAudio, settings: DictationPipeline.Settings) async throws -> Transcribed {
        let transcript = try await provider.transcribe(settings.request(for: audio))
        return Transcribed(
            raw: transcript.text,
            text: settings.dictionary.applyReplacements(to: transcript.text),
            model: transcript.model
        )
    }

    /// The cleaned text with replacements applied, or nil when there is no cleaner or it failed:
    /// the raw transcript is used then, and the cleanup is not retried. The replacements run once,
    /// on the cleaner's output, so a rule such as "kotoba" -> "kotoba.app" does not grow twice.
    func clean(_ raw: String, settings: DictationPipeline.Settings, id: DictationID) async -> String? {
        guard let cleaner else {
            Log.pipeline.error("Cleanup \(id.rawValue): no cleaner, using the raw transcript")
            return nil
        }
        do {
            let cleaned = try await cleaner.clean(raw, vocabulary: settings.dictionary.keyterms).text
            return settings.dictionary.applyReplacements(to: cleaned)
        } catch {
            Log.pipeline.error("Cleanup \(id.rawValue) failed, using the raw transcript: \(error)")
            return nil
        }
    }
}
