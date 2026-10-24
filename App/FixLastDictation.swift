// 0.5.0 ratchet: the Fix Last Dictation window's rollout puts this file on the page system and removes the next line.
// swiftlint:disable ui_layout_literal ui_layout_constant page_form
import AppKit
import KotobaCore
import Observation
import SwiftUI

/// "Fix Last Dictation…" and a History row's "Fix Dictation…": the owner corrects a dictation's text, kotoba finds the
/// words worth learning in the edit, and the owner picks which to add (story 32, docs/research/auto-learning.md 3d).
/// "Add Selected Word" adds a word the dictation got right. The fixed text goes to the clipboard; it is not pasted
/// again, since the focus has moved. Built when it opens and released when it closes. Readback (`EditReadback`)
/// learns from edits in apps whose text Accessibility can read; this window is the way for the others, such as
/// terminals.
@MainActor
final class FixLastDictationController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 480
    /// The tallest the form gets; past it the form scrolls. Below it the window is as tall as its content, so it
    /// grows when Learn adds the words it found.
    static let maxFormHeight: CGFloat = 440

    /// Which dictation the open window fixes.
    private enum Fixing {
        /// The menu's last dictation, read when the window opened; nil when there was none.
        case last(DictationID?)
        case row(DictationID)

        var id: DictationID? {
            switch self {
            case .last(let id): id
            case .row(let id): id
            }
        }

        var title: String {
            switch self {
            case .last: "Fix Last Dictation"
            case .row: "Fix Dictation"
            }
        }
    }

    /// The dictation kotoba delivered last, or nil when there is none.
    private let last: @MainActor () async -> DictationRecord?
    /// Nil until the dictionary is read at launch; the window then learns nothing but still copies.
    private let dictionary: @MainActor () -> DictionaryModel?
    /// Leaves the fixed text on the clipboard through the pipeline (`DictationPipeline.copyAgain`), so a paste that
    /// waits for its restore does not put the owner's old clipboard back over it.
    private let copy: @MainActor (String) async -> Void
    private var window: NSWindow?
    private var fixing: Fixing?
    /// Set while the last dictation loads, so a second click does not build a second window.
    private var opening: Task<Void, Never>?

    init(
        last: @escaping @MainActor () async -> DictationRecord?,
        dictionary: @escaping @MainActor () -> DictionaryModel?,
        copy: @escaping @MainActor (String) async -> Void
    ) {
        self.last = last
        self.dictionary = dictionary
        self.copy = copy
    }

    /// Shows the window with the last dictation. An open window keeps the owner's edit.
    func show() {
        WindowFront.activate()
        if window != nil, case .last = fixing {
            present()
            return
        }
        guard opening == nil else { return }
        opening = Task {
            let record = await last()
            // A History row opened the window while the last dictation loaded.
            guard !Task.isCancelled else { return }
            opening = nil
            open(.last(record?.id), text: record?.deliveredText)
        }
    }

    /// Shows the window with one History row's text. An open window for the same dictation keeps the owner's edit;
    /// another dictation takes its place.
    func show(_ record: DictationRecord) {
        WindowFront.activate()
        opening?.cancel()
        opening = nil
        if window != nil, fixing?.id == record.id {
            present()
            return
        }
        open(.row(record.id), text: record.deliveredText)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        fixing = nil
    }

    private func open(_ fixing: Fixing, text: String?) {
        window?.close()
        let model = FixLastDictationModel(
            pasted: text, learner: dictionary().map(FixLastDictationModel.Learner.live), copy: copy)
        let window = Self.window(showing: model, title: fixing.title) { [weak self] in self?.window?.close() }
        window.delegate = self
        // Centred at its tallest (`FixLastDictationView` starts there); the content then sets the height, and the top
        // edge stays as the window shrinks or grows.
        window.center()
        self.window = window
        self.fixing = fixing
        present()
    }

    private func present() {
        guard let window else { return }
        WindowFront.show(window)
    }

    /// The window and its content; the snapshot run draws the same window.
    static func window(showing model: FixLastDictationModel, title: String, close: @escaping () -> Void) -> NSWindow {
        let view = FixLastDictationView(model: model, close: close)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }
}

