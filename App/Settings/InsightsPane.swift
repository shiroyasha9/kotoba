import AppKit
import Charts
import KotobaCore
import KotobaStorage
import Observation
import SwiftUI

extension Pane {
    static func insights(_ model: InsightsModel) -> Self {
        Pane(id: .insights) {
            AnyView(InsightsPane(model: model))
        }
    }
}

/// How the owner dictates: speaking speed, streak, time saved, words, learned words and top apps. Built with each
/// main window; it reads the usage ledger and the dictionary while the pane is shown (`PaneReader`): when it appears,
/// after each write to either and when the day changes, so nothing runs at idle.
@MainActor
final class InsightsModel {
    struct Figures: Equatable {
        var history: DictationInsights
        /// Words still in the dictionary that kotoba learned from the owner's corrections, by where they came from.
        var learned: [SuggestionCandidate.Origin: Int]
    }

    /// The typing speed "Time saved" compares with, in words per minute.
    static let typingSpeed = 40

    let reader: PaneReader<Figures>
    let apps = InstalledApps()

    /// `read` gives the figures at a date.
    init(read: @escaping @MainActor (_ now: Date) async throws -> Figures) {
        reader = PaneReader("insights") { try await read(.now) }
    }

    /// For snapshots: fixed figures and no store.
    init(figures: Figures) {
        reader = PaneReader(value: figures)
    }

    /// The ledger or the dictionary was written: a shown pane reads again.
    func storeChanged() {
        reader.changed()
    }
}

private struct InsightsPane: View {
    let model: InsightsModel

    var body: some View {
        // One container, not a Group: a Group gives each branch its own onAppear and onDisappear, so the change from
        // the placeholder to the figures would read again, or leave the reader hidden.
        VStack {
            if model.reader.isLoadFailed {
                EmptyState.loadFailed(retry: model.reader.show)
            } else if let figures = model.reader.value {
                if figures.history.dictations == 0 {
                    EmptyState(
                        "No Insights Yet", systemImage: "chart.line.uptrend.xyaxis",
                        description: "Your speaking speed, streak and top apps appear here after your first dictation.")
                } else {
                    Form {
                        highlights(figures.history)
                        words(figures.history)
                        learned(figures.learned)
                        apps(figures.history)
                    }
                    .formStyle(.grouped)
                }
            } else {
                // Before the first read: a view that appears, so the read starts.
                Color.clear
            }
        }
        .reads(through: model.reader)
    }

    private func highlights(_ insights: DictationInsights) -> some View {
        Section {
            HStack(alignment: .top) {
                Highlight(
                    title: "Words per minute", systemImage: "speedometer",
                    value: insights.wordsPerMinute?.formatted() ?? "None",
                    detail: "Over \(StatusText.counted(insights.dictations, "dictation"))")
                Divider()
                Highlight(
                    title: "Streak", systemImage: "flame", value: StatusText.counted(insights.streak, "day"),
                    detail: insights.streakDetail)
                Divider()
                Highlight(
                    title: "Time saved", systemImage: "clock",
                    value: Self.duration(insights.timeSaved(typingSpeed: InsightsModel.typingSpeed)),
                    detail: "Compared with typing")
            }
        } footer: {
            Text(
                "Words per minute counts the words you spoke over the length of your recordings, pauses included. "
                    + "Time saved compares typing your words at \(InsightsModel.typingSpeed) words per minute with "
                    + "the time you spent speaking them.")
        }
    }

    private func words(_ insights: DictationInsights) -> some View {
        Section("Words Dictated") {
            VStack(alignment: .leading) {
                Text("Last \(InsightsQuery.chartDays) days").foregroundStyle(.secondary)
                WordsChart(days: insights.days)
            }
            LabeledContent("This week", value: insights.wordsThisWeek.formatted())
            LabeledContent("This month", value: insights.wordsThisMonth.formatted())
            LabeledContent("All time", value: insights.words.formatted())
        }
    }

