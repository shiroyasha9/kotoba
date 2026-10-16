import Foundation
import KotobaCore

/// The History pane's sections: one per calendar day, in the rows' order.
extension HistoryModel {
    static func days(of rows: [DictationRecord]) -> [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        for row in rows {
            let start = calendar.startOfDay(for: row.createdAt)
            if days.last?.id == start {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(Day(id: start, title: title(of: start, calendar: calendar), rows: [row]))
            }
        }
        return days
    }

    /// "Today", "Yesterday", "Monday, 12 October", with the year when it is not this year.
    private static func title(of day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        return calendar.isDate(day, equalTo: .now, toGranularity: .year)
            ? day.formatted(style) : day.formatted(style.year())
    }
}
