import AppKit
import KotobaCore
import SwiftUI

extension FixLastDictationController {
    /// The window before Learn, after Learn with a strong and a weak word, with more words than fit, with nothing
    /// found, with no dictation, before the dictionary is loaded, and opened from a History row with a word selected
    /// and then added.
    static func snapshots() -> [Snapshot] {
        let pasted = "Deploy the ember branch to versel, then add it the change and tell the team."
        let fixed = "Deploy the embra branch to Vercel, then audit the change and tell the team."
        return [
            windowSnapshot(named: "fix-last-dictation") {
                let model = FixLastDictationModel(pasted: pasted, learner: sampleLearner) { _ in }
                model.text = fixed
                return model
            },
            windowSnapshot(named: "fix-last-dictation-learned") {
                let model = FixLastDictationModel(pasted: pasted, learner: sampleLearner) { _ in }
                model.text = fixed
                model.learn()
                return model
            },
            // More words than fit: the window stops at its tallest and the form scrolls. Each name is one changed word
            // in a sentence, so the edit stays a fix, not a rewrite.
            windowSnapshot(named: "fix-last-dictation-many") {
                let names = ["Zentyl", "Korvex", "Plinth", "Quorra", "Vantor", "Brisko", "Celdra", "Dunmar", "Fyrnel"]
                let sentence = { (name: String) in "Ship \(name) to the team today." }
                let model = FixLastDictationModel(
                    pasted: names.map { sentence(String($0.dropLast())) }.joined(separator: " "),
                    learner: sampleLearner
                ) { _ in }
                model.text = names.map(sentence).joined(separator: " ")
                model.learn()
                return model
            },
            windowSnapshot(named: "fix-last-dictation-none-found") {
                let model = FixLastDictationModel(pasted: pasted, learner: sampleLearner) { _ in }
                model.text = pasted.replacingOccurrences(of: "then", with: "and then")
                model.learn()
                return model
            },
            windowSnapshot(named: "fix-last-dictation-empty") {
                FixLastDictationModel(pasted: nil, learner: sampleLearner) { _ in }
            },
            windowSnapshot(named: "fix-last-dictation-no-dictionary") {
                let model = FixLastDictationModel(pasted: pasted, learner: nil) { _ in }
                model.text = fixed
                return model
            },
            Snapshots.fittedWindow(named: "fix-dictation-window") {
                window(showing: rowModel(isAdded: false), title: "Fix Dictation") {}
            },
            windowSnapshot(named: "fix-dictation-word-added") { rowModel(isAdded: true) },
        ]
    }

    /// A History row's text that the dictation got right, with a selection inside one word.
    private static func rowModel(isAdded: Bool) -> FixLastDictationModel {
        let text = "Ship the Zentyl landing page after the design review."
        let model = FixLastDictationModel(pasted: text, learner: sampleLearner) { _ in }
        if let word = text.range(of: "enty") {
            model.selection = TextSelection(range: word)
        }
        if isAdded { model.addSelectedWord() }
        return model
    }

    /// A fixed word list instead of the spell checker, so the images do not depend on this Mac's learned words, and
    /// a dictionary of the snapshot's own.
    private static var sampleLearner: FixLastDictationModel.Learner {
        let known: Set<String> = ["ember", "add", "it", "audit"]
        let dictionary = SampleDictionary()
        return FixLastDictationModel.Learner(
            dictionary: { dictionary.entries }, dismissed: [], isKnownWord: { known.contains($0.lowercased()) },
            add: { dictionary.entries = $0.reduce(dictionary.entries) { $0.adding($1) } }, record: { _ in },
            dismiss: { _ in })
    }

    /// What `DictionaryModel` holds in the app.
    @MainActor
    private final class SampleDictionary {
        var entries = PersonalDictionary()
    }

    /// The window at the size its content takes, with the shared fit check.
    private static func windowSnapshot(named name: String, model: @escaping @MainActor () -> FixLastDictationModel)
        -> Snapshot
    {
        Snapshots.fittedWindow(named: name) { window(showing: model(), title: "Fix Last Dictation") {} }
    }
}