/// The edit, and what Learn found in it.
@MainActor
@Observable
final class FixLastDictationModel {
    /// What the window needs from the dictionary.
    struct Learner {
        /// Read at each use, so a word added while the window is open counts.
        var dictionary: @MainActor () -> PersonalDictionary
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
                dictionary: { model.dictionary }, dismissed: model.dismissedPairs,
                isKnownWord: DictionaryModel.isKnownWord,
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
    /// The editor's selection, for "Add Selected Word".
    var selection: TextSelection?
    /// The words "Add Selected Word" added, in click order, for the footer.
    private(set) var addedWords: [String] = []
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

    /// The selection widened to whole words, when that is a word the dictionary does not have yet.
    var selectedWord: SuggestionCandidate? {
        guard let learner, case .selection(let range) = selection?.indices,
            let candidate = CorrectionDetector.selectedWord(in: text, range: range),
            !learner.dictionary().contains(candidate)
        else { return nil }
        return candidate
    }

    /// Adds the selected word as it is: the dictation got it right, and the next one should too.
    func addSelectedWord() {
        guard let candidate = selectedWord, let learner else { return }
        learner.add([candidate])
        addedWords.append(candidate.corrected)
    }

    /// Strong corrections start checked; weak ones (known words on both sides) wait for the owner's click.
    func learn() {
        guard let pasted, let learner else { return }
        let found = CorrectionDetector.corrections(
            pasted: pasted, observed: text, dictionary: learner.dictionary(), dismissed: learner.dismissed,
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
    // Starts at the tallest, so the window opens at its tallest frame and only shrinks to the measured height.
    @State private var formHeight = FixLastDictationController.maxFormHeight

    var body: some View {
        VStack(spacing: 0) {
            if model.pasted == nil {
                empty
            } else {
                Form {
                    Section {
                        TextEditor(text: $model.text, selection: $model.selection)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 100)
                    } footer: {
                        footer
                    }
                    if let corrections = model.corrections {
                        found(corrections)
                    }
                }
                .formStyle(.grouped)
                // A form takes all the height it is offered; this gives it its content's, so the window (sized by its
                // content) has no empty half and grows when Learn adds words.
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, height in
                    formHeight = height
                }
                .frame(height: min(formHeight, FixLastDictationController.maxFormHeight))
                buttons
                    .padding([.horizontal, .bottom], 20)
            }
        }
        .frame(width: FixLastDictationController.width)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.canLearn {
                Text(
                    "Fix the wrong words, then click Learn. To add a word that is right, select it and click Add "
                        + "Selected Word.")
            } else {
                Text("Fix the wrong words, then click Copy.")
            }
            if !model.addedWords.isEmpty {
                Label(
                    "Added \(model.addedWords.map { "“\($0)”" }.formatted(.list(type: .and))) to your dictionary.",
                    systemImage: "checkmark.circle")
            }
        }
    }

    private var empty: some View {
        VStack {
            EmptyState(
                "No Dictation to Fix Yet", systemImage: "text.badge.checkmark",
                description: "Dictate something, then open this window again.")
            HStack {
                Spacer()
                Button("Close", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        // As tall as the message and the button: the window fits its content.
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func found(_ corrections: [DetectedCorrection]) -> some View {
        if corrections.isEmpty {
            Section {
                Text("No new words found. Copy puts the fixed text on the clipboard.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Section("Words to Add") {
                ForEach(corrections, id: \.candidate.pair) { correction in
                    Toggle(isOn: binding(for: correction.candidate.pair)) {
                        SuggestionCandidateLabel(candidate: correction.candidate)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var buttons: some View {
        HStack {
            if model.canLearn {
                AddSelectedWordButton(model: model)
            }
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

/// Its own view: it reads the selection, which changes at each caret move, so only the button draws again.
private struct AddSelectedWordButton: View {
    let model: FixLastDictationModel

    var body: some View {
        Button("Add Selected Word", action: model.addSelectedWord)
            .disabled(model.selectedWord == nil)
    }
}
