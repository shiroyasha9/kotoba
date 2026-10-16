import Foundation

/// Polish (docs/spec.md, "Polish and View Changes"): an LLM rewrite of the last dictation, shorter and clearer with
/// nothing lost. It runs only when the owner asks, on text already pasted, never on the 1 s path.
public protocol TextPolisher: Sendable {
    /// Throws `ProviderError`, like `TextCleaner.clean`. An answer that did not end on its own comes back with
    /// `isComplete` off, with its cost, so the pipeline books it and pastes nothing.
    func polish(_ text: String) async throws -> PolishedText
}

public struct PolishedText: Sendable, Equatable {
    public var text: String
    /// The model identifier that answered.
    public var model: String
    /// The reported cost, else an estimate from the model's list price; nil when neither is known.
    public var cost: Cost?
    /// The model ended the text itself (`finish_reason` "stop"); false when the answer was cut at the token limit or
    /// filtered, so the text is partial.
    public var isComplete: Bool

    public init(text: String, model: String, cost: Cost?, isComplete: Bool = true) {
        self.text = text
        self.model = model
        self.cost = cost
        self.isComplete = isComplete
    }
}

/// Finds text kotoba pasted in the focused field and selects it, so the next ⌘V replaces it (Polish and its Undo).
public protocol PastedTextSelector: Sendable {
    /// Selects `text` when the focused field is an editable field of `app` (nil: any app) that holds it exactly once,
    /// and returns true once the selection is exactly `text`. False leaves the field as it was: no readable field (a
    /// terminal), another app, a secure field, or text the owner changed.
    func select(_ text: String, in app: DictationApp?) async -> Bool
}

/// Why Polish pasted nothing.
public enum PolishFailure: Sendable, Equatable {
    /// No dictation reached the owner yet.
    case nothingToPolish
    /// The answer did not end on its own (`PolishedText.isComplete`).
    case cutOff
    /// No answer within `Settings.polishDeadline`.
    case tooSlow
    /// OpenRouter needs a key, or credit.
    case needsSetup(SetupItem)
    /// No network, a server error, a refusal, or an answer with no words.
    case failed
}
