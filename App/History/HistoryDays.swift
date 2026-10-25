import Foundation
import KotobaCore

/// The History page's sections: one per calendar day, in the rows' order.
extension HistoryModel {
    /// `now` decides which day is "Today".
    static func days(of rows: [DictationRecord], now: Date) -> [Day] {
        let calendar = Calendar.current
        var days: [Day] = []
        for row in rows {
            let start = calendar.startOfDay(for: row.createdAt)
            if days.last?.id == start {
                days[days.count - 1].rows.append(row)
            } else {
                days.append(Day(id: start, title: DayText.title(of: start, now: now, calendar: calendar), rows: [row]))
            }
        }
        return days
    }
}
