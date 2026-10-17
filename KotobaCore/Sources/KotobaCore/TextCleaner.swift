import Foundation

/// LLM cleanup of a finished transcript (docs/spec.md, "Cleanup"). It runs only on its own hotkey or in a mode that
/// cleans every dictation, never for a plain dictation, and it treats the transcript as data, never as instructions.
public protocol TextCleaner: Sendable {
    /// Opens or refreshes the connection. The pipeline calls it when a press turns out to be the cleanup chord
    /// (`HotkeyEvent.cleanupModifier`), at key-down in a mode that cleans every dictation, and at a stop that decides on
    /// cleanup when neither came before.
    func warmUp() async
    /// Throws `ProviderError`, like `TranscriptionProvider.transcribe`, and like it returns an answer with no words
    /// with its cost. `vocabulary` is the dictionary's keyterms, already within the route limits; `mode` is the mode of
    /// the app the text goes to, which picks the prompt.
    func clean(_ transcript: String, vocabulary: [String], mode: AppMode) async throws -> RewrittenText
}

/// An LLM's rewrite of a dictated text: a cleanup (`TextCleaner`) or a polish (`TextPolisher`).
public struct RewrittenText: Sendable, Equatable {
    public var text: String
    /// The model identifier that answered.
    public var model: String
    /// The reported cost, else an estimate from the model's list price; nil when neither is known.
    public var cost: Cost?
    /// The model ended the text itself (`finish_reason` "stop"); false when the answer was cut at the token limit or
    /// filtered, so the text is partial and never pasted.
    public var isComplete: Bool

    public init(text: String, model: String, cost: Cost?, isComplete: Bool) {
        self.text = text
        self.model = model
        self.cost = cost
        self.isComplete = isComplete
    }
}
