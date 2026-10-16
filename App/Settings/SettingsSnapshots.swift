import AppKit
import KotobaCore
import KotobaStorage

/// Sample data for the Settings snapshots, and the whole window on each pane (`make snapshots`). Samples never touch
/// the owner's files, Keychain or devices.
@MainActor
extension SettingsPane {
    /// The whole window, once per pane and for the Dictionary pane's suggestions state.
    static func windowSnapshots() -> [Snapshot] {
        [
            windowSnapshot(sampleDictionary, selecting: .dictionary, named: "settings-window"),
            windowSnapshot(
                sampleDictionary, suggestions: sampleSuggestions, selecting: .dictionary,
                named: "settings-window-suggestions"),
            windowSnapshot(sampleDictionary, selecting: .speech, named: "settings-window-speech"),
            windowSnapshot(sampleDictionary, selecting: .microphones, named: "settings-window-microphone"),
            windowSnapshot(sampleDictionary, selecting: .general, named: "settings-window-general"),
            windowSnapshot(sampleDictionary, selecting: .usage, named: "settings-window-usage"),
            windowSnapshot(sampleDictionary, selecting: .insights, named: "settings-window-insights"),
            windowSnapshot(sampleDictionary, selecting: .modes, named: "settings-window-modes"),
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

    /// The whole window with every pane, showing `id`.
    private static func windowSnapshot(
        _ dictionary: PersonalDictionary,
        suggestions: [DictionarySuggestion] = [],
        selecting id: SettingsPaneID,
        named name: String
    ) -> Snapshot {
        let panes: [SettingsPane] = [
            .general(.sample()),
            .dictionary(sampleModel(dictionary, suggestions: suggestions)),
            .modes(ModesModel(source: .sample())),
            .microphones(MicrophoneModel(source: .sample()) {}),
            .speech(.sample(route: .openRouterMAI, azureEndpoint: "")),
            .usage(.sample),
            .insights(.sample),
        ]
        return SettingsWindow.windowSnapshot(of: panes, selecting: id, named: name)
    }
}
