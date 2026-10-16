import AppKit
import Charts
import KotobaCore
import KotobaStorage
import Observation
import SwiftUI

extension SettingsPane {
    static func insights(_ model: InsightsModel) -> Self {
        SettingsPane(id: .insights) {
            AnyView(InsightsPane(model: model))
        }
    }
}

/// How the owner dictates: speaking speed, streak, time saved, words, learned words and top apps. Built with each
/// Settings window; it reads the usage ledger and the dictionary when the pane appears, and while it is shown after
/// each write to either and when the day changes, so nothing runs at idle.
@MainActor
@Observable
final class InsightsModel {
    struct Figures: Equatable {
        var history: DictationInsights
        /// Words still in the dictionary that kotoba learned from the owner's corrections, by where they came from.
        var learned: [SuggestionCandidate.Origin: Int]
    }

    /// The typing speed "Time saved" compares with, in words per minute.
    static let typingSpeed = 40

    private(set) var figures: Figures?
    private(set) var isLoadFailed = false
    /// Each top app's name and icon by bundle ID, looked up once for the model's life, not at each read or draw.
    private(set) var names: [String: String] = [:]
    private(set) var icons: [String: NSImage] = [:]

    /// The figures at a date. Nil for snapshots, which set the figures themselves.
    @ObservationIgnored private let read: (@MainActor (_ now: Date) async throws -> Figures)?
    /// The read in progress; a write during it asks for one more read after it, so a burst of writes costs at most two
    /// reads.
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var isReadDue = false
    @ObservationIgnored private var isShown = false

    init(read: @escaping @MainActor (_ now: Date) async throws -> Figures) {
        self.read = read
    }

    /// For snapshots: fixed figures and no store.
    init(figures: Figures) {
        read = nil
        self.figures = figures
        readApps()
    }

    /// The pane appeared, or the owner asked to try again.
    func show() {
        isShown = true
        reload()
    }

    func hide() {
        isShown = false
        reading?.cancel()
        reading = nil
    }

    /// The ledger or the dictionary was written, or the day changed: a shown pane reads again; a hidden one reads when
    /// it appears.
    func storeChanged() {
        guard isShown else { return }
        reload()
    }

    private func reload() {
        guard let read else { return }
        guard reading == nil else {
            isReadDue = true
            return
        }
        reading = Task {
            repeat {
                isReadDue = false
                do {
                    let loaded = try await read(.now)
                    // `hide()` cancelled it; a newer read may already be running.
                    guard !Task.isCancelled else { return }
                    isLoadFailed = false
                    // Most writes change no figure (a dictation's first save has no answer yet): no redraw then.
                    guard loaded != figures else { continue }
                    figures = loaded
                    readApps()
                } catch {
                    guard !Task.isCancelled else { return }
                    Log.app.error("Cannot read insights: \(error)")
                    isLoadFailed = true
                }
            } while isReadDue && !Task.isCancelled
            // A cancelled read was already replaced by `hide()`, maybe by a newer one: leave that handle alone.
            if !Task.isCancelled { reading = nil }
        }
    }

    /// A row keeps the app's name from its newest dictation; an app kept without one gets its installed name.
    private func readApps() {
        for app in figures?.history.apps.map(\.app) ?? [] {
            if let name = app.name, names[app.bundleID] != name {
                names[app.bundleID] = name
            } else if app.name == nil, names[app.bundleID] == nil {
                names[app.bundleID] = InstalledApp.name(of: app.bundleID) ?? "Unknown app"
            }
            if icons[app.bundleID] == nil {
                icons[app.bundleID] = InstalledApp.icon(of: app.bundleID)
            }
        }
    }
}

private struct InsightsPane: View {
    let model: InsightsModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .insights)
            }
            if model.isLoadFailed {
                Section {
                    LabeledContent {
                        Button("Try Again", action: model.show)
                    } label: {
                        Text("Couldn’t read your dictation history.")
                    }
                }
            } else if let figures = model.figures {
                if figures.history.dictations == 0 {
                    Section {
                        ContentUnavailableView(
                            "No Insights Yet", systemImage: "chart.line.uptrend.xyaxis",
                            description: Text(
                                "Your speaking speed, streak and top apps appear here after your first dictation."))
                    }
                } else {
                    highlights(figures.history)
                    words(figures.history)
                    learned(figures.learned)
                    apps(figures.history)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.show)
        .onDisappear(perform: model.hide)
        // Today, the streak and the chart move at midnight; the task ends when the pane goes.
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                model.storeChanged()
            }
        }
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
                    detail: Self.streakDetail(insights))
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
                    LabeledContent {
                        Text(StatusText.counted(row.words, "word"))
                    } label: {
                        Label {
                            Text(model.names[row.app.bundleID] ?? "Unknown app")
                        } icon: {
                            if let icon = model.icons[row.app.bundleID] {
                                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "app.dashed")
                            }
                        }
                    }
                }
            }
        }
    }

    private static func streakDetail(_ insights: DictationInsights) -> String {
        if insights.isTodayInStreak { return "Today included" }
        return insights.streak > 0 ? "Dictate today to keep it" : "Dictate today to start one"
    }

    /// "42 sec" under a minute, else hours and minutes ("1 hr, 42 min").
    private static func duration(_ duration: Duration) -> String {
        duration < .seconds(60)
            ? duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
            : duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// One figure of the top row, as the figures at the top of a Screen Time or Battery pane. Custom: `LabeledContent`
/// has no large-value style.
private struct Highlight: View {
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
extension SettingsPane {
    static func insightsSnapshots() -> [Snapshot] {
        [
            SettingsWindow.snapshot(of: .insights(.sample), named: "settings-insights", height: 900),
            SettingsWindow.snapshot(of: .insights(.empty), named: "settings-insights-empty"),
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
