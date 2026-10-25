import Foundation
import KotobaCore
import KotobaStorage

// MARK: - Snapshots

@MainActor
extension Pane {
    /// Home in use (ready, today's words, five dictations), set up with nothing dictated yet, a new install with no key,
    /// and a last dictation that was not transcribed.
    static func homeSnapshots() -> [Snapshot] {
        [
            MainWindow.snapshot(of: .home(.sample), named: "home", height: 900),
            MainWindow.snapshot(of: .home(.sampleReady), named: "home-ready"),
            MainWindow.snapshot(of: .home(.sampleNew), named: "home-new"),
            MainWindow.snapshot(of: .home(.sampleFailed), named: "home-failed", height: 900),
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

    private static func sample(_ rows: [DictationRecord] = HistoryController.sampleRows()) -> HomeModel {
        let recent = Array(rows.prefix(recentCount))
        return HomeModel(
            readiness: .sample(), chords: HotkeyChords(defaults: nil),
            figures: Figures(
                insights: ActivityModel.sampleInsights, recent: recent, lastDelivered: rows.first(where: \.hasText)?.id,
                retryable: HistoryModel.kept(recent)))
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
