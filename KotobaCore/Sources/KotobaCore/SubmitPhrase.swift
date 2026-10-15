/// Submit after paste (docs/research/beyond-wispr.md, idea 3): a transcript that ends with a spoken submit phrase
/// is pasted without it, and Return follows the paste. The phrase counts only as the last words, after other text:
/// a phrase alone ("Press enter.") is pasted as text, because a Return with nothing pasted saves no key press.
/// Aqua's "send it" is left out: "Looks good, send it." in a chat would lose words and send the message.
enum SubmitPhrase {
    /// Wispr's "press enter", plus the Mac name of the key.
    private static let phrases = [["press", "enter"], ["press", "return"]]

    /// Left at the end of the text once the phrase is removed: "Fix it, press enter" pastes "Fix it".
    private static let trailingJoiners: Set<Character> = [",", ";", ":", "-", "–", "—"]

    /// `text` without its trailing submit phrase, and whether it had one.
    static func split(_ text: String) -> (text: String, submits: Bool) {
        for phrase in phrases {
            if let head = head(of: text[...], before: phrase) {
                return (String(head), true)
            }
        }
        return (text, false)
    }

    /// The text before `phrase` when `text` ends with it (case and trailing punctuation aside), else nil.
    private static func head(of text: Substring, before phrase: [String]) -> Substring? {
        var rest = dropping(from: text) { !isWordCharacter($0) }
        for (index, word) in phrase.enumerated().reversed() {
            guard rest.suffix(word.count).lowercased() == word else { return nil }
            rest = rest.dropLast(word.count)
            if index > 0 {
                let separated = dropping(from: rest) { !isWordCharacter($0) }
                guard separated.count < rest.count else { return nil }
                rest = separated
            }
        }
        // A whole word: "express return" is not the phrase.
        if let last = rest.last, isWordCharacter(last) { return nil }
        let head = dropping(from: rest) { $0.isWhitespace || trailingJoiners.contains($0) }
        return head.contains(where: isWordCharacter) ? head : nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    /// `text` without the characters at its end that match `predicate`.
    private static func dropping(from text: Substring, while predicate: (Character) -> Bool) -> Substring {
        var end = text.endIndex
        while end > text.startIndex, predicate(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        return text[text.startIndex..<end]
    }
}
