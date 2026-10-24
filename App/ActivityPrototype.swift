import AppKit
import Charts
import KotobaCore
import KotobaStorage
import SwiftUI

// The 0.5.0 Activity page (Insights and Usage in one), as a prototype on the new visual system (`Page.swift`;
// docs/research/ui-redesign.md, "Page map"). It draws sample data only; the prototype goes when the page is built.

/// What the Activity prototype shows: the samples the Insights and Usage snapshots use.
@MainActor
struct ActivityPrototypeData {
    var insights: DictationInsights
    var learned: [SuggestionCandidate.Origin: Int]
    /// This month's words, audio and spend.
    var month: UsageSummary
    let apps = InstalledApps()

    static var sample: Self {
        let insights = InsightsModel.sample.reader.value
        return Self(
            insights: insights?.history ?? DictationInsights(), learned: insights?.learned ?? [:],
            month: UsageModel.sample.summary ?? UsageSummary())
    }

    /// Someone who started three days ago: the chart starts at their first dictation.
    static var sampleNew: Self {
        var data = sample
        let recent = [0, 0, 0, 0, 260, 410, 180]
        data.insights.days = data.insights.days.suffix(recent.count).enumerated().map { index, day in
            DictationInsights.Day(start: day.start, words: recent[index], dictations: recent[index] / 40)
        }
        return data
    }
}

/// The chart's period: the Week/Month switch.
enum ActivityPeriod: CaseIterable, Hashable {
    case week
    case month

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// How many days the chart shows at most, today last.
    var dayCount: Int {
        switch self {
        case .week: 7
        case .month: InsightsQuery.chartDays
        }
    }
}

struct ActivityPrototype: View {
    let data: ActivityPrototypeData
    @State var period = ActivityPeriod.week

    var body: some View {
        PageForm {
            Section {
                PageHeader(title: "Activity", summary: "How much you dictate, in which apps, and what it costs.") {
                    SymbolTile(
                        systemImage: PrototypePage.activity.systemImage, tint: PrototypePage.activity.tint,
                        side: PageMetrics.rowTileSide)
                }
            }
            Section {
                DailyWords(days: data.insights.days, period: $period)
            }
            highlights
            topApps
            spend
        }
    }

    private var highlights: some View {
        let insights = data.insights
        let learned = data.learned.values.reduce(0, +)
        let learnedParts = [(SuggestionCandidate.Origin.edit, "from your edits"), (.fix, "from Fix Last Dictation")]
            .compactMap { origin, text in data.learned[origin].flatMap { $0 > 0 ? "\($0.formatted()) \(text)" : nil } }
        return Section("Highlights") {
            row(
                "Words per minute", "speedometer", .blue, value: insights.wordsPerMinute?.formatted() ?? "None",
                detail: "Your speaking speed, pauses included")
            row(
                "Streak", "flame", .orange, value: StatusText.counted(insights.streak, "day"),
                detail: insights.streakDetail)
            row(
                "Time saved", "clock", .green,
                value: Self.duration(insights.timeSaved(typingSpeed: InsightsModel.typingSpeed)),
                detail: "Compared with typing at \(InsightsModel.typingSpeed) words a minute")
            row(
                "Words learned", "character.book.closed", .purple, value: learned.formatted(),
                detail: learned == 0
                    ? "kotoba learns a word when you correct a dictation" : learnedParts.joined(separator: " · "))
        }
    }

    @ViewBuilder private var topApps: some View {
        if !data.insights.apps.isEmpty {
            Section("Top Apps") {
                ForEach(data.insights.apps, id: \.app.bundleID) { row in
                    LabeledContent {
                        Text(StatusText.counted(row.words, "word"))
                    } label: {
                        Label {
                            Text(data.apps.name(of: row.app) ?? "Unknown app")
                        } icon: {
                            AppIconView(icon: data.apps.icon(of: row.app), side: PageMetrics.lineTileSide)
                        }
                    }
                }
            }
        }
    }

    private var spend: some View {
        let month = data.month
        return Section {
            LabeledContent {
                Text(Self.dollars(month.cost))
            } label: {
                Text("Spend")
                if month.isCostEstimated {
                    Text("Partly estimated from list prices")
                }
            }
            LabeledContent("Dictations", value: month.dictations.formatted())
            LabeledContent("Audio", value: Self.duration(month.audio))
        } header: {
            Text("This Month")
        } footer: {
            HStack(alignment: .firstTextBaseline) {
                Text("What your speech and cleanup services billed. It stays when you delete dictations.")
                Spacer()
                Button("Advanced…") {}
            }
        }
    }

    /// A highlight: a tile, a title with one line under it, and the figure.
    private func row(_ title: String, _ symbol: String, _ tint: Color, value: String, detail: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                SymbolTile(systemImage: symbol, tint: tint, side: PageMetrics.rowTileSide)
            }
        }
    }

    /// Cents, as a bill shows them; "Less than $0.01" for a spend that rounds to nothing.
    private static func dollars(_ amount: Decimal) -> String {
        let cent = Decimal(sign: .plus, exponent: -2, significand: 1)
        let format = Decimal.FormatStyle.Currency(code: "USD").precision(.fractionLength(2))
        return amount > 0 && amount < cent ? "Less than \(cent.formatted(format))" : amount.formatted(format)
    }

    /// "42 sec" under a minute, else hours and minutes ("1 hr, 42 min").
    private static func duration(_ duration: Duration) -> String {
        duration < .seconds(60)
            ? duration.formatted(.units(allowed: [.seconds], width: .abbreviated))
            : duration.formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

/// Words per day as Screen Time draws its daily use: the daily average as the headline, rounded bars in the accent
/// colour, the average as a line, the word counts on the right. The chart starts at the first dictation: days before
/// it are not drawn, but a week's seven slots stay so a new user's bars keep their width.
private struct DailyWords: View {
    let days: [DictationInsights.Day]
    @Binding var period: ActivityPeriod

    var body: some View {
        let shown = Self.shown(days, period: period)
        let started = shown.drop { $0.words == 0 }
        let average = started.isEmpty ? 0 : started.map(\.words).reduce(0, +) / started.count
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Daily Average")
                        .foregroundStyle(.secondary)
                    Text(StatusText.counted(average, "word"))
                        .font(.largeTitle)
                        .monospacedDigit()
                }
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach(ActivityPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Chart {
                ForEach(shown, id: \.start) { day in
                    BarMark(
                        x: .value("Day", day.start, unit: .day), y: .value("Words", day.words),
                        width: .ratio(PageMetrics.barWidthRatio)
                    )
                    .cornerRadius(PageMetrics.barCornerRadius)
                    .foregroundStyle(.tint)
                }
                // No "average" label on the line: at the right end it covers today's bar, and the headline names it.
                if average > 0 {
                    RuleMark(y: .value("Daily average", average))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(PageMetrics.averageLine)
                }
            }
            .chartXAxis {
                switch period {
                case .week:
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true, anchor: .top)
                    }
                case .month:
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .topLeading)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine()
                    AxisValueLabel(anchor: .leading)
                }
            }
            .frame(height: PageMetrics.chartHeight)
            .accessibilityLabel("Words per day")
        }
    }

    /// The period's days from the first dictation on, at least a week of them, today last.
    static func shown(_ days: [DictationInsights.Day], period: ActivityPeriod) -> [DictationInsights.Day] {
        let recent = days.suffix(period.dayCount)
        let started = recent.drop { $0.words == 0 }.count
        return Array(recent.suffix(max(started, ActivityPeriod.week.dayCount)))
    }
}
