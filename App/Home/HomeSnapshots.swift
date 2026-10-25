import Foundation
import KotobaCore
import KotobaStorage

// MARK: - Snapshots

@MainActor
extension Pane {
    /// Home in use (ready, today's words, five dictations), set up with nothing dictated yet, a new install with no key,
    /// a last dictation that was not transcribed, and out of credit with dictations saved and with none.
    static func homeSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .home(.sample), named: "home", height: 900),
            MainWindow.snapshot(of: .home(.sampleReady), named: "home-ready"),
            MainWindow.snapshot(of: .home(.sampleNew), named: "home-new"),
            MainWindow.snapshot(of: .home(.sampleFailed), named: "home-failed", height: 900),
            MainWindow.snapshot(of: .home(.sampleNoCredit(waiting: 3)), named: "home-no-credit", height: 900),
            MainWindow.snapshot(of: .home(.sampleNoCredit(waiting: 0)), named: "home-no-credit-none"),
        ]
    }
}

extension HomeModel {
    /// Five dictations, Activity's days and streak, so both pages agree.
    static var sample: HomeModel { sample() }

    /// Home in the README: only dictations with text.
    static var readme: HomeModel {
        sample(HistoryController.sampleRows().filter(\.hasText))
    }

    /// The newest dictation was not transcribed and waits for a retry: the card says so and offers Retry alone. The
    /// rows from the first one with no text on, so they stay newest first, as the store reads them.
    static var sampleFailed: HomeModel {
        sample(Array(HistoryController.sampleRows().drop(while: \.hasText)))
    }

    /// How long before `Snapshots.sampleNow` each of the five was, so the Earlier rows show each kind of date: a time
    /// today, "Yesterday", a weekday and a date.
    private static let sampleMinutesAgo: [Double] = [3, 40, 60 * 26, 60 * 24 * 3, 60 * 24 * 15]

    /// OpenRouter is out of credit, with `waiting` dictations saved: the newest ones, waiting for it.
    static func sampleNoCredit(waiting: Int) -> HomeModel {
        let rows = HistoryController.sampleRows()
        return sample(
            waiting > 0 ? Array(rows.drop(while: \.hasText)) : rows.filter(\.hasText),
            readiness: .sample(outOfCredit: .openRouter),
            waiting: waiting)
    }

    private static func sample(
        _ rows: [DictationRecord] = HistoryController.sampleRows(), readiness: Readiness = .sample(), waiting: Int = 0
    ) -> HomeModel {
        let recent = zip(rows.prefix(recentCount), sampleMinutesAgo).map { row, minutesAgo in
            var row = row
            row.createdAt = Snapshots.sampleNow - minutesAgo * 60
            return row
        }
        return HomeModel(
            readiness: readiness, chords: HotkeyChords(defaults: nil),
            figures: Figures(
                insights: ActivityModel.sampleInsights, recent: recent, lastDelivered: rows.first(where: \.hasText)?.id,
                retryable: HistoryModel.kept(recent), waitingCount: waiting))
    }

    /// Set up, nothing dictated yet.
    static var sampleReady: HomeModel {
        HomeModel(
            readiness: .sample(), chords: HotkeyChords(defaults: nil),
            figures: Figures(insights: DictationInsights(), recent: [], lastDelivered: nil))
    }

    /// A first launch: no OpenRouter key yet, nothing dictated.
    static var sampleNew: HomeModel {
        HomeModel(
            readiness: .sample(missingSetup: (.key, .openRouter)), chords: HotkeyChords(defaults: nil),
            figures: Figures(insights: DictationInsights(), recent: [], lastDelivered: nil))
    }
}
