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
                        side: PageMetrics.headerTileSide)
                }
            }
            Section {
                DailyWords(days: data.insights.days, period: period)
            } header: {
                // Above the chart card, outside it, so the card holds no control (owner, 2026-10-24); Battery puts its
                // period switch at the top of its charts. Centred: a segmented control does not stretch.
                HStack {
                    Spacer()
                    Picker("Period", selection: $period) {
                        ForEach(ActivityPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                }
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
                detail: "Speaking speed, pauses included")
            row(
                "Streak", "flame", .orange, value: StatusText.counted(insights.streak, "day"),
                detail: insights.streakDetail)
            row(
                "Time saved", "stopwatch", .green,
                value: Self.duration(insights.timeSaved(typingSpeed: InsightsModel.typingSpeed)),
                detail: "Compared with typing at \(InsightsModel.typingSpeed) words a minute")
            row(
                "Words learned", "text.badge.checkmark", .purple, value: learned.formatted(),
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
            // The facts stay on screen in the row (copy rules), not in a footer beside the button.
            PageRow(
                title: "Spend",
                subtitle: "What your speech and cleanup services billed. It stays when you delete dictations."
                    + (month.isCostEstimated ? " Partly estimated from list prices." : "")
            ) {
                Text(Self.dollars(month.cost))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Dictations", value: month.dictations.formatted())
            LabeledContent("Audio", value: Self.duration(month.audio))
        } header: {
            Text("This Month")
        } footer: {
            // Alone at the trailing edge under the group, as Battery's "Options…".
            HStack {
                Spacer()
                Button("Advanced…") {}
            }
        }
    }

    /// A highlight: a tile, a title with one line under it, and the figure.
    private func row(_ title: String, _ symbol: String, _ tint: Color, value: String, detail: String) -> some View {
        PageRow(title: title, subtitle: detail) {
            SymbolTile(systemImage: symbol, tint: tint, side: PageMetrics.rowTileSide)
        } trailing: {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
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
/// colour, the average as a line with "avg" in the axis column, the word counts on the right, no grid lines. The chart
/// starts at the first dictation: days before it are not drawn, but a week's seven slots stay so a new user's bars keep
/// their width.
struct DailyWords: View {
    let days: [DictationInsights.Day]
    let period: ActivityPeriod

    var body: some View {
        let shown = Self.shown(days, period: period)
        let started = shown.drop { $0.words == 0 }
        let average = started.isEmpty ? 0 : started.map(\.words).reduce(0, +) / started.count
        let top = Self.scaleTop(shown.map(\.words).max() ?? 0)
        VStack(alignment: .leading) {
            ChartHeadline(label: "Daily Average", value: StatusText.counted(average, "word"))
            Chart {
                DayBars(days: shown)
                if average > 0 {
                    RuleMark(y: .value("Daily average", average))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(PageMetrics.dashedLine)
                }
            }
            .chartXAxis {
                switch period {
                case .week:
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true, anchor: .top)
                            .font(.body)
                    }
                case .month:
                    // A dashed line at each date, as Battery's, so a date points to its bar.
                    AxisMarks(values: .stride(by: .weekOfYear)) {
                        AxisGridLine(stroke: PageMetrics.dashedLine)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .topLeading)
                            .font(.body)
                    }
                }
            }
            .chartYScale(domain: 0...top)
            .chartYAxis {
                // Labels only, as Screen Time: no grid line runs beside the average line.
                AxisMarks(position: .trailing, values: Self.ticks(top: top, clearOf: average)) {
                    AxisValueLabel(anchor: .leading)
                        .font(.body)
                }
                if average > 0 {
                    AxisMarks(position: .trailing, values: [average]) {
                        AxisValueLabel(anchor: .leading) {
                            Text("avg")
                        }
                        .font(.body)
                    }
                }
            }
            .frame(height: PageMetrics.chartHeight)
            .accessibilityLabel("Words per day")
        }
    }

    /// The scale's top: the largest day rounded up to its leading digit (910 to 1,000, 410 to 500).
    static func scaleTop(_ largest: Int) -> Int {
        guard largest > 0 else { return 1 }
        let step = Int(pow(10, floor(log10(Double(largest)))))
        return (largest + step - 1) / step * step
    }

    /// 0, the middle and the top, less one that "avg" would overlap: a label nearer the average than one line of body
    /// text on the chart's scale yields to it (Screen Time draws them on top of each other).
    @MainActor static func ticks(top: Int, clearOf average: Int) -> [Int] {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let line = font.ascender - font.descender + font.leading
        let clearance = Double(top) * line / PageMetrics.chartHeight
        return [0, top / 2, top].filter { average == 0 || abs(Double($0 - average)) >= clearance }
    }

    /// The period's days from the first dictation on, at least a week of them, today last.
    static func shown(_ days: [DictationInsights.Day], period: ActivityPeriod) -> [DictationInsights.Day] {
        let recent = days.suffix(period.dayCount)
        let started = recent.drop { $0.words == 0 }.count
        return Array(recent.suffix(max(started, ActivityPeriod.week.dayCount)))
    }
}

/// The day bars of Activity's chart and of Home's today card: one bar shape for both, always in the brand colour, as
/// Screen Time's charts keep their own colours whatever the accent.
struct DayBars: ChartContent {
    let days: [DictationInsights.Day]
    /// Home's today card, as Screen Time's week: today in the brand colour, the other days muted, an empty day as a
    /// stub on the base line so the week does not look broken.
    var marksToday = false

    var body: some ChartContent {
        ForEach(days, id: \.start) { day in
            if marksToday && day.words == 0 {
                // A stub as tall as a bar's corner, standing on the base line.
                RectangleMark(
                    x: .value("Day", day.start, unit: .day), y: .value("Words", 0),
                    width: .ratio(PageMetrics.barWidthRatio), height: .fixed(PageMetrics.barCornerRadius)
                )
                .offset(y: -PageMetrics.barCornerRadius / 2)
                .cornerRadius(PageMetrics.barCornerRadius / 2)
                .foregroundStyle(Color.brand.secondary)
            } else {
                BarMark(
                    x: .value("Day", day.start, unit: .day), y: .value("Words", day.words),
                    width: .ratio(PageMetrics.barWidthRatio)
                )
                .cornerRadius(PageMetrics.barCornerRadius)
                .foregroundStyle(
                    marksToday && day.start != days.last?.start
                        ? AnyShapeStyle(Color.brand.secondary) : AnyShapeStyle(Color.brand))
            }
        }
    }
}
