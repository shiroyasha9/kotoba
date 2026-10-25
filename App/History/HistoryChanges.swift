import KotobaCore
import SwiftUI

/// History's View Changes (docs/spec.md, "Polish and View Changes"): the word-level change between two texts of one
/// dictation, what was heard, the cleaned text and the rewritten text, in a page sheet. Removed words are struck through
/// and added words underlined, each in its color too, so the change never rests on color alone; VoiceOver reads them as
/// “removed” and “added”.
struct ChangesView: View {
    let record: DictationRecord
    @State private var comparison: Comparison
    @State private var diffs = Diffs()

    /// A row with no second text has nothing to show; History offers the sheet only when one comparison exists.
    init?(record: DictationRecord) {
        let comparisons = Comparison.all(of: record)
        guard let latest = comparisons.last else { return nil }
        self.record = record
        _comparison = State(initialValue: latest)
    }

    var body: some View {
        let runs = diffs.runs(of: comparison, in: record)
        PageSheet(title: "Changes") {
            Section {
                Text(Self.marked(runs))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Self.spoken(runs))
            } header: {
                let comparisons = Comparison.all(of: record)
                if comparisons.count > 1 {
                    // A pop-up, not a segmented control: three "Cleaned Up → Rewritten" segments are wider than the
                    // sheet.
                    Picker("Compare", selection: $comparison) {
                        ForEach(comparisons, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                } else {
                    Text(comparison.title)
                }
            } footer: {
                Text(Self.summary(runs))
            }
        }
    }

    /// One of the texts a dictation can have.
    enum Version: Hashable {
        case transcript
        case cleaned
        case polished

        var title: String {
            switch self {
            case .transcript: "Original"
            case .cleaned: "Cleaned Up"
            case .polished: "Rewritten"
            }
        }

        func text(of record: DictationRecord) -> String {
            switch self {
            case .transcript: record.transcript ?? ""
            case .cleaned: record.cleanedText ?? ""
            case .polished: record.polishedText ?? ""
            }
        }
    }

    struct Comparison: Hashable {
        var from: Version
        var to: Version

        var title: String { "\(from.title) → \(to.title)" }

        /// The pairs the row has, the latest change last.
        static func all(of record: DictationRecord) -> [Self] {
            let hasCleaned = record.cleanedText != nil
            let hasPolished = record.polishedText != nil
            return [
                hasCleaned ? Self(from: .transcript, to: .cleaned) : nil,
                hasPolished ? Self(from: .transcript, to: .polished) : nil,
                hasCleaned && hasPolished ? Self(from: .cleaned, to: .polished) : nil,
            ].compactMap(\.self)
        }
    }

    /// Removed words struck through in red, added words underlined in green; the spacing after them stays plain. The
    /// two colors (asset catalog, light and dark) read at 4.5:1 or more on the text background in both modes.
    /// A word put in place of a struck one with no space between them ("friday" → "Friday." at a sentence end) gets one,
    /// so the two do not read as one word (qa1-review, History).
    static func marked(_ runs: [WordDiff.Run]) -> AttributedString {
        zip([nil] + runs.map(\.kind), runs).reduce(into: AttributedString()) { text, pair in
            let (previous, run) = pair
            if previous == .removed, run.kind == .added, text.characters.last?.isWhitespace == false {
                text += AttributedString(" ")
            }
            let end = run.text.lastIndex { !$0.isWhitespace }.map(run.text.index(after:)) ?? run.text.startIndex
            var words = AttributedString(run.text[..<end])
            switch run.kind {
            case .kept:
                break
            case .removed:
                words.foregroundColor = Color(.diffRemoved)
                words.strikethroughStyle = .single
            case .added:
                words.foregroundColor = Color(.diffAdded)
                words.underlineStyle = .single
            }
            text += words + AttributedString(run.text[end...])
        }
    }

    /// The change as VoiceOver reads it: “Look at, removed: the the, added: the, webhook handler”.
    static func spoken(_ runs: [WordDiff.Run]) -> String {
        runs.map { run in
            let words = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return switch run.kind {
            case .kept: words
            case .removed: "removed: \(words)"
            case .added: "added: \(words)"
            }
        }
        .joined(separator: ", ")
    }

    /// “12 words removed, 3 added”, a zero count left out, or “No changes”.
    static func summary(_ runs: [WordDiff.Run]) -> String {
        let removed = runs.filter { $0.kind == .removed }.map(\.words).reduce(0, +)
        let added = runs.filter { $0.kind == .added }.map(\.words).reduce(0, +)
        switch (removed, added) {
        case (0, 0): return "No changes"
        case (_, 0): return "\(StatusText.counted(removed, "word")) removed"
        case (0, _): return "\(StatusText.counted(added, "word")) added"
        default: return "\(StatusText.counted(removed, "word")) removed, \(added) added"
        }
    }

    /// Each comparison's diff, made once when the sheet first shows it: the body runs again on each appearance or
    /// picker change, and a 900-word diff takes about 6 ms.
    final class Diffs {
        private var runs: [Comparison: [WordDiff.Run]] = [:]

        func runs(of comparison: Comparison, in record: DictationRecord) -> [WordDiff.Run] {
            if let made = runs[comparison] { return made }
            let made = WordDiff.runs(from: comparison.from.text(of: record), to: comparison.to.text(of: record))
            runs[comparison] = made
            return made
        }
    }
}

// MARK: - Snapshots

extension ChangesView {
    /// A cleaned and rewritten row (three comparisons, on the latest), and a row with only a cleanup.
    @MainActor
    static func snapshots() -> [Snapshot] {
        let rows = HistoryController.sampleRows()
        let polished = HistoryController.samplePolished()
        let samples = [("history-changes-rewritten", polished), ("history-changes-cleaned", rows[1])]
        return samples.compactMap { name, record in
            ChangesView(record: record).map { view in
                MainWindow.sheetSnapshot(named: name) { view }
            }
        }
    }
}
