import AppKit
import KotobaCore
import KotobaStorage

/// What Home shows: whether kotoba is ready, the chords, a few Insights figures and the newest dictations. Built with
/// each main window; it reads the history while Home is shown (`PaneReader`), so nothing runs at idle or while another
/// pane is shown.
@MainActor
final class HomeModel {
    struct Figures: Equatable {
        /// The Insights pane's figures; Home shows today, this week and the streak.
        var insights: DictationInsights
        /// Newest first, at most `recentCount`, as History reads them.
        var recent: [DictationRecord]
        /// A dictation reached the owner, so "Fix Last Dictation…" has something to fix (`LastDictation`).
        var hasLastDictation: Bool
    }

    /// What Home does. The snapshot run passes none and sets the figures itself.
    struct Source {
        var read: @MainActor (_ now: Date) async throws -> Figures
        var copy: @MainActor (String) async -> Void
        /// Opens the Fix window on the last dictation.
        var fixLast: @MainActor () -> Void
        /// "Finish Setting Up kotoba…": onboarding on the first missing step, or the Speech pane.
        var finishSetup: @MainActor () -> Void
    }

    static let recentCount = 5

    /// Observed: a grant or a saved key changes the status line at once.
    let readiness: Readiness
    let chords: HotkeyChords
    let reader: PaneReader<Figures>
    let apps = InstalledApps()
    private let source: Source?

    init(readiness: Readiness, chords: HotkeyChords, source: Source) {
        self.readiness = readiness
        self.chords = chords
        self.source = source
        reader = PaneReader("Home") { try await source.read(.now) }
    }

    /// For snapshots: fixed figures, no store.
    init(readiness: Readiness, chords: HotkeyChords, figures: Figures) {
        self.readiness = readiness
        self.chords = chords
        source = nil
        reader = PaneReader(value: figures)
    }

    /// "0.3.0" from the bundle.
    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Words and dictations today: the last chart day when it is today.
    var today: DictationInsights.Day? {
        reader.value?.insights.days.last.flatMap { Calendar.current.isDateInToday($0.start) ? $0 : nil }
    }

    /// The history was written: a shown Home reads again.
    func historyChanged() {
        reader.changed()
    }

    func copy(_ record: DictationRecord) {
        guard let source, let text = record.deliveredText else { return }
        Task { await source.copy(text) }
    }

    func fixLast() {
        source?.fixLast()
    }

    func finishSetup() {
        source?.finishSetup()
    }
}
