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
        /// The rows of `recent` whose audio waits for a retry, as History marks them (`HistoryModel.kept`).
        var retryable: Set<DictationID> = []
    }

    /// What Home does. The snapshot run passes none and sets the figures itself.
    struct Source {
        /// The Insights figures at `now`: a scan of the whole ledger (20 ms at 10,000 dictations).
        var readInsights: @MainActor (_ now: Date) async throws -> DictationInsights
        /// The newest dictations, at most `recentCount`, and whether one reached the owner.
        var readRows: @MainActor () async throws -> (recent: [DictationRecord], hasLastDictation: Bool)
        var copy: @MainActor (String) async -> Void
        /// Opens the Fix window on the last dictation.
        var fixLast: @MainActor () -> Void
        /// "Finish Setting Up kotoba…": onboarding on the first missing step, or the Speech pane.
        var finishSetup: @MainActor () -> Void
    }

    /// The name and icon at the top of Home.
    struct Identity {
        var name: String
        var icon: NSImage

        /// This install's: "kotoba Dev" and the DEV icon in a development build.
        @MainActor static var running: Self {
            Self(name: Install.displayName, icon: NSApplication.shared.applicationIconImage)
        }

        /// The release's, for the README images: a development build carries the release icon too (`AppIcon`).
        @MainActor static var release: Self {
            guard let icon = NSImage(named: "AppIcon") else { preconditionFailure("The build has no release icon") }
            return Self(name: Install.releaseDisplayName, icon: icon)
        }
    }

    static let recentCount = 5

    /// Observed: a grant or a saved key changes the status line at once.
    let readiness: Readiness
    let chords: HotkeyChords
    let identity: Identity
    let reader: PaneReader<Figures>
    let apps = InstalledApps()
    private let source: Source?
    /// Nil for snapshots.
    private let reads: Reads?
    /// Which chart day is today.
    private let now: @MainActor () -> Date
    /// The last Copy, which a pasteboard write ends at once; the next Copy replaces it.
    private var copying: Task<Void, Never>?

    init(readiness: Readiness, chords: HotkeyChords, source: Source) {
        self.readiness = readiness
        self.chords = chords
        identity = .running
        self.source = source
        now = { .now }
        let reads = Reads(source: source)
        self.reads = reads
        reader = PaneReader("Home") { try await reads.read(at: .now) }
    }

    /// For snapshots: fixed figures, no store, at `Snapshots.sampleNow`.
    init(readiness: Readiness, chords: HotkeyChords, figures: Figures, identity: Identity = .running) {
        self.readiness = readiness
        self.chords = chords
        self.identity = identity
        source = nil
        reads = nil
        now = { Snapshots.sampleNow }
        reader = PaneReader(value: figures)
    }

    /// "0.3.0" from the bundle.
    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Words and dictations today: the last chart day when it is today.
    var today: DictationInsights.Day? {
        reader.value?.insights.days.last.flatMap { Calendar.current.isDate($0.start, inSameDayAs: now()) ? $0 : nil }
    }

    /// The history was written: a shown Home reads again, the rows alone when the write left the figures as they were
    /// (the pending save at upload start, a status change).
    func historyChanged(_ change: HistoryChange) {
        if change.isInsightsChanged { reads?.insightsChanged() }
        if change.isRowChanged || change.isUsageAdded { reader.changed() }
    }

    func copy(_ record: DictationRecord) {
        guard let source, let text = record.latestText else { return }
        copying = Task { await source.copy(text) }
    }

    func fixLast() {
        source?.fixLast()
    }

    func finishSetup() {
        source?.finishSetup()
    }
}

extension HomeModel {
    /// Reads Home's figures, with the Insights scan only when a write could change them or the day changed: the scan
    /// runs on the store actor that the next dictation's save needs.
    @MainActor
    private final class Reads {
        private let readInsights: @MainActor (_ now: Date) async throws -> DictationInsights
        private let readRows: @MainActor () async throws -> (recent: [DictationRecord], hasLastDictation: Bool)
        private var isInsightsDue = true
        private var insights: (value: DictationInsights, day: Date)?

        init(source: Source) {
            readInsights = source.readInsights
            readRows = source.readRows
        }

        func insightsChanged() {
            isInsightsDue = true
        }

        func read(at now: Date) async throws -> Figures {
            async let rows = readRows()
            let current: DictationInsights
            if !isInsightsDue, let insights, Calendar.current.isDate(insights.day, inSameDayAs: now) {
                current = insights.value
            } else {
                // A write during the scan sets it due again, so the next read scans again.
                isInsightsDue = false
                do {
                    current = try await readInsights(now)
                } catch {
                    isInsightsDue = true
                    throw error
                }
                insights = (current, now)
            }
            let (recent, hasLastDictation) = try await rows
            return Figures(
                insights: current, recent: recent, hasLastDictation: hasLastDictation,
                retryable: HistoryModel.kept(recent))
        }
    }
}
