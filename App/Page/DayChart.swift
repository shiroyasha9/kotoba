import Charts
import KotobaStorage
import SwiftUI

/// A chart card's headline, as Screen Time's "Daily Average": a label, the figure in Large Title, and an optional grey
/// line under it. Activity and Home's today card both draw it, so they cannot drift.
struct ChartHeadline: View {
    let label: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
            Text(value)
                .font(.largeTitle)
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The days a words-per-day chart shows: the last `count` days, today last, from the first dictation on (the chart
/// starts at the first dictation; review-window.md T5). A chart keeps at least a week's slots, so a new user's bars keep
/// a week bar's width; the slots before the first dictation stay blank, with no bar and no label.
struct ChartDays: Equatable {
    /// Every slot, oldest first, today last.
    let slots: [DictationInsights.Day]
    /// The slots from the first dictation on: the ones that get a bar and a label.
    let started: ArraySlice<DictationInsights.Day>

    /// A week's slots.
    static let week = 7

    init(_ days: [DictationInsights.Day], last count: Int) {
        let recent = days.suffix(count)
        let startedCount = recent.drop { $0.words == 0 }.count
        slots = Array(recent.suffix(max(startedCount, min(Self.week, recent.count))))
        started = slots.suffix(startedCount)
    }

    /// The scale's top: the largest day rounded up to its leading digit (910 to 1,000, 410 to 500).
    var top: Int {
        let largest = slots.map(\.words).max() ?? 0
        guard largest > 0 else { return 1 }
        let step = Int(pow(10, floor(log10(Double(largest)))))
        return (largest + step - 1) / step * step
    }

    /// A day that gets a label: one from the first dictation on. The marks stride by day over every slot, so Charts
    /// centres each label on its day.
    func isLabelled(_ date: Date) -> Bool {
        started.contains { Calendar.current.isDate($0.start, inSameDayAs: date) }
    }

    /// The average over the started days.
    var average: Int {
        started.isEmpty ? 0 : started.map(\.words).reduce(0, +) / started.count
    }
}

/// The day bars of Activity's chart: always in the brand colour, as Screen Time's charts keep their own colours whatever
/// the accent. All four corners rounded and no base line, as Screen Time's (review-window.md T6). Home's week draws the
/// same bar with shapes (`WeekBars`).
struct DayBars: ChartContent {
    let days: ChartDays

    var body: some ChartContent {
        ForEach(days.slots, id: \.start) { day in
            if !days.started.contains(day) {
                // A blank slot before the first dictation: a bar of no height, so the slot keeps its room.
                BarMark(x: .value("Day", day.start, unit: .day), y: .value("Words", 0))
                    .opacity(0)
            } else {
                BarMark(
                    x: .value("Day", day.start, unit: .day), y: .value("Words", day.words),
                    width: .ratio(PageMetrics.barWidthRatio)
                )
                .clipShape(DayBarShape())
                .foregroundStyle(Color.brand)
            }
        }
    }
}

/// A day bar's shape, in Activity's chart and Home's week: all four corners rounded, continuous.
struct DayBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: PageMetrics.barCornerRadius, style: .continuous).path(in: rect)
    }
}

/// The week's words on Home's today card, as Screen Time's week: Activity's bar (`DayBarShape`) with today in the brand
/// colour, the other days muted, an empty day after the first dictation as a stub on the base line so the week does not
/// look broken, the day initials under them and no word counts. It takes the height of the headline beside it.
/// Plain shapes, not Swift Charts: the window opens on Home, and its first chart cost about 108 MB of footprint
/// (measured with `make window-memory`, 2026-10-25), which Activity's axes and average line need and seven bars do not.
struct WeekBars: View {
    let days: ChartDays

    var body: some View {
        VStack(spacing: PageMetrics.weekLabelGap) {
            GeometryReader { plot in
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(days.slots, id: \.start) { day in
                        bar(day, plotHeight: plot.size.height)
                            .frame(width: plot.size.width / CGFloat(days.slots.count) * PageMetrics.barWidthRatio)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            HStack(spacing: 0) {
                ForEach(days.slots, id: \.start) { day in
                    Text(days.started.contains(day) ? day.start.formatted(.dateTime.weekday(.narrow)) : "")
                        .frame(maxWidth: .infinity)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        // Headroom over the tallest bar: the system's padding, so the bars stay level with the figure, not the label.
        .padding(.top)
        // No height of its own: it takes the height of the text beside it.
        .frame(maxWidth: .infinity, minHeight: 0, idealHeight: 0, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Words per day this week")
    }

    @ViewBuilder private func bar(_ day: DictationInsights.Day, plotHeight: CGFloat) -> some View {
        if !days.started.contains(day) {
            // A blank slot before the first dictation.
            Color.clear.frame(height: 0)
        } else if day.words == 0 {
            Capsule()
                .fill(Color.brand.secondary)
                .frame(height: PageMetrics.barStubHeight)
        } else {
            DayBarShape()
                .fill(
                    day.start == days.slots.last?.start
                        ? AnyShapeStyle(Color.brand) : AnyShapeStyle(Color.brand.secondary)
                )
                .frame(height: plotHeight * CGFloat(day.words) / CGFloat(days.top))
        }
    }
}
