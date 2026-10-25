import Foundation
import Testing

@testable import KotobaCore

/// A dictation's day as Home's rows and History's day titles name it, counted from a fixed `now`.
struct DayTextTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = .gmt
        return calendar
    }()

    /// A day in the calendar's time zone; the 24th of October 2026, a Saturday, is `now`'s.
    private static func date(day: Int = 24, month: Int = 10, year: Int = 2026, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
            ?? .distantPast
    }

    private static let now = date(hour: 15, minute: 30)

    private static func row(_ date: Date, now: Date = now) -> String {
        DayText.row(of: date, now: now, calendar: calendar)
    }

    /// The system's time format puts a narrow no-break space before AM.
    @Test func todayShowsTheTime() {
        #expect(Self.row(Self.date(hour: 11, minute: 4)) == "11:04\u{202F}AM")
        #expect(Self.row(Self.date(hour: 0, minute: 1)) == "12:01\u{202F}AM")
    }

    @Test func yesterdayShowsYesterday() {
        #expect(Self.row(Self.date(day: 23, hour: 18)) == "Yesterday")
        #expect(Self.row(Self.date(day: 23, hour: 0)) == "Yesterday")
    }

    @Test func theSixDaysBeforeShowTheWeekday() {
        #expect(Self.row(Self.date(day: 21, hour: 9)) == "Wednesday")
        #expect(Self.row(Self.date(day: 18, hour: 9)) == "Sunday")
    }

    /// 7 days ago is the same weekday as today, so it shows the date.
    @Test func aWeekAgoAndBeforeShowTheDate() {
        #expect(Self.row(Self.date(day: 17, hour: 20)) == "10/17/2026")
        #expect(Self.row(Self.date(day: 10, hour: 9)) == "10/10/2026")
        #expect(Self.row(Self.date(day: 3, month: 12, year: 2025, hour: 9)) == "12/3/2025")
    }

    /// Calendar days, not 24-hour spans: 7 minutes after midnight, 23:58 is yesterday and 00:01 is today.
    @Test func justAfterMidnight() {
        let now = Self.date(hour: 0, minute: 5)
        #expect(Self.row(Self.date(hour: 0, minute: 1), now: now) == "12:01\u{202F}AM")
        #expect(Self.row(Self.date(day: 23, hour: 23, minute: 58), now: now) == "Yesterday")
        #expect(Self.row(Self.date(day: 22, hour: 23, minute: 58), now: now) == "Thursday")
    }

    /// A clock set back leaves a dictation after today: its date, never a weekday that reads as past.
    @Test func afterTodayShowsTheDate() {
        #expect(Self.row(Self.date(day: 25, hour: 9)) == "10/25/2026")
    }

    @Test func dayTitles() {
        func title(_ date: Date) -> String { DayText.title(of: date, now: Self.now, calendar: Self.calendar) }
        #expect(title(Self.date(hour: 9)) == "Today")
        #expect(title(Self.date(day: 23, hour: 9)) == "Yesterday")
        #expect(title(Self.date(day: 12, hour: 9)) == "Monday, October 12")
        #expect(title(Self.date(day: 3, month: 12, year: 2025, hour: 9)) == "Wednesday, December 3, 2025")
    }
}
