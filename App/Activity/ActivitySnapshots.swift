import Foundation
import KotobaCore
import KotobaProviders
import KotobaStorage
import SwiftUI

// MARK: - Snapshots

@MainActor
extension Pane {
    /// Activity in use (week and month), a user who started three days ago, a new install, and the Advanced… sheet.
    static func activitySnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .activity(.sample()), named: "activity", height: 1_500),
            MainWindow.snapshot(of: .activity(.sample(period: .month)), named: "activity-month", height: 1_500),
            MainWindow.snapshot(of: .activity(.sampleStarted), named: "activity-started", height: 1_500),
            // Owner QA 1, Q10: one day of 17 words, so "avg" sat on the scale's "20".
            MainWindow.snapshot(of: .activity(.sampleFirstDay), named: "activity-first-day", height: 1_500),
            MainWindow.snapshot(of: .activity(.empty), named: "activity-empty"),
            MainWindow.sheetSnapshot(named: "activity-advanced") { SpendByModel(month: ActivityModel.sampleMonth) },
        ]
    }
}

extension ActivityModel {
    /// Two months of synthetic use: a streak that includes today, quiet weekends, four apps, a few learned words, and a
    /// month with a cleanup model, an estimated direct route and unpriced answers.
    static func sample(period: ActivityPeriod = .week) -> ActivityModel {
        ActivityModel(figures: sampleFigures, period: period)
    }

    /// Someone who started three days ago: the chart starts at their first dictation.
    static var sampleStarted: ActivityModel {
        var figures = sampleFigures
        let recent = [0, 0, 0, 0, 260, 410, 180]
        figures.insights.days = figures.insights.days.suffix(recent.count).enumerated().map { index, day in
            DictationInsights.Day(start: day.start, words: recent[index], dictations: recent[index] / 40)
        }
        return ActivityModel(figures: figures)
    }

    /// The first day: 17 words today, nothing before.
    static var sampleFirstDay: ActivityModel {
        var figures = sampleFigures
        figures.insights.days = figures.insights.days.enumerated().map { index, day in
            let isToday = index == figures.insights.days.count - 1
            return DictationInsights.Day(start: day.start, words: isToday ? 17 : 0, dictations: isToday ? 1 : 0)
        }
        return ActivityModel(figures: figures)
    }

    /// A new install: no dictations, nothing learned, nothing spent.
    static var empty: ActivityModel {
        ActivityModel(figures: Figures(insights: DictationInsights(), learned: [:], month: UsageSummary()))
    }

    static var sampleFigures: Figures {
        Figures(insights: sampleInsights, learned: [.edit: 14, .fix: 3], month: sampleMonth)
    }

    /// Thirty days of words, today last.
    static var sampleInsights: DictationInsights {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Snapshots.sampleNow)
        let words = [
            420, 610, 0, 0, 540, 720, 380, 655, 510, 90, 0, 830, 760, 590, 640, 470, 0, 0, 910, 680, 720, 560, 805,
            120, 0, 690, 740, 610, 880, 350,
        ]
        let days = words.enumerated().compactMap { index, count in
            calendar.date(byAdding: .day, value: index + 1 - words.count, to: today).map {
                DictationInsights.Day(start: $0, words: count, dictations: count / 40)
            }
        }
        return DictationInsights(
            dictations: 1_204, wordsThisWeek: 3_575, wordsThisMonth: 12_840, words: 48_310, spokenWords: 49_020,
            speakingTime: .seconds(20_850), streak: 5, isTodayInStreak: true, days: days,
            apps: [
                .init(app: DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), words: 21_480),
                .init(app: DictationApp(bundleID: "com.apple.mail", name: "Mail"), words: 11_906),
                .init(app: DictationApp(bundleID: "com.apple.Notes", name: "Notes"), words: 8_312),
                .init(app: DictationApp(bundleID: "com.apple.TextEdit", name: "TextEdit"), words: 4_120),
            ])
    }

    static var sampleMonth: UsageSummary {
        UsageSummary(
            dictations: 412, words: 18_734, audio: .seconds(7_890), cost: Decimal(26_243) / 100_000,
            isCostEstimated: true, unpricedAnswers: 3,
            models: [
                .init(
                    .speech, model: TranscriptionRoute.openRouterMAI.rawValue, cost: Decimal(20_413) / 100_000,
                    unpricedAnswers: 3),
                .init(.cleanup, model: CleanupModel.geminiFlashLite.rawValue, cost: Decimal(4_786) / 100_000),
                .init(
                    .speech, model: TranscriptionRoute.xaiGrok.rawValue, cost: Decimal(1_044) / 100_000,
                    isEstimated: true),
            ],
            apps: [
                .init(app: DictationApp(bundleID: "com.apple.Terminal", name: "Terminal"), words: 9_120),
                .init(app: DictationApp(bundleID: "com.apple.mail", name: "Mail"), words: 4_388),
                .init(app: DictationApp(bundleID: "com.apple.Notes", name: "Notes"), words: 3_016),
                .init(app: DictationApp(bundleID: "com.apple.TextEdit", name: "TextEdit"), words: 2_210),
            ])
    }
}
