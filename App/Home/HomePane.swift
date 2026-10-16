import AppKit
import KotobaCore
import KotobaProviders
import KotobaStorage
import SwiftUI

extension Pane {
    static func home(_ model: HomeModel) -> Self {
        Pane(id: .home) {
            AnyView(HomePane(model: model))
        }
    }
}

/// The first pane of the main window: kotoba's icon and version, whether it is ready (with the button that fixes what
/// is missing), today's figures, the newest dictations and the chords.
private struct HomePane: View {
    let model: HomeModel
    @Environment(\.openPane) private var openPane

    var body: some View {
        Form {
            Section {
                hero
                status
            }
            if model.reader.isLoadFailed {
                Section {
                    EmptyState.loadFailed(retry: model.reader.show)
                }
            } else if let figures = model.reader.value {
                if figures.insights.dictations > 0 {
                    activity(figures.insights)
                }
                recent(figures)
            }
            shortcuts
        }
        .formStyle(.grouped)
        .reads(through: model.reader)
        .onAppear(perform: model.readiness.refresh)
    }

    private var hero: some View {
        HStack {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(Install.displayName).font(.title.weight(.semibold))
                Text("Version \(model.version)").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let missing = model.readiness.firstMissing {
            LabeledContent {
                fixButton(missing)
            } label: {
                Label {
                    Text("Not ready to dictate")
                    Text(missing.problemText)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
        } else {
            Label {
                Text("Ready to dictate")
                Text("Works in any app where you can type.")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
    }

    /// The fix goes the way of the menu's “Finish Setting Up kotoba…” (`SetupFlow.finishSetup`).
    private func fixButton(_ missing: Readiness.Missing) -> some View {
        let title =
            switch missing {
            case .microphone: "Allow Microphone…"
            case .accessibility: "Allow Accessibility…"
            case .setup(.key, _): "Add Key…"
            case .setup(.endpoint, _): "Add Endpoint…"
            case .setup(.credit, _): "Add Credit…"
            }
        return Button(title, action: model.finishSetup)
    }

    /// The chords as the owner set them in General; each redraws when a chord changes. The words are General's.
    private var shortcuts: some View {
        Section {
            LabeledContent {
                Text(model.chords.dictation.title)
            } label: {
                Text("Dictate")
                Text(StatusText.shortcutHelp(.dictation))
            }
            if let cleanup = model.chords.cleanup {
                LabeledContent {
                    Text(cleanup.title)
                } label: {
                    Text("Clean up")
                    Text(StatusText.shortcutHelp(.cleanup))
                }
            }
            if let pasteLast = model.chords.pasteLast {
                LabeledContent {
                    Text(pasteLast.title)
                } label: {
                    Text("Paste last dictation")
                    Text(StatusText.shortcutHelp(.pasteLast))
                }
            }
            LabeledContent {
                Text("Esc")
            } label: {
                Text("Cancel")
                Text("While you dictate.")
            }
        } header: {
            Text("How to Dictate")
        } footer: {
            HStack {
                Spacer()
                Button("Change Shortcuts") { openPane(.general) }
            }
        }
    }

    private func activity(_ insights: DictationInsights) -> some View {
        Section {
            HStack(alignment: .top) {
                Highlight(
                    title: "Today", systemImage: "sun.max", value: StatusText.counted(model.today?.words ?? 0, "word"),
                    detail: StatusText.counted(model.today?.dictations ?? 0, "dictation"))
                Divider()
                Highlight(
                    title: "This week", systemImage: "calendar",
                    value: StatusText.counted(insights.wordsThisWeek, "word"),
                    detail: "\(insights.wordsThisMonth.formatted()) this month")
                Divider()
                Highlight(
                    title: "Streak", systemImage: "flame", value: StatusText.counted(insights.streak, "day"),
                    detail: insights.streakDetail)
            }
        } header: {
            header("Activity", link: "Show Insights", opening: .insights)
        }
    }

    private func recent(_ figures: HomeModel.Figures) -> some View {
        Section {
            if figures.recent.isEmpty {
                EmptyState.noDictations(chord: model.chords.dictation)
            } else {
                ForEach(figures.recent) { record in
                    HStack(alignment: .top) {
                        HistoryRow(
                            record: record, apps: model.apps, isRetryable: figures.retryable.contains(record.id))
                        // Hidden, not removed, on a row with no text: the times stay in one column.
                        let copy = Button("Copy", systemImage: "doc.on.doc") { model.copy(record) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Copy the text")
                            .padding(.top, 4)
                        if record.deliveredText?.isEmpty == false {
                            copy
                        } else {
                            copy.hidden()
                        }
                    }
                }
            }
        } header: {
            header("Recent Dictations", link: figures.recent.isEmpty ? nil : "Show All", opening: .history)
        } footer: {
            if figures.hasLastDictation {
                HStack {
                    Spacer()
                    Button("Fix Last Dictation…", action: model.fixLast)
                }
            }
        }
    }

    /// A section title with a link to the pane that shows more, as in Music's "See All"; no link when there is no
    /// more to show.
    private func header(_ title: String, link: String?, opening pane: PaneID) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let link {
                Button(link) { openPane(pane) }
                    .buttonStyle(.link)
            }
        }
    }
}

// MARK: - Snapshots

@MainActor
extension Pane {
    /// Home in use (ready, with figures and dictations), and a new install with no key and no dictations.
    static func homeSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .home(.sample), named: "home", height: 1_240),
            MainWindow.snapshot(of: .home(.sampleNew), named: "home-new"),
        ]
    }
}

extension HomeModel {
    /// Synthetic figures: five dictations, a streak that includes today.
    static var sample: HomeModel {
        let today = Calendar.current.startOfDay(for: .now)
        let insights = DictationInsights(
            dictations: 1_204, wordsThisWeek: 3_575, wordsThisMonth: 12_840, words: 48_310, streak: 5,
            isTodayInStreak: true, days: [.init(start: today, words: 640, dictations: 14)])
        let recent = Array(HistoryController.sampleRows().prefix(recentCount))
        return HomeModel(
            readiness: .sample(), chords: HotkeyChords(defaults: nil),
            figures: Figures(
                insights: insights, recent: recent, hasLastDictation: true, retryable: HistoryModel.kept(recent)))
    }

    /// A first launch: no OpenRouter key yet, nothing dictated.
    static var sampleNew: HomeModel {
        HomeModel(
            readiness: .sample(missingSetup: (.key, .openRouter)), chords: HotkeyChords(defaults: nil),
            figures: Figures(insights: DictationInsights(), recent: [], hasLastDictation: false))
    }
}