    private typealias Origin = SuggestionCandidate.Origin

    private func learned(_ learned: [Origin: Int]) -> some View {
        // Every origin counts; the two that exist today get a part each.
        let total = learned.values.reduce(0, +)
        let parts = [(Origin.edit, "from your edits"), (.fix, "from Fix Last Dictation")].compactMap { origin, text in
            learned[origin].flatMap { $0 > 0 ? "\($0.formatted()) \(text)" : nil }
        }
        return Section("Learning") {
            LabeledContent {
                Text(total.formatted())
            } label: {
                Text("Words learned")
                if total == 0 {
                    Text("kotoba learns a word when you correct a dictation.")
                } else if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                }
            }
        }
    }

    @ViewBuilder
    private func apps(_ insights: DictationInsights) -> some View {
        if !insights.apps.isEmpty {
            Section("Top Apps") {
                ForEach(insights.apps, id: \.app.bundleID) { row in
                    AppWordsRow(row: row, apps: model.apps)
                }
            }
        }
    }

    /// "42 sec" under a minute, else hours and minutes ("1 hr, 42 min").
    private static func duration(_ duration: Duration) -> String {
        duration < .seconds(60)
            ? duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
            : duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

extension DictationInsights {
    /// The line under the streak, here and on Home.
    var streakDetail: String {
        if isTodayInStreak { return "Today included" }
        return streak > 0 ? "Dictate today to keep it" : "Dictate today to start one"
    }
}

/// One figure of the top row, as the figures at the top of a Screen Time or Battery pane; Home shows three too.
/// Custom: `LabeledContent` has no large-value style.
struct Highlight: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Words per day as bars, today last.
private struct WordsChart: View {
    let days: [DictationInsights.Day]

    var body: some View {
        Chart(days, id: \.start) { day in
            BarMark(x: .value("Day", day.start, unit: .day), y: .value("Words", day.words))
                .foregroundStyle(.tint)
        }
        // A label at each week's start, without the year; three word counts are enough to read a bar.
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .frame(height: 120)
    }
}

// MARK: - Snapshots

@MainActor
extension Pane {
    static func insightsSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .insights(.sample), named: "settings-insights", height: 900),
            MainWindow.snapshot(of: .insights(.empty), named: "settings-insights-empty"),
        ]
    }
}

extension InsightsModel {
    /// Two months of synthetic use: a streak that includes today, quiet weekends, four apps and a few learned words.
    static var sample: InsightsModel {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let words = [
            420, 610, 0, 0, 540, 720, 380, 655, 510, 90, 0, 830, 760, 590, 640, 470, 0, 0, 910, 680, 720, 560, 805,
            120, 0, 690, 740, 610, 880, 350,
        ]
        let days = words.enumerated().compactMap { index, count in
            calendar.date(byAdding: .day, value: index + 1 - words.count, to: today).map {
                DictationInsights.Day(start: $0, words: count, dictations: count / 40)
            }
        }
        let history = DictationInsights(
            dictations: 1_204, wordsThisWeek: 3_575, wordsThisMonth: 12_840, words: 48_310, spokenWords: 49_020,
            speakingTime: .seconds(20_850), streak: 5, isTodayInStreak: true, days: days,
            apps: [
                .init(app: DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), words: 21_480),
                .init(app: DictationApp(bundleID: "com.apple.mail", name: "Mail"), words: 11_906),
                .init(app: DictationApp(bundleID: "com.apple.Notes", name: "Notes"), words: 8_312),
                .init(app: DictationApp(bundleID: "com.apple.TextEdit", name: "TextEdit"), words: 4_120),
            ])
        return InsightsModel(figures: Figures(history: history, learned: [.edit: 14, .fix: 3]))
    }

    /// A new install: no dictations, nothing learned.
    static var empty: InsightsModel {
        InsightsModel(figures: Figures(history: DictationInsights(), learned: [:]))
    }
}
