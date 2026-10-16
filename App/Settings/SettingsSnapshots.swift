import AppKit
import KotobaCore
import KotobaStorage

/// Sample data for the Settings snapshots, and the whole main window on each pane (`make snapshots`). Samples never touch
/// the owner's files, Keychain or devices.
@MainActor
extension Pane {
    /// The whole main window: Home, History, and each settings pane, the Dictionary pane also with suggestions. History
    /// also in the framed window, for its toolbar with a selected row: one with text (Copy, Paste Again and Delete on),
    /// a failed one (Retry and Delete on) and one with no audio (Delete on only). Usage framed for its period switch in
    /// the toolbar.
    static func windowSnapshots() -> [Snapshot] {
        [
            windowSnapshot(selecting: .home, named: "window-home"),
            windowSnapshot(selecting: .history, named: "window-history"),
            windowSnapshot(selecting: .history, named: "window-history-toolbar", isFramed: true),
            windowSnapshot(selecting: .history, history: 2, named: "window-history-failed", isFramed: true),
            windowSnapshot(selecting: .history, history: 5, named: "window-history-no-audio", isFramed: true),
            windowSnapshot(selecting: .insights, named: "window-insights"),
            windowSnapshot(selecting: .usage, named: "window-usage", isFramed: true),
            windowSnapshot(selecting: .general, named: "window-general"),
            windowSnapshot(selecting: .speech, named: "window-speech"),
            windowSnapshot(selecting: .dictionary, named: "window-dictionary"),
            windowSnapshot(
                suggestions: sampleSuggestions, selecting: .dictionary, named: "window-dictionary-suggestions"),
            windowSnapshot(selecting: .modes, named: "window-modes"),
            windowSnapshot(selecting: .microphones, named: "window-microphone"),
        ]
    }

    static var sampleDictionary: PersonalDictionary {
        PersonalDictionary(
            terms: [
                "PyTorch", "zshrc", "Vercel", "uv", "Supabase", String(repeating: "very-long-identifier-", count: 3),
            ],
            rules: [
                ReplacementRule(find: "cloud code", replacement: "Claude Code"),
                ReplacementRule(find: "um", replacement: ""),
            ]
        )
    }

    /// What Wispr Flow would add, and its counts: one learned correction, two snippets.
    static var sampleWisprImport: (PersonalDictionary, WisprFlowImport.Contents) {
        var incoming = PersonalDictionary(terms: ["Xandor", "changeset"])
        incoming.rules = [ReplacementRule(find: "Zandor", replacement: "Xandor")]
        return (incoming, WisprFlowImport.Contents(dictionary: incoming, learned: incoming.rules, snippets: 2))
    }

    static var sampleSuggestions: [DictionarySuggestion] {
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        return [
            DictionarySuggestion(
                candidate: SuggestionCandidate(
                    heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .fix,
                    appBundleID: "com.apple.TextEdit"),
                evidence: 3, firstSeenAt: seen, lastSeenAt: seen),
            DictionarySuggestion(
                candidate: SuggestionCandidate(heard: "ember", corrected: "embra", proposes: .term, origin: .fix),
                firstSeenAt: seen, lastSeenAt: seen),
        ]
    }

    /// 116 words, over the cap: the last dictation left out two of the sample words and the newest padding.
    static var sampleOverCapModel: DictionaryModel {
        var dictionary = sampleDictionary
        dictionary.terms += (1...110).map { "word\($0)" }
        let notSent = ["zshrc", "uv"] + (95...110).map { "word\($0)" }
        return sampleModel(dictionary, termUse: ["pytorch": TermUse(isPinned: true)], notSent: Set(notSent))
    }

    /// A model over a throwaway store; snapshots never save. "Vercel" is starred.
    static func sampleModel(
        _ dictionary: PersonalDictionary,
        suggestions: [DictionarySuggestion] = [],
        termUse: [String: TermUse] = ["vercel": TermUse(isPinned: true)],
        notSent: Set<String> = []
    ) -> DictionaryModel {
        let url = FileManager.default.temporaryDirectory.appending(path: "kotoba-snapshot-\(UUID().uuidString).sqlite")
        let store: DictionaryStore
        do {
            store = try DictionaryStore(url: url)
        } catch {
            preconditionFailure("Snapshot dictionary store: \(error)")
        }
        let model = DictionaryModel(
            dictionary: dictionary, termUse: termUse, notSent: notSent, store: store, suggestions: suggestions
        ) { _ in }
        model.isWisprInstalled = true
        return model
    }

    /// The whole window with every pane, showing `id`; `history` selects that History sample row.
    private static func windowSnapshot(
        suggestions: [DictionarySuggestion] = [],
        selecting id: PaneID,
        history selected: Int = 0,
        named name: String,
        isFramed: Bool = false
    ) -> Snapshot {
        MainWindow.windowSnapshot(
            of: samplePanes(suggestions: suggestions, history: selected), selecting: id, named: name,
            isFramed: isFramed)
    }

    /// Every pane with sample data; `history` selects that History sample row.
    private static func samplePanes(suggestions: [DictionarySuggestion] = [], history selected: Int = 0) -> [Pane] {
        let rows = HistoryController.sampleRows()
        let history = HistoryModel(rows: rows)
        history.selection = [rows[selected].id]
        return [
            .home(.sample),
            .history(history),
            .general(.sample()),
            .dictionary(sampleModel(sampleDictionary, suggestions: suggestions)),
            .modes(ModesModel(source: .sample())),
            .microphones(MicrophoneModel(source: .sample()) {}),
            .speech(.sample(route: .openRouterMAI, azureEndpoint: "")),
            .usage(.sample),
            .insights(.sample),
        ]
    }

    /// Each pane with an empty state, on a new install, at the default size and wide: the state sits in the centre of
    /// the space it gets.
    static func emptyWindowSnapshots() -> [Snapshot] {
        let wide = NSSize(width: 1_440, height: 900)
        let ids: [PaneID] = [.home, .history, .insights, .usage, .dictionary]
        return ids.flatMap { id in
            [("", MainWindow.defaultSize), ("-wide", wide)].map { suffix, size in
                MainWindow.windowSnapshot(
                    of: emptyPanes(), selecting: id, named: "window-empty-\(id.rawValue)\(suffix)", size: size)
            }
        }
    }

    /// Every pane of a new install: no key, no dictations, no words.
    private static func emptyPanes() -> [Pane] {
        [
            .home(.sampleNew),
            .history(HistoryModel(rows: [])),
            .general(.sample()),
            .dictionary(sampleModel(PersonalDictionary())),
            .modes(ModesModel(source: .sample())),
            .microphones(MicrophoneModel(source: .sample()) {}),
            .speech(.sample(route: .openRouterMAI, azureEndpoint: "")),
            .usage(.empty),
            .insights(.empty),
        ]
    }

    /// One window switched Home, History, General, Insights, Usage in turn, drawn at each step: the toolbar, traffic lights
    /// and window frame stay where they were on Home.
    static func switchSnapshots() -> [Snapshot] {
        let path: [PaneID] = [.home, .history, .general, .insights, .usage]
        return path.indices.map { end in
            MainWindow.switchSnapshot(
                of: samplePanes(), through: Array(path[...end]), named: "window-switch-\(path[end].rawValue)")
        }
    }
}
