import AppKit
import Charts
import KotobaStorage
import SwiftUI

/// Words per day as Screen Time draws its daily use: the daily average as the headline, rounded bars in the brand
/// colour, the average as a dashed line in its own colour with "avg" in that colour in the axis column, the word counts
/// on the right, no grid lines (owner QA 1, Q10). A week shows its 7 days (`ChartDays`).
struct DailyWordsChart: View {
    let days: ChartDays
    let period: ActivityPeriod

    var body: some View {
        let average = days.average
        let top = days.top
        VStack(alignment: .leading) {
            ChartHeadline(label: "Daily Average", value: StatusText.counted(average, "word"))
            Chart {
                DayBars(days: days)
                if average > 0 {
                    RuleMark(y: .value("Daily average", average))
                        .foregroundStyle(Color.chartAverage)
                        .lineStyle(PageMetrics.dashedLine)
                }
            }
            .chartXAxis {
                switch period {
                case .week:
                    // A label under each day, as Screen Time's day initials.
                    AxisMarks(values: .stride(by: .day)) { value in
                        // Every slot keeps its mark, so Charts centres each label on its day; the mark after today has
                        // no label.
                        AxisValueLabel(centered: true, anchor: .top) {
                            if let date = value.as(Date.self), days.isLabelled(date) {
                                Text(date, format: .dateTime.weekday(.narrow))
                            }
                        }
                        .font(.body)
                    }
                case .month:
                    // A dashed line at each week's date, as Battery's, so a date points to its bar.
                    AxisMarks(values: Self.weekStarts(in: days)) {
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
                                .foregroundStyle(Color.chartAverage)
                        }
                        .font(.body)
                    }
                }
            }
            .frame(height: PageMetrics.chartHeight)
            .accessibilityLabel("Words per day")
        }
    }

    /// The start of each calendar week among the started days: where a month's date lines go.
    private static func weekStarts(in days: ChartDays) -> [Date] {
        let calendar = Calendar.current
        return days.started.map(\.start).filter {
            calendar.dateInterval(of: .weekOfYear, for: $0)?.start == $0
        }
    }

    /// 0, the middle and the top, less one that "avg" would overlap: a label less than one line of body text from the
    /// average yields to it. The distance is measured on the plot, which is the chart's height less its row of day
    /// labels (the 0.5.0 build measured on the whole height and let "20" sit on "avg", owner QA 1, Q10).
    @MainActor static func ticks(top: Int, clearOf average: Int) -> [Int] {
        let font = NSFont.preferredFont(forTextStyle: .body)
        let line = font.ascender - font.descender + font.leading
        let clearance = Double(top) * line / (PageMetrics.chartHeight - line)
        return [0, top / 2, top].filter { average == 0 || abs(Double($0 - average)) >= clearance }
    }
}
