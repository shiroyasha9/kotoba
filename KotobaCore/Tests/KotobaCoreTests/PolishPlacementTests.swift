import Testing

@testable import KotobaCore

/// How Polish puts its text in place of the old one: over a selection, after Backspaces only while nothing can have
/// changed since kotoba's paste, else on the clipboard.
struct PolishPlacementTests {
    static let mark = InputMark(processID: 100, window: 7, inputSincePaste: 0)
    static let paste = LastPaste(text: "Fix the login bug.", mark: mark)

    struct Row: Sendable, CustomTestStringConvertible {
        let name: String
        var old = "Fix the login bug."
        var selection = SelectionResult.untouched
        var lastPaste: LastPaste? = PolishPlacementTests.paste
        var now: InputMark? = PolishPlacementTests.mark
        let placement: PolishPlacement

        var testDescription: String { name }
    }

    static let rows: [Row] = [
        Row(name: "a selection wins", selection: .selected, lastPaste: nil, placement: .overSelection),
        Row(name: "a selection the selector changed and lost", selection: .changed, placement: .clipboard),
        Row(name: "nothing changed: one Backspace per character", placement: .backspaces(18)),
        Row(
            name: "a key or a click since the paste",
            now: InputMark(processID: 100, window: 7, inputSincePaste: 1), placement: .clipboard),
        Row(
            name: "another window", now: InputMark(processID: 100, window: 8, inputSincePaste: 0), placement: .clipboard
        ),
        Row(name: "another app", now: InputMark(processID: 101, window: 7, inputSincePaste: 0), placement: .clipboard),
        Row(name: "the window is not known", now: nil, placement: .clipboard),
        Row(name: "no paste since launch or a Return submitted it", lastPaste: nil, placement: .clipboard),
        Row(name: "the last paste was another text", old: "Ship it.", placement: .clipboard),
        Row(
            name: "longer than Claude Code shows as typed",
            old: String(repeating: "a", count: 801),
            lastPaste: LastPaste(text: String(repeating: "a", count: 801), mark: mark), placement: .clipboard),
        Row(
            name: "three lines", old: "one\ntwo\nthree",
            lastPaste: LastPaste(text: "one\ntwo\nthree", mark: mark), placement: .clipboard),
        Row(
            name: "two lines", old: "one\ntwo", lastPaste: LastPaste(text: "one\ntwo", mark: mark),
            placement: .backspaces(7)),
        Row(
            name: "a character of two scalars (an emoji with a skin tone)", old: "ok 👍🏽",
            lastPaste: LastPaste(text: "ok 👍🏽", mark: mark), placement: .clipboard),
        Row(
            name: "a character of two UTF-16 units", old: "ok 😀", lastPaste: LastPaste(text: "ok 😀", mark: mark),
            placement: .clipboard),
        Row(
            name: "an accented letter is one unit", old: "café", lastPaste: LastPaste(text: "café", mark: mark),
            placement: .backspaces(4)),
    ]

    @Test(arguments: rows)
    func placement(_ row: Row) {
        #expect(
            PolishPlacement.choose(
                replacing: row.old, selection: row.selection, lastPaste: row.lastPaste, now: row.now)
                == row.placement)
    }
}
