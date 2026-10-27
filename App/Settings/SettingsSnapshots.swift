import AppKit
import KotobaCore
import KotobaStorage

/// Sample data for the Settings snapshots, and the whole main window on each pane (`make snapshots`). Samples never touch
/// the owner's files, Keychain or devices.
@MainActor
extension Pane {
    /// The whole main window: Home, History, and each settings pane, the Dictionary pane also with suggestions. Home,
    /// History and Activity framed too: the title bar keeps one height on every page. History with its first row
    /// selected, also with its audio playing.
    static func windowSnapshots() -> [Snapshot] {
        [
            windowSnapshot(selecting: .home, named: "window-home"),
            windowSnapshot(selecting: .home, named: "window-home-framed", isFramed: true),
            windowSnapshot(selecting: .history, named: "window-history"),
            windowSnapshot(selecting: .history, named: "window-history-framed", isFramed: true),
            windowSnapshot(selecting: .history, isPlaying: true, named: "window-history-playing", isFramed: true),
            windowSnapshot(selecting: .activity, named: "window-activity"),
            windowSnapshot(selecting: .activity, named: "window-activity-framed", isFramed: true),
            windowSnapshot(selecting: .shortcuts, named: "window-shortcuts"),
            windowSnapshot(selecting: .general, named: "window-general"),
            windowSnapshot(selecting: .speech, named: "window-speech"),
            windowSnapshot(selecting: .dictionary, named: "window-dictionary"),
            // Framed: its search, Import and + in the window toolbar.
            windowSnapshot(selecting: .dictionary, named: "window-dictionary-framed", isFramed: true),
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

    /// The whole window with every pane, showing `id`; `isPlaying` shows History's first row's audio playing.
    private static func windowSnapshot(
        suggestions: [DictionarySuggestion] = [],
        selecting id: PaneID,
        isPlaying: Bool = false,
        named name: String,
        isFramed: Bool = false
    ) -> Snapshot {
        MainWindow.windowSnapshot(
            of: samplePanes(suggestions: suggestions, isPlaying: isPlaying), selecting: id,
            named: name, isFramed: isFramed)
    }

    /// The README's and the site's window images (`make readme-images`, `Showcase`): the whole window as the release
    /// shows it, each page from its top: dictations with text (as Home's), none selected, and words a reader knows in
    /// the dictionary.
    static func showcaseSnapshots() -> [Snapshot] {
        let dictionary = PersonalDictionary(
            terms: ["PyTorch", "Supabase", "Vercel", "Kubernetes", "zshrc"],
            rules: [
                ReplacementRule(find: "cloud code", replacement: "Claude Code"),
                ReplacementRule(find: "um", replacement: ""),
            ])
        let history = HistoryModel(rows: HistoryController.sampleRows().filter(\.hasText))
        let panes = samplePanes(home: .readme, history: history, dictionary: dictionary)
        let ids: [PaneID] = [.home, .history, .activity, .dictionary, .modes]
        return ids.map { id in
            MainWindow.showcaseSnapshot(of: panes, selecting: id, named: "showcase-\(id.rawValue)")
        }
    }

    /// Every pane with sample data; `isPlaying` shows History's first row's audio playing, `history` replaces History's
    /// rows.
    static func samplePanes(
        suggestions: [DictionarySuggestion] = [], isPlaying: Bool = false, home: HomeModel = .sample,
        history: HistoryModel? = nil, dictionary: PersonalDictionary = sampleDictionary
    ) -> [Pane] {
        let rows = HistoryController.sampleRows()
        let sampleHistory = HistoryModel(rows: rows, playing: isPlaying ? rows[0].id : nil)
        sampleHistory.selection = [rows[0].id]
        return [
            .home(home),
            .history(history ?? sampleHistory),
            .general(.sample()),
            .shortcuts(.sample()),
            .dictionary(sampleModel(dictionary, suggestions: suggestions)),
            .modes(ModesModel(source: .sample(), chords: HotkeyChords(defaults: nil))),
            .microphones(MicrophoneModel(source: .sample()) {}),
            .speech(.sample(route: .openRouterMAI, azureEndpoint: "")),
            .activity(.sample()),
        ]
    }

    /// Each pane with an empty state, on a new install, at the default size and wide: the state sits in the centre of
    /// the space it gets.
    static func emptyWindowSnapshots() -> [Snapshot] {
        let wide = NSSize(width: PageMetrics.maximumWindowWidth, height: 900)
        let ids: [PaneID] = [.home, .history, .activity, .dictionary]
        return ids.flatMap { id in
            [("", PageMetrics.defaultWindowSize), ("-wide", wide)].map { suffix, size in
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
            .shortcuts(.sample()),
            .dictionary(sampleModel(PersonalDictionary())),
            .modes(ModesModel(source: .sample(), chords: HotkeyChords(defaults: nil))),
            .microphones(MicrophoneModel(source: .sample()) {}),
            .speech(.sample(route: .openRouterMAI, azureEndpoint: "")),
            .activity(.empty),
        ]
    }

    /// One window switched through every page in turn, drawn at each step: the title bar, traffic lights and window
    /// frame stay where they were on Home, also on a page with toolbar items.
    static func switchSnapshots() -> [Snapshot] {
        let path = PaneID.allCases
        return path.indices.map { end in
            MainWindow.switchSnapshot(
                of: samplePanes(), through: Array(path[...end]), named: "window-switch-\(path[end].rawValue)")
        }
    }
}

// MARK: - Window memory

@MainActor
extension Pane {
    /// `make window-memory` launches the app binary with `--window-memory`: the main window with the sample panes is
    /// built, shown on every pane and closed, three times, then idles 5 s. Each step prints the footprint (the number
    /// Activity Monitor shows), so a change to the window or to the allocator reports what stays after close.
    /// Offscreen, as the snapshots: glass draws nothing, so the numbers are a floor for the window on screen.
    static func measureWindowMemory() -> Never {
        reportFootprint(at: "launch")
        for cycle in 1...3 {
            autoreleasepool {
                let panes = samplePanes()
                let selection = Selection(panes: panes, showing: .home)
                let window = MainWindow.window(showing: MainView(panes: panes, selection: selection))
                window.setContentSize(PageMetrics.defaultWindowSize)
                for id in PaneID.allCases {
                    selection.id = id
                    Snapshots.settle()
                    window.displayIfNeeded()
                    // Each page's own cost, the first time: the window opens on Home, so Home's is what most owners pay.
                    if cycle == 1 { reportFootprint(at: "  \(id.rawValue)") }
                }
                reportFootprint(at: "window open \(cycle)")
                window.close()
            }
            Snapshots.settle()
            reportFootprint(at: "window closed \(cycle)")
        }
        // Core Animation and the GPU driver free the window's surfaces a few seconds after it closes, with no event to
        // wait on: the last step is defined as 5 s of idle run loop after the close.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 5))
        reportFootprint(at: "5 s after close")
        exit(0)
    }

    static func reportFootprint(at step: String) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let megabytes = { (bytes: Int64) in String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        let footprint = megabytes(Int64(info.phys_footprint))
        let line =
            status == KERN_SUCCESS
            ? "\(step): footprint \(footprint), peak \(megabytes(info.ledger_phys_footprint_peak))"
            : "\(step): no task info (\(status))"
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
