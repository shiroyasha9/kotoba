import KotobaCore
import KotobaProviders
import SwiftUI

extension Pane {
    static func modes(_ model: ModesModel) -> Self {
        Pane(id: .modes) {
            AnyView(CleanupPage(model: model))
        }
    }
}

/// Cleanup, Rewrite and App styles on one page, each with one example (docs/research/ui-redesign.md, "Page map"); the
/// cleanup model is in "Advanced…". The shortcuts are set on the Shortcuts page; this page names them.
private struct CleanupPage: View {
    @Bindable var model: ModesModel
    @Environment(\.openPane) private var openPane

    var body: some View {
        PageForm {
            Section {
                PageHeader(
                    page: .modes,
                    summary: "kotoba can clean up your words before it pastes them, and rewrite them after.")
            }
            if model.isCleanupKeyMissing {
                Section {
                    PageRow(
                        title: "Cleanup needs your \(ProviderAccount.openRouter.title) key",
                        subtitle: "Without it, kotoba pastes the text as spoken."
                    ) {
                        SymbolTile(
                            systemImage: "exclamationmark.triangle", tint: .orange, side: PageMetrics.rowTileSide)
                    } trailing: {
                        Button("Add Key…", action: model.addKey)
                    }
                }
            }
            cleanup
            rewrite
            appStyles
        }
        .onAppear(perform: model.show)
        .task { await model.readRecentApps() }
        .sheet(isPresented: $model.isAdvancedShown) {
            CleanupAdvanced(model: model)
        }
    }

    private var cleanup: some View {
        Section {
            let sample = AppMode.writing.sample
            Text("Cleanup removes filler words and fixes punctuation as you dictate.")
            CleanupSample(
                before: ("You say", sample.spoken), after: ("kotoba pastes", sample.cleaned))
            ForEach(AppMode.allCases, id: \.self) { mode in
                PageToggle(
                    title: "Every dictation in \(mode.title.lowercased()) apps", subtitle: mode.apps,
                    isOn: cleansEveryDictation(mode))
            }
            shortcutRow(.cleanup, subtitle: "Cleans up one dictation in any app.")
        } header: {
            Text("Cleanup")
        } footer: {
            Text("Each cleanup adds about 1-2 seconds before the paste.")
        }
    }

    private var rewrite: some View {
        Section {
            Text("Rewrite makes your last dictation shorter and clearer, with nothing left out.")
            CleanupSample(
                before: ("You dictated", Self.rewriteSample.dictated),
                after: ("kotoba pastes", Self.rewriteSample.rewritten))
            shortcutRow(.polishLast, subtitle: "Rewrites the dictation you pasted last.")
        } header: {
            Text("Rewrite")
        }
    }

