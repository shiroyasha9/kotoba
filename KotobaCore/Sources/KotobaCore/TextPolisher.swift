import Foundation

/// Polish (docs/spec.md, "Polish and View Changes"): an LLM rewrite of the last dictation, shorter and clearer with
/// nothing lost. It runs only when the owner asks, on text already pasted, never on the 1 s path.
public protocol TextPolisher: Sendable {
    /// Throws `ProviderError`, like `TextCleaner.clean`. An answer that did not end on its own comes back with
    /// `isComplete` off, with its cost, so the pipeline books it and pastes nothing.
    func polish(_ text: String) async throws -> RewrittenText
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
    /// The answer did not end on its own (`RewrittenText.isComplete`).
    case cutOff
    /// No answer within `Settings.polishDeadline`.
    case tooSlow
    /// OpenRouter needs a key, or credit.
    case needsSetup(SetupItem)
    /// No network, a server error, a refusal, or an answer with no words.
    case failed
}

/// Where the owner works and what they did there since kotoba's last ⌘V: the front app and window, and the key-downs
/// that reached an app and the clicks in other apps, counted where the event stream put them. kotoba's own posted keys
/// and the chords it swallows do not count.
public struct InputMark: Sendable, Equatable {
    public var processID: Int32
    /// The window server's number of the app's front window.
    public var window: Int
    public var inputSincePaste: UInt64

    public init(processID: Int32, window: Int, inputSincePaste: UInt64) {
        self.processID = processID
        self.window = window
        self.inputSincePaste = inputSincePaste
    }
}

/// The last text kotoba pasted, and where the owner was then.
struct LastPaste: Sendable {
    var text: String
    var mark: InputMark
}

/// How Polish (and its Undo) puts a text in place of the old one (docs/spec.md, "Polish and View Changes").
enum PolishPlacement: Equatable {
    /// The selector selected the old text: ⌘V replaces it.
    case overSelection
    /// Backspace this many times, then ⌘V.
    case backspaces(Int)
    /// Nothing is pasted; the new text goes to the clipboard.
    case clipboard

    /// Claude Code shows a paste of over 800 characters or 3 lines as one “[Pasted text #N +M lines]” item (its issue
    /// 85453), so a Backspace per character would delete past it, into the owner's own text. Longer texts go to the
    /// clipboard.
    static let maxCharacters = 800
    static let maxLines = 2

    /// Backspace only where nothing can have moved the insertion point or changed the text since kotoba pasted `old`:
    /// `old` is that paste, the same app and window are in front, and no key went to an app and no click happened
    /// since. Each character must be one UTF-16 unit, so an app that deletes a character, a scalar or a JavaScript
    /// string unit per Backspace agrees on the count.
    static func choose(replacing old: String, isSelected: Bool, lastPaste: LastPaste?, now: InputMark?) -> Self {
        if isSelected { return .overSelection }
        guard let lastPaste, lastPaste.text == old, let now, now.inputSincePaste == 0,
            now.processID == lastPaste.mark.processID, now.window == lastPaste.mark.window, !old.isEmpty,
            old.count <= maxCharacters, old.split(separator: "\n", omittingEmptySubsequences: false).count <= maxLines,
            old.utf16.count == old.count
        else { return .clipboard }
        return .backspaces(old.count)
    }
}
