import AppKit
import KotobaCore
import Observation
import SwiftUI

/// "Fix Last Dictation…": the owner corrects the last dictation's text, kotoba finds the words worth learning in the
/// edit, and the owner picks which to add (story 32, docs/research/auto-learning.md 3d). The fixed text goes to the
/// clipboard; it is not pasted again, since the focus has moved. Built when it opens and released when it closes.
@MainActor
final class FixLastDictationController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 480, height: 400)

    /// The text kotoba delivered last (the cleaned text for a cleanup dictation), or nil when there is none.
    private let lastText: @MainActor () async -> String?
    /// Nil until the dictionary is read at launch; the window then learns nothing but still copies.
    private let dictionary: @MainActor () -> DictionaryModel?
    private let pasteboard = SystemPasteboard()
    private var window: NSWindow?
    /// Set while the last text loads, so a second click does not build a second window.
    private var opening: Task<Void, Never>?

    init(
        lastText: @escaping @MainActor () async -> String?,
        dictionary: @escaping @MainActor () -> DictionaryModel?
    ) {
        self.lastText = lastText
        self.dictionary = dictionary
    }

    /// Shows the window with the last dictation. An open window keeps the owner's edit.
    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard opening == nil else { return }
        opening = Task {
            let text = await lastText()
            let model = FixLastDictationModel(
                pasted: text, learner: dictionary().map(FixLastDictationModel.Learner.live)
            ) { [pasteboard] in _ = await pasteboard.write($0, isTransient: false) }
            let window = makeWindow(model: model)
            self.window = window
            opening = nil
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow(model: FixLastDictationModel) -> NSWindow {
        let view = FixLastDictationView(model: model) { [weak self] in self?.window?.close() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Fix Last Dictation"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(Self.size)
        window.delegate = self
        window.center()
        return window
    }
}

/// The edit, and what Learn found in it.
@MainActor
@Observable
final class FixLastDictationModel {
    /// What the window needs from the dictionary.
    struct Learner {
        var dictionary: PersonalDictionary
        var dismissed: Set<SuggestionPair>
        var isKnownWord: @MainActor (String) -> Bool
        var add: @MainActor ([SuggestionCandidate]) -> Void
        /// Unchecked weak corrections become pending suggestions; the store shows them from the second sighting.
        var record: @MainActor ([DetectedCorrection]) -> Void
        /// Unchecked strong corrections: the owner said no, so they never come back.
        var dismiss: @MainActor ([SuggestionCandidate]) -> Void

        @MainActor
        static func live(_ model: DictionaryModel) -> Self {
            Self(
                dictionary: model.dictionary, dismissed: model.dismissedPairs, isKnownWord: DictionaryModel.isKnownWord,
                add: { model.add($0) }, record: { model.record($0) }, dismiss: { model.dismiss($0) })
        }
    }

    /// Nil when there is no dictation to fix.
    let pasted: String?
    var text: String {
        didSet {
            if text != oldValue { corrections = nil }
        }
    }
    /// Nil until Learn; an edit after Learn clears it, so the list always matches the text.
    private(set) var corrections: [DetectedCorrection]?
    var checked: Set<SuggestionPair> = []
    /// Nil while the dictionary is not loaded: the window then only copies the fixed text.
    @ObservationIgnored private let learner: Learner?
    @ObservationIgnored private let copy: @MainActor (String) async -> Void

    init(pasted: String?, learner: Learner?, copy: @escaping @MainActor (String) async -> Void) {
        self.pasted = pasted
        self.text = pasted ?? ""
        self.learner = learner
        self.copy = copy
    }

    var canLearn: Bool {
        learner != nil
    }

    var isEdited: Bool {
        pasted != nil && text != pasted
    }

    /// Strong corrections start checked; weak ones (known words on both sides) wait for the owner's click.
    func learn() {
        guard let pasted, let learner else { return }
        let found = CorrectionDetector.corrections(
            pasted: pasted, observed: text, dictionary: learner.dictionary, dismissed: learner.dismissed,
            origin: .fix, isKnownWord: { learner.isKnownWord($0) })
        corrections = found
        checked = Set(found.filter(\.isStrong).map(\.candidate.pair))
    }

    /// Applies the owner's checkboxes (`FixChoice`) and puts the fixed text on the clipboard.
    func addAndCopy() async {
        if let learner {
            let choice = FixChoice(corrections: corrections ?? [], checked: checked)
            if !choice.add.isEmpty { learner.add(choice.add) }
            if !choice.suggest.isEmpty { learner.record(choice.suggest) }
            if !choice.dismiss.isEmpty { learner.dismiss(choice.dismiss) }
        }
        await copy(text)
    }
}

struct FixLastDictationView: View {
    @Bindable var model: FixLastDictationModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.pasted == nil {
                empty
            } else {
                Text("Correct the words kotoba got wrong, then click \(model.canLearn ? "Learn" : "Copy").")
                    .foregroundStyle(.secondary)
                TextEditor(text: $model.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    .frame(minHeight: 100)
                if let corrections = model.corrections {
                    found(corrections)
                }
                buttons
            }
        }
        .padding(20)
        .frame(width: FixLastDictationController.size.width, height: FixLastDictationController.size.height)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No Dictation to Fix Yet").font(.headline)
            Text("Dictate something, then open this window again.")
                .foregroundStyle(.secondary)
            Spacer()
            HStack {
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func found(_ corrections: [DetectedCorrection]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if corrections.isEmpty {
                Text("No new words found. Copy puts the fixed text on the clipboard.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Words to Add").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(corrections, id: \.candidate.pair) { correction in
                            Toggle(isOn: binding(for: correction.candidate.pair)) {
                                SuggestionCandidateLabel(candidate: correction.candidate)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            if model.canLearn && model.corrections == nil {
                Button("Learn", action: model.learn)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isEdited)
            } else {
                Button(model.checked.isEmpty ? "Copy" : "Add and Copy") {
                    Task {
                        await model.addAndCopy()
                        close()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func binding(for pair: SuggestionPair) -> Binding<Bool> {
        Binding {
            model.checked.contains(pair)
        } set: { isOn in
            if isOn { model.checked.insert(pair) } else { model.checked.remove(pair) }
        }
    }
}

// MARK: - Snapshots

extension FixLastDictationController {
    /// The window before Learn, after Learn with a strong and a weak word, with nothing found, with no dictation, and
    /// before the dictionary is loaded.
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
        ]
    }

    /// A fixed word list instead of the spell checker, so the images do not depend on this Mac's learned words.
    private static var sampleLearner: FixLastDictationModel.Learner {
        let known: Set<String> = ["ember", "add", "it", "audit"]
        return FixLastDictationModel.Learner(
            dictionary: PersonalDictionary(), dismissed: [], isKnownWord: { known.contains($0.lowercased()) },
            add: { _ in }, record: { _ in }, dismiss: { _ in })
    }

    /// The window at its fixed size, with the shared fit check.
    private static func windowSnapshot(named name: String, model: @escaping @MainActor () -> FixLastDictationModel)
        -> Snapshot
    {
        Snapshots.fixedWindow(named: name, size: size) { FixLastDictationView(model: model()) {} }
    }
}