    private var appStyles: some View {
        Section {
            let sample = AppMode.code.sample
            Text("Each app has a style. In code apps, cleanup keeps commands, paths and flags as you said them.")
            CleanupSample(
                before: ("You say", sample.spoken), after: ("kotoba pastes", sample.cleaned))
            EditableList(
                rows: model.rows, emptyText: "No apps in the list: every app uses the style below.",
                addTitle: "Add App", addHelp: "Give an app its own style", removeTitle: "Remove from List",
                remove: model.remove
            ) { row in
                PageRow(title: row.name, subtitle: nil) {
                    AppIconView(icon: model.icons[row.bundleID])
                } trailing: {
                    Picker(row.name, selection: mode(of: row)) {
                        modeChoices
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } addItems: {
                if !model.recent.isEmpty {
                    Section("Recent Apps") {
                        ForEach(model.recent, id: \.bundleID) { app in
                            // Names only: a menu draws an app icon at its own 32 pt.
                            Button(app.name ?? app.bundleID) { model.add(app) }
                        }
                    }
                }
                Button("Choose App…", action: model.chooseApp)
            }
            Picker("Other apps", selection: $model.otherApps) {
                modeChoices
            }
        } header: {
            Text("App Styles")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("kotoba uses the style of the app in front when you stop a dictation.")
                Spacer()
                // Alone at the trailing edge under the last group, as Activity's and Battery's "Options…".
                Button("Advanced…") { model.isAdvancedShown = true }
            }
        }
    }

    /// A shortcut that starts the feature, with its keycaps; the Shortcuts page sets it.
    private func shortcutRow(_ role: ChordRole, subtitle: String) -> some View {
        PageRow(title: StatusText.shortcutTitle(role), subtitle: subtitle) {
            if let chord = model.chords.chord(role) {
                Keycaps(keys: chord.keycaps)
            } else {
                Button("Set Shortcut…") { openPane(.shortcuts) }
            }
        }
    }

    /// What the owner dictated and what Rewrite pastes, from the second example in Rewrite's prompt
    /// (`OpenRouterPolisher.systemPrompt`), shortened.
    private static let rewriteSample = (
        dictated:
            "So I’m trying to figure out, like, should we move the queue from Redis to Postgres? Because jobs get "
            + "lost when Redis restarts. Don’t change anything yet, just tell me the options.",
        rewritten: "Should we move the queue from Redis to Postgres? Jobs get lost when Redis restarts. Don’t change "
            + "anything yet. Tell me the options."
    )

    private var modeChoices: some View {
        ForEach(AppMode.allCases, id: \.self) { Text($0.title).tag($0) }
    }

    private func mode(of row: ModesModel.Row) -> Binding<AppMode> {
        Binding(get: { row.mode }, set: { model.setMode($0, of: row.bundleID) })
    }

    private func cleansEveryDictation(_ mode: AppMode) -> Binding<Bool> {
        Binding(get: { model.cleansEveryDictation(mode) }, set: { model.setCleansEveryDictation(mode, $0) })
    }
}

/// The Cleanup page's "Advanced…": the cleanup model, by name with what it is in plain words.
struct CleanupAdvanced: View {
    @Bindable var model: ModesModel

    var body: some View {
        PageSheet(title: "Advanced Cleanup Settings") {
            Section {
                ForEach(CleanupModel.allCases, id: \.self) { choice in
                    ChoiceRow(title: choice.title, subtitle: choice.summary, isChosen: model.cleanupModel == choice) {
                        model.cleanupModel = choice
                    }
                }
            } header: {
                Text("Cleanup Model")
            } footer: {
                Text("Cleanup and every app style use this model, through your OpenRouter key.")
            }
        }
    }
}

extension CleanupModel {
    /// What the model is, in plain words: the line under its name.
    var summary: String {
        switch self {
        case .geminiFlashLite: "Recommended: about 1.5 seconds per cleanup in kotoba’s tests."
        case .qwenCerebras: "Often the fastest in kotoba’s tests, but sometimes slow or fails."
        case .claudeHaiku: "Another model, from Anthropic."
        }
    }
}

@MainActor
extension Pane {
    /// No OpenRouter key: the page says so first, with the fix on a button.
    private static var noKeyModel: ModesModel {
        var source = ModesModel.Source.sample()
        source.hasCleanupKey = { false }
        return ModesModel(source: source, chords: HotkeyChords(defaults: nil))
    }

    /// Every shortcut set, so both shortcut rows show keycaps.
    private static var allShortcutsModel: ModesModel {
        ModesModel(
            source: .sample(), chords: HotkeyChords(defaults: nil, polishLast: Chord.polishLastSuggestions.first))
    }

    static func modesSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .modes(allShortcutsModel), named: "settings-modes", height: 1_500),
            MainWindow.snapshot(
                of: .modes(ModesModel(source: .sample(rules: ModeRules()), chords: HotkeyChords(defaults: nil))),
                named: "settings-modes-empty", height: 1_400),
            MainWindow.snapshot(of: .modes(noKeyModel), named: "settings-modes-no-key", height: 1_600),
            MainWindow.sheetSnapshot(named: "settings-modes-advanced") {
                CleanupAdvanced(model: ModesModel(source: .sample(), chords: HotkeyChords(defaults: nil)))
            },
        ]
    }
}
