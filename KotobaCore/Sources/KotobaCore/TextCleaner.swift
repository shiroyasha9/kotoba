import Foundation

/// LLM cleanup of a finished transcript (docs/spec.md, "Cleanup"). It runs only on its own hotkey, never on the
/// main dictation path, and it treats the transcript as data, never as instructions.
public protocol TextCleaner: Sendable {
    /// Opens or refreshes the connection. The pipeline calls it when a press turns out to be the cleanup chord
    /// (`HotkeyEvent.cleanupModifier`).
    func warmUp() async
    /// Throws `ProviderError`, like `TranscriptionProvider.transcribe`, and like it returns an answer with no words
    /// with its cost. `vocabulary` is the dictionary's keyterms, already within the route limits.
    func clean(_ transcript: String, vocabulary: [String]) async throws -> CleanedText
}

public struct CleanedText: Sendable, Equatable {
    public var text: String
    /// The model identifier this request used.
    public var model: String
    /// The reported cost, else an estimate from the model's list price; nil when neither is known.
    public var cost: Cost?

    public init(text: String, model: String, cost: Cost?) {
        self.text = text
        self.model = model
        self.cost = cost
    }
}
