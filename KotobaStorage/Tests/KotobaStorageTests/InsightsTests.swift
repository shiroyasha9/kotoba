import Foundation
import KotobaCore
import Testing

@testable import KotobaStorage

/// The Insights figures, from the usage ledger and the dictionary's learned words, in a fixed calendar.
struct InsightsTests {
    let folder = TemporaryFolder()

    static let notes = DictationApp(bundleID: "com.apple.Notes", name: "Notes")
    static let mail = DictationApp(bundleID: "com.apple.mail", name: "Mail")

    /// India has no clock changes; weeks start on Monday.
    static let india: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    func makeStore() throws -> HistoryStore {
        try HistoryStore(url: folder.url.appending(path: "kotoba.sqlite"), audio: folder.url)
    }

    func date(_ month: Int, _ day: Int, _ hour: Int = 12, minute: Int = 0, in calendar: Calendar = india) throws
        -> Date
    {
        try #require(
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)))
    }

    /// A speech answer that delivered `words`, or with no words (a rejected try) when zero.
    func speech(
        at time: Date, words: Int = 30, audio: Duration = .seconds(15), for dictation: DictationID = DictationID(),
        app: DictationApp? = nil
    ) -> UsageEntry {
        UsageEntry(
            time: time, dictation: dictation, kind: .speech, model: "microsoft/mai-transcribe-2", audio: audio,
            deliveredWords: words, spokenWords: words, cost: nil, app: app)
    }

    @Test func anEmptyLedgerHasNoInsights() async throws {
        let insights = try await makeStore().insights(at: try date(10, 14), in: Self.india)

        #expect(insights == DictationInsights())
        #expect(insights.wordsPerMinute == nil)
    }

    /// Words count as History counts them (a cleanup's change included); speed counts only answers with words.
    @Test func totalsSplitByWeekAndMonthAndSpeedIsSpokenWordsPerMinuteOfAudio() async throws {
        let store = try makeStore()
        let cleaned = DictationID()
        try await store.addUsage([
            speech(at: try date(10, 13), for: cleaned),
            UsageEntry(
                time: try date(10, 13), dictation: cleaned, kind: .cleanup, model: "google/gemini-3.5-flash-lite",
                deliveredWords: -4, cost: nil),
            speech(at: try date(10, 13), words: 0, audio: .seconds(5)),
            speech(at: try date(10, 5)),
            speech(at: try date(9, 20)),
        ])

        let insights = try await store.insights(at: try date(10, 14), in: Self.india)

        #expect(insights.dictations == 3)
        #expect(insights.wordsThisWeek == 26)
        #expect(insights.wordsThisMonth == 56)
        #expect(insights.words == 86)
        #expect(insights.spokenWords == 90)
        #expect(insights.speakingTime == .seconds(45))
        #expect(insights.wordsPerMinute == 120)
        // 86 words typed at 40 a minute take 129 s; speaking them took 45 s.
        #expect(insights.timeSaved(typingSpeed: 40) == .seconds(84))
    }

    @Test func todayCountsInTheStreakWhenItHasADictation() async throws {
        let store = try makeStore()
        try await store.addUsage([
            speech(at: try date(10, 14, 9)), speech(at: try date(10, 13, 23, minute: 59)),
            speech(at: try date(10, 12, 0)), speech(at: try date(10, 10)),
        ])

        let insights = try await store.insights(at: try date(10, 14, 18), in: Self.india)

        #expect(insights.streak == 3)
        #expect(insights.isTodayInStreak)
        #expect(insights.days.count == InsightsQuery.chartDays)
        #expect(insights.days.last == .init(start: try date(10, 14, 0), words: 30, dictations: 1))
        #expect(insights.days.first?.start == (try date(9, 15, 0)))
    }

    /// The streak goes on until today ends; a try with no words is no dictation.
    @Test func withoutADictationTodayTheStreakEndsYesterday() async throws {
        let store = try makeStore()
        try await store.addUsage([
            speech(at: try date(10, 14, 9), words: 0), speech(at: try date(10, 13)), speech(at: try date(10, 12)),
        ])

        let insights = try await store.insights(at: try date(10, 14, 18), in: Self.india)

        #expect(insights.streak == 2)
        #expect(!insights.isTodayInStreak)
        #expect(insights.days.last?.dictations == 0)
    }

    /// Past the chart's 30 days the streak reads a year at a time, until a day with no dictation.
    @Test func aStreakLongerThanTheChartCountsEveryDay() async throws {
        let store = try makeStore()
        let yesterday = try date(10, 13)
        try await store.addUsage(
            (0..<400).compactMap { day in
                Self.india.date(byAdding: .day, value: -day, to: yesterday).map { speech(at: $0) }
            })

        let insights = try await store.insights(at: try date(10, 14), in: Self.india)

        #expect(insights.streak == 400)
    }

    /// The day the clocks go forward has 23 hours: a dictation late that evening is still on that day.
    @Test func daysFollowTheLocalCalendarAcrossAClockChange() async throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let store = try makeStore()
        try await store.addUsage(
            try [7, 8, 9].map { speech(at: try date(3, $0, 23, minute: 30, in: newYork)) })

        let insights = try await store.insights(at: try date(3, 9, 23, minute: 45, in: newYork), in: newYork)

        #expect(insights.days.suffix(3).map(\.dictations) == [1, 1, 1])
        #expect(insights.days.suffix(3).map(\.start) == (try [7, 8, 9].map { try date(3, $0, 0, in: newYork) }))
        #expect(insights.streak == 3)
    }

    /// The day the clocks go back has 25 hours: a dictation late that evening is not on the next day.
    @Test func daysFollowTheLocalCalendarWhenTheClocksGoBack() async throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let store = try makeStore()
        try await store.addUsage(
            try [(10, 31), (11, 1), (11, 2)].map { speech(at: try date($0, $1, 23, minute: 30, in: newYork)) })

        let insights = try await store.insights(at: try date(11, 2, 23, minute: 45, in: newYork), in: newYork)

        #expect(insights.days.suffix(4).map(\.dictations) == [0, 1, 1, 1])
        #expect(insights.streak == 3)
    }

    /// A row dated after the end of this week or month (a clock set ahead) counts in all time only.
    @Test func weekAndMonthEndAtTheirLastDay() async throws {
        let store = try makeStore()
        try await store.addUsage([speech(at: try date(10, 14)), speech(at: try date(11, 20))])

        let insights = try await store.insights(at: try date(10, 14, 18), in: Self.india)

        #expect(insights.wordsThisWeek == 30)
        #expect(insights.wordsThisMonth == 30)
        #expect(insights.words == 60)
    }

    /// Deleting dictations leaves the ledger, and the figures, as they were.
    @Test func topAppsAreByWordsAndOutliveDeletedDictations() async throws {
        let store = try makeStore()
        var record = DictationRecord(
            id: DictationID(), createdAt: try date(10, 13),
            audio: RecordedAudio(file: folder.url.appending(path: "one.flac"), duration: .seconds(15)),
            transcript: "one two", model: "microsoft/mai-transcribe-2", status: .pasted, latency: LatencyLog())
        record.usage = [speech(at: try date(10, 13), words: 50, for: record.id, app: Self.mail)]
        try await store.save(record)
        try await store.addUsage([speech(at: try date(10, 12), app: Self.notes)])
        try await store.delete([record.id])

        let insights = try await store.insights(at: try date(10, 14), in: Self.india)

        #expect(insights.apps == [.init(app: Self.mail, words: 50), .init(app: Self.notes, words: 30)])
        #expect(insights.words == 80)
    }

    /// Learned words count while they stay in the dictionary: pending suggestions do not, a deleted word stops.
    @Test func learnedWordsAreTheAddedCorrectionsByOrigin() async throws {
        let store = try DictionaryStore(url: folder.url.appending(path: "dictionary.sqlite"))
        let now = try date(10, 14)
        let vercel = SuggestionCandidate(heard: "versel", corrected: "Vercel", proposes: .termAndRule, origin: .edit)
        let embra = SuggestionCandidate(heard: "ember", corrected: "embra", proposes: .term, origin: .edit)
        let xandor = SuggestionCandidate(heard: "zandor", corrected: "Xandor", proposes: .termAndRule, origin: .fix)
        let pending = SuggestionCandidate(heard: "supa base", corrected: "Supabase", proposes: .term, origin: .edit)
        let all = PersonalDictionary().adding(vercel).adding(embra).adding(xandor)
        try await store.save(all, recordingAdded: [vercel, embra, xandor], at: now)
        _ = try await store.record(pending, at: now)
        #expect(try await store.learnedWords() == [.edit: 2, .fix: 1])

        try await store.save(PersonalDictionary().adding(vercel).adding(xandor), at: now)

        #expect(try await store.learnedWords() == [.edit: 1, .fix: 1])
    }

    /// The cost the Insights pane pays when it opens, over 10,000 dictations in 70 days (a streak past the chart).
    /// Measured 2026-10-16 (debug build): about 15 ms. The bound is loose for other agents' builds on the same machine.
    @Test func insightsOf10000DictationsStayFast() async throws {
        let store = try makeStore()
        let now = try date(10, 14, 18)
        let apps = [Self.notes, Self.mail, DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), nil]
        for start in stride(from: 0, to: 10_000, by: 1_000) {
            try await store.addUsage(
                (start..<start + 1_000).map { index in
                    speech(at: now - Double(index) * 600, words: 13, audio: .seconds(8), app: apps[index % 4])
                })
        }
        let clock = ContinuousClock()
        var insights = DictationInsights()
        let time = try await clock.measure {
            insights = try await store.insights(at: now, in: Self.india)
        }

        #expect(insights.dictations == 10_000)
        #expect(insights.words == 130_000)
        #expect(insights.streak == 70)
        #expect(time < .milliseconds(150))
    }
}
