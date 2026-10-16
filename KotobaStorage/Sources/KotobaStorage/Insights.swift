import Foundation
import KotobaCore

/// How the owner dictates, for the Insights pane: summed from the usage ledger when the pane asks, never at idle. The
/// ledger outlives deleted dictations, so the figures do too. Days are the calendar's days (the local time zone).
public struct DictationInsights: Sendable, Equatable {
    /// One day of the chart.
    public struct Day: Sendable, Equatable {
        public var start: Date
        /// Delivered words, as History counts them.
        public var words: Int
        public var dictations: Int

        public init(start: Date, words: Int = 0, dictations: Int = 0) {
            self.start = start
            self.words = words
            self.dictations = dictations
        }
    }

    /// Dictations with a speech answer that had words: the ones that delivered text.
    public var dictations: Int
    /// Delivered words in the calendar week and month of `now`, and in all.
    public var wordsThisWeek: Int
    public var wordsThisMonth: Int
    public var words: Int
    /// Words the speech models heard, and the audio of those answers: recordings in full, pauses included.
    public var spokenWords: Int
    public var speakingTime: Duration
    /// Days in a row with a delivered dictation, up to today when today has one, else up to yesterday.
    public var streak: Int
    public var isTodayInStreak: Bool
    /// The last `InsightsQuery.chartDays` days, oldest first, today last.
    public var days: [Day]
    /// Most words first.
    public var apps: [UsageSummary.AppWords]

    public init(
        dictations: Int = 0, wordsThisWeek: Int = 0, wordsThisMonth: Int = 0, words: Int = 0, spokenWords: Int = 0,
        speakingTime: Duration = .zero, streak: Int = 0, isTodayInStreak: Bool = false, days: [Day] = [],
        apps: [UsageSummary.AppWords] = []
    ) {
        self.dictations = dictations
        self.wordsThisWeek = wordsThisWeek
        self.wordsThisMonth = wordsThisMonth
        self.words = words
        self.spokenWords = spokenWords
        self.speakingTime = speakingTime
        self.streak = streak
        self.isTodayInStreak = isTodayInStreak
        self.days = days
        self.apps = apps
    }

    /// Spoken words per minute of recorded audio; nil before any.
    public var wordsPerMinute: Int? {
        let minutes = speakingTime / .seconds(60)
        return minutes > 0 ? Int((Double(spokenWords) / minutes).rounded()) : nil
    }

    /// The time typing the delivered words at `typingSpeed` words per minute would take, less the time spent speaking
    /// them; zero when speaking took longer.
    public func timeSaved(typingSpeed: Int) -> Duration {
        max(.seconds(Double(words) / Double(typingSpeed) * 60) - speakingTime, .zero)
    }
}

extension HistoryStore {
    /// The figures at `now` in `calendar`: one scan of the ledger for the totals, one day-range read per chart day on
    /// its `time` index, the top apps, and for a streak longer than the chart one more read per year of it.
    public func insights(at now: Date, in calendar: Calendar, apps: Int = 5) throws -> DictationInsights {
        let week = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 0)
        let month = calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        let speech = "kind = '\(UsageEntry.Kind.speech.rawValue)' AND spoken_words > 0"
        let totals = try database.query(
            """
            SELECT count(DISTINCT CASE WHEN \(speech) THEN dictation_id END),
                coalesce(sum(CASE WHEN time >= ?1 AND time < ?2 THEN words END), 0),
                coalesce(sum(CASE WHEN time >= ?3 AND time < ?4 THEN words END), 0), coalesce(sum(words), 0),
                coalesce(sum(CASE WHEN \(speech) THEN spoken_words END), 0),
                coalesce(sum(CASE WHEN \(speech) THEN audio_ms END), 0),
                min(CASE WHEN \(speech) THEN time END)
            FROM usage_ledger;
            """, [week.start, week.end, month.start, month.end].map { .real($0.timeIntervalSince1970) })
        guard let row = totals.first, let count = row[0].integer, count > 0, case .real(let first) = row[6] else {
            return DictationInsights()
        }
        let today = calendar.startOfDay(for: now)
        let days = try self.days(InsightsQuery.chartDays, endingAt: today, in: calendar)
        let isTodayInStreak = days.last?.dictations ?? 0 > 0
        let streak = try self.streak(
            from: isTodayInStreak ? days : days.dropLast(), since: Date(timeIntervalSince1970: first), in: calendar)
        let number = { (index: Int) in Int(row[index].integer ?? 0) }
        return DictationInsights(
            dictations: number(0), wordsThisWeek: number(1), wordsThisMonth: number(2), words: number(3),
            spokenWords: number(4), speakingTime: .milliseconds(number(5)), streak: streak,
            isTodayInStreak: isTodayInStreak, days: days,
            apps: try topApps(from: nil, to: nil, limit: apps))
    }

    /// Counts back from the newest of `recent` (the days before today, or up to today) to the first day with no
    /// delivered dictation, reading a year further back each time the run reaches the oldest day read, until `first`.
    private func streak(
        from recent: some Collection<DictationInsights.Day>, since first: Date, in calendar: Calendar
    ) throws -> Int {
        var streak = 0
        var read = Array(recent)
        while true {
            let run = read.reversed().prefix { $0.dictations > 0 }.count
            streak += run
            guard run == read.count, let oldest = read.first?.start, oldest > first else { return streak }
            read = try days(InsightsQuery.streakDays, endingAt: oldest, in: calendar).dropLast()
        }
    }

    /// The `count` calendar days that end with the day starting at `last`, oldest first: one statement with a range
    /// read per day on the ledger's `time` index, so a day of 23 or 25 hours (a clock change) counts right.
    private func days(_ count: Int, endingAt last: Date, in calendar: Calendar) throws -> [DictationInsights.Day] {
        // Each start again from `startOfDay`: where a clock change skips midnight, a day starts at 1:00.
        let starts = (0...count).reversed().compactMap {
            calendar.date(byAdding: .day, value: 1 - $0, to: last).map(calendar.startOfDay(for:))
        }
        let rows = (1..<starts.count).map { "(?\($0 * 2 - 1), ?\($0 * 2))" }.joined(separator: ", ")
        let values = zip(starts, starts.dropFirst()).flatMap { start, end -> [Value] in
            [.real(start.timeIntervalSince1970), .real(end.timeIntervalSince1970)]
        }
        return try database.query(
            """
            WITH days (day_start, day_end) AS (VALUES \(rows))
            SELECT day_start, coalesce(sum(words), 0),
                count(DISTINCT CASE WHEN kind = '\(UsageEntry.Kind.speech.rawValue)' AND spoken_words > 0
                    THEN dictation_id END)
            FROM days LEFT JOIN usage_ledger ON time >= day_start AND time < day_end
            GROUP BY day_start ORDER BY day_start;
            """, values
        ).compactMap { row in
            guard case .real(let start) = row[0] else { return nil }
            return DictationInsights.Day(
                start: Date(timeIntervalSince1970: start), words: Int(row[1].integer ?? 0),
                dictations: Int(row[2].integer ?? 0))
        }
    }
}

/// How far the Insights reads go back.
public enum InsightsQuery {
    /// Days in the chart, today included.
    public static let chartDays = 30
    /// Days read in one statement while a streak goes on past the chart.
    static let streakDays = 365
}
