import Foundation

/// Spoken line breaks (owner, 2026-10-17), off by default: "new line" (also "newline", "new-line") becomes a line
/// break and "new paragraph" an empty line. The phrase counts as a command where it stands as words of its own, with
/// three exceptions that keep it text: right after a determiner ("add a new line", "the newline character"), right
/// before "of" ("new line of products"), and next to a quote mark ("say “new line”", "new line's"). Plain words in
/// the middle of a sentence ("insert new line here") are a command too; no rule can tell them apart.
///
/// The text before the command keeps its punctuation ("Dear Bob," stays); the spaces before the break, and the
/// spaces and the punctuation the speech model put after the command, go. When the transcript is sentence-cased, the
/// word after a break gets a capital letter, unless it already has one ("iPhone" stays) or the app is in Code mode. The text never starts or ends
/// with a break, so a last "new line" never reaches a terminal as Enter; a command alone ("New line.") stays text, as
/// a submit phrase alone does.
enum LineBreakPhrase {
    /// The phrase as a whole word, in any case; `isCommand(_:in:)` decides each match.
    private static let pattern = #"(?<![\p{L}\p{N}])new(?:[ -]?line|[ -]paragraph)(?![\p{L}\p{N}])"#

    /// Compiled once, at the first dictation with the setting on: that first call takes 2-3 ms, a later one about 3 µs
    /// for 50 words with no command and 40 µs with four (release build). Compiled on each call, it took 3.8 ms.
    private static let regex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            Log.pipeline.error("The line break pattern did not compile, transcripts are left as is: \(error)")
            return nil
        }
    }()

    /// A word right before the phrase that makes it a noun ("a new line"), not a command.
    private static let determiners: Set<String> = [
        "a", "an", "the", "this", "that", "each", "every", "another", "any", "some", "no",
        "my", "your", "our", "their", "his", "her", "its",
    ]

    private static let quotes: Set<Character> = ["\"", "'", "“", "”", "‘", "’"]

    /// Left out after the command: "New line. Second point" is "\nSecond point".
    private static let droppedAfter: Set<Character> = [".", ",", ";", ":", "!", "?", "…"]

    /// `text` with each command as its line breaks. `capitalizes` is false for an app in Code mode (lead, 2026-10-17):
    /// a terminal or an editor takes the next word as said ("npm install", not "Npm install").
    static func apply(to text: String, capitalizes: Bool) -> String {
        guard let regex else { return text }
        let isSentenceCased = capitalizes && text.first(where: \.isLetter)?.isUppercase == true
        var result = ""
        var cursor = text.startIndex
        var hasBreak = false
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), range.lowerBound >= cursor, isCommand(range, in: text)
            else { continue }
            let head = text[cursor..<range.lowerBound]
            result += startingLine(head, capitalized: hasBreak && isSentenceCased)
            while result.last?.isWhitespace == true, result.last?.isNewline == false { result.removeLast() }
            result += text[range].lowercased().hasSuffix("paragraph") ? "\n\n" : "\n"
            cursor =
                text[range.upperBound...].firstIndex { !$0.isWhitespace && !droppedAfter.contains($0) }
                ?? text.endIndex
            hasBreak = true
        }
        guard hasBreak else { return text }
        result += startingLine(text[cursor...], capitalized: isSentenceCased)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains { $0.isLetter || $0.isNumber } ? trimmed : text
    }

    /// The phrase at `range` is a command: no determiner before it, no "of" after it, no quote mark next to it.
    private static func isCommand(_ range: Range<String.Index>, in text: String) -> Bool {
        if range.lowerBound > text.startIndex, quotes.contains(text[text.index(before: range.lowerBound)]) {
            return false
        }
        if range.upperBound < text.endIndex, quotes.contains(text[range.upperBound]) { return false }
        let before = text[..<range.lowerBound].reversed().drop { $0 == " " }.prefix { $0.isLetter }
        if determiners.contains(String(before.reversed()).lowercased()) { return false }
        let after = text[range.upperBound...].drop { $0 == " " }.prefix { $0.isLetter }
        return after.lowercased() != "of"
    }

    /// `line` with a capital first letter when `capitalized` and its first word is all lower case.
    private static func startingLine(_ line: Substring, capitalized: Bool) -> String {
        guard capitalized, let first = line.first, first.isLowercase,
            !line.prefix(while: \.isLetter).contains(where: \.isUppercase)
        else { return String(line) }
        return first.uppercased() + line.dropFirst()
    }
}
