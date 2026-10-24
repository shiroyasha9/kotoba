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

/// The day bars of Activity's chart and of Home's today card: one bar shape for both, always in the brand colour, as
/// Screen Time's charts keep their own colours whatever the accent. All four corners rounded and no base line, as
/// Screen Time's (review-window.md T6).
struct DayBars: ChartContent {
    let days: ChartDays
    /// Home's today card, as Screen Time's week: today in the brand colour, the other days muted, an empty day after the
    /// first dictation as a stub on the base line so the week does not look broken.
    var marksToday = false

    var body: some ChartContent {
        ForEach(days.slots, id: \.start) { day in
            if !days.started.contains(day) {
                // A blank slot before the first dictation: a bar of no height, so the slot keeps its room.
                BarMark(x: .value("Day", day.start, unit: .day), y: .value("Words", 0))
                    .opacity(0)
            } else if marksToday && day.words == 0 {
                // A stub as tall as a bar's corner, standing on the base line.
                RectangleMark(
                    x: .value("Day", day.start, unit: .day), y: .value("Words", 0),
                    width: .ratio(PageMetrics.barWidthRatio), height: .fixed(PageMetrics.barStubHeight)
                )
                .offset(y: -PageMetrics.barStubLift)
                .clipShape(.capsule)
                .foregroundStyle(Color.brand.secondary)
            } else {
                BarMark(
                    x: .value("Day", day.start, unit: .day), y: .value("Words", day.words),
                    width: .ratio(PageMetrics.barWidthRatio)
                )
                .clipShape(.rect(cornerRadius: PageMetrics.barCornerRadius, style: .continuous))
                .foregroundStyle(
                    marksToday && day.start != days.slots.last?.start
                        ? AnyShapeStyle(Color.brand.secondary) : AnyShapeStyle(Color.brand))
            }
        }
    }
}
