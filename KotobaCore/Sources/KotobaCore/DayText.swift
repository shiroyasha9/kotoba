import Foundation

/// How the pages name a dictation's day, counted from `now` in `calendar` (its time zone and locale): History's day
/// titles, and the date on a row with no day title above it (Home), as Mail, Messages and Notes date their list rows.
public enum DayText {
    /// "Today", "Yesterday", "Monday, 12 October", with the year when it is not this year.
    public static func title(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        switch daysAgo(date, now: now, calendar: calendar) {
        case 0: return "Today"
        case 1: return "Yesterday"
        default:
            let style = format(calendar).weekday(.wide).day().month(.wide)
            return calendar.isDate(date, equalTo: now, toGranularity: .year)
                ? date.formatted(style) : date.formatted(style.year())
        }
    }

    /// "11:04 AM" today, "Yesterday", the weekday ("Friday") in the 6 days before, and the short date ("10/9/2026")
    /// before that or after today. A weekday of 7 days ago would read as today's.
    public static func row(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        switch daysAgo(date, now: now, calendar: calendar) {
        case 0: date.formatted(format(calendar, time: .shortened))
        case 1: "Yesterday"
        case 2...6: date.formatted(format(calendar).weekday(.wide))
        default: date.formatted(format(calendar, date: .numeric))
        }
    }

    /// Calendar days from `date`'s to `now`'s, so a dictation at 23:58 is yesterday's at 00:05. A components read
    /// asked for `.day` always has it.
    private static func daysAgo(_ date: Date, now: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
            ?? 0
    }

    private static func format(
        _ calendar: Calendar, date: Date.FormatStyle.DateStyle? = nil, time: Date.FormatStyle.TimeStyle? = nil
    ) -> Date.FormatStyle {
        Date.FormatStyle(
            date: date, time: time, locale: calendar.locale ?? .current, calendar: calendar,
            timeZone: calendar.timeZone)
    }
}
