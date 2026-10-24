import Foundation
import KotobaCore
import KotobaStorage
import Observation
import SwiftUI

extension Pane {
    static func activity(_ model: ActivityModel) -> Self {
        Pane(id: .activity) {
            AnyView(ActivityPage(model: model))
        }
    }
}

/// What the Activity page shows (Insights and Usage in one; docs/research/ui-redesign.md, "Page map"): words per day,
/// speaking speed, streak, time saved, learned words, top apps and this month's spend. Built with each main window; it
/// reads the usage ledger and the dictionary while the page is shown (`PaneReader`): when it appears, after each write
/// to either and when the day changes, so nothing runs at idle.
@MainActor
@Observable
final class ActivityModel {
    struct Figures: Equatable {
        var insights: DictationInsights
        /// Words still in the dictionary that kotoba learned from the owner's corrections, by where they came from.
        var learned: [SuggestionCandidate.Origin: Int]
        /// This calendar month's words, audio and spend.
        var month: UsageSummary
    }

    /// The typing speed "Time saved" compares with, in words per minute.
    nonisolated static let typingSpeed = 40

    /// The chart's period.
    var period = ActivityPeriod.week
    /// The Advanced… sheet: spend by model.
    var isAdvancedShown = false
    @ObservationIgnored let reader: PaneReader<Figures>
    @ObservationIgnored let apps = InstalledApps()

    /// `read` gives the figures at a date.
    init(read: @escaping @MainActor (_ now: Date) async throws -> Figures) {
        reader = PaneReader("activity") { try await read(.now) }
    }

    /// For snapshots: fixed figures and no store.
    init(figures: Figures, period: ActivityPeriod = .week) {
        reader = PaneReader(value: figures)
        self.period = period
    }

    /// The ledger or the dictionary was written: a shown page reads again.
    func storeChanged() {
        reader.changed()
    }

    /// The month the page sums: the calendar month of `now`.
    static func monthStart(at now: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: now)?.start ?? now
    }
}

/// The chart's period: the Week/Month switch.
enum ActivityPeriod: CaseIterable, Hashable {
    case week
    case month

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }

    /// How many days the chart shows at most, today last.
    var dayCount: Int {
        switch self {
        case .week: ChartDays.week
        case .month: InsightsQuery.chartDays
        }
    }
}

extension DictationInsights {
    /// The line under the streak.
    var streakDetail: String {
        if isTodayInStreak { return "Including today" }
        return streak > 0 ? "Dictate today to keep it" : "Dictate today to start one"
    }

    /// The time saved by today's words: typed at `ActivityModel.typingSpeed`, less the time to say them at the owner's
    /// speaking speed, as Activity's "Time saved" counts all of them.
    var savedToday: Duration {
        let words = Double(days.last?.words ?? 0)
        let typing = words / Double(ActivityModel.typingSpeed)
        let speaking = wordsPerMinute.map { words / Double($0) } ?? 0
        return .seconds(max(Int(((typing - speaking) * 60).rounded()), 0))
    }
}
