import AppKit
import KotobaCore
import KotobaStorage
import Observation

/// What Home shows: whether kotoba is ready, today's words and the week's bars, the chords and the newest dictations.
/// Built with each main window; it reads the history while Home is shown (`PaneReader`), so nothing runs at idle or while another
/// pane is shown.
@MainActor
@Observable
final class HomeModel {
    struct Figures: Equatable {
        /// Activity's figures; Home shows today's words, the time they saved, the streak and the week's bars.
        var insights: DictationInsights
        /// Newest first, at most `recentCount`, as History reads them.
        var recent: [DictationRecord]
        /// The newest dictation that reached the owner, which "Fix…" fixes (`LastDictation`); nil before the first.
        var lastDelivered: DictationID?
        /// The rows of `recent` whose audio waits for a retry, as History marks them (`HistoryModel.kept`).
        var retryable: Set<DictationID> = []
        /// Every dictation that waits for a retry, as the menu's Retry counts them: the credit card's Send button.
        var waitingCount = 0
    }

    /// What Home does. The snapshot run passes none and sets the figures itself.
    struct Source {
        /// The Insights figures at `now`: a scan of the whole ledger (20 ms at 10,000 dictations).
        var readInsights: @MainActor (_ now: Date) async throws -> DictationInsights
        /// The newest dictations, at most `recentCount`, and the newest one that reached the owner.
        var readRows: @MainActor () async throws -> (recent: [DictationRecord], lastDelivered: DictationID?)
        var copy: @MainActor (String) async -> Void
        /// Paste Again (`PasteAgain`): false when nothing was pasted and the text is on the clipboard.
        var paste: @MainActor (String, DictationID) async -> Bool
        /// The dictations that wait for a retry, all of them (`HistoryStore.pendingCount`).
        var readWaitingCount: @MainActor () async throws -> Int
        /// Retry on a dictation whose audio waits for one, as History's (`DictationPipeline.retry`).
        var retry: @MainActor (Set<DictationID>) async -> Void
        /// Sends every saved dictation, as the menu's Retry (`DictationPipeline.retryPending`).
        var sendSaved: @MainActor () async -> Void
        /// Opens the Fix window on the last dictation.
        var fixLast: @MainActor () -> Void
        /// "Finish Setting Up kotoba…": onboarding on the first missing step, or the Speech pane.
        var finishSetup: @MainActor () -> Void
        /// "Try It…" before the first dictation: onboarding's Try It step.
        var tryIt: @MainActor () -> Void
    }

    /// The last dictation and the 4 before it (docs/research/ui-redesign.md, "Page map").
    static let recentCount = 5

    /// Observed: a grant or a saved key changes the status line at once.
    let readiness: Readiness
    let chords: HotkeyChords
    let reader: PaneReader<Figures>
    let apps = InstalledApps()
    private let source: Source?
    /// Nil for snapshots.
    private let reads: Reads?
    /// Which chart day is today, and what the rows' dates count from.
    private let now: @MainActor () -> Date
    /// The last Copy or Paste Again, which ends at once or within `PasteAgain`'s bound; the next one replaces it.
    @ObservationIgnored private var sending: Task<Void, Never>?
    /// Paste Again could not bring back the app the owner was in.
    var isPasteFailureShown = false
    /// The credit card's Send, which ends once each saved dictation got its answer.
    @ObservationIgnored private var sendingSaved: Task<Void, Never>?
    /// `sendingSaved` runs.
    private(set) var isSendingSaved = false
    /// Which dictations are being sent, and whether Paste Again can paste (`DictationPipeline.activity`).
    var activity = PipelineActivity(isQuiet: true, inFlight: [])

    init(readiness: Readiness, chords: HotkeyChords, source: Source, activity: PipelineActivity) {
        self.readiness = readiness
        self.activity = activity
        self.chords = chords
        self.source = source
        now = { .now }
        let reads = Reads(source: source)
        self.reads = reads
        reader = PaneReader("Home") { try await reads.read(at: .now) }
    }

    /// For snapshots: fixed figures, no store, at `Snapshots.sampleNow`.
    init(readiness: Readiness, chords: HotkeyChords, figures: Figures) {
        self.readiness = readiness
        self.chords = chords
        source = nil
        reads = nil
        now = { Snapshots.sampleNow }
        reader = PaneReader(value: figures)
    }

    /// Words today: the last chart day's when it is today.
    var todayWords: Int {
        reader.value?.insights.days.last.flatMap {
            Calendar.current.isDate($0.start, inSameDayAs: now()) ? $0.words : nil
        } ?? 0
    }

    /// When a dictation was, as Mail dates its rows: the time today, "Yesterday", the weekday within the week, the
    /// date before (`DayText.row`).
    func when(_ record: DictationRecord) -> String {
        DayText.row(of: record.createdAt, now: now())
    }

    /// The history was written: a shown Home reads again, the rows alone when the write left the figures as they were
    /// (the pending save at upload start, a status change).
    func historyChanged(_ change: HistoryChange) {
        if change.isInsightsChanged { reads?.insightsChanged() }
        if change.isRowChanged || change.isUsageAdded { reader.changed() }
    }

    func copy(_ record: DictationRecord) {
        guard let source, let text = record.latestText else { return }
        sending = Task { await source.copy(text) }
    }

    /// While a dictation records or is sent, Paste Again would race its paste.
    func canPasteAgain(_ record: DictationRecord) -> Bool {
        activity.isQuiet && record.hasText
    }

    func pasteAgain(_ record: DictationRecord) {
        guard let source, canPasteAgain(record), let text = record.latestText else { return }
        sending = Task {
            if await !source.paste(text, record.id) {
                isPasteFailureShown = true
            }
        }
    }

    /// A dictation whose audio waits for a retry, and that is not being sent now.
    func canRetry(_ record: DictationRecord) -> Bool {
        reader.value?.retryable.contains(record.id) == true && !activity.inFlight.contains(record.id)
    }

    func retry(_ record: DictationRecord) {
        guard let source, canRetry(record) else { return }
        sending = Task { await source.retry([record.id]) }
    }

    /// The credit card's Send: every saved dictation, once credit is back.
    func sendSaved() {
        guard let source, !isSendingSaved else { return }
        isSendingSaved = true
        sendingSaved = Task {
            await source.sendSaved()
            isSendingSaved = false
        }
    }

    func fixLast() {
        source?.fixLast()
    }

    func finishSetup() {
        source?.finishSetup()
    }

    func tryIt() {
        source?.tryIt()
    }
}

extension HomeModel {
    /// Reads Home's figures, with the Insights scan only when a write could change them or the day changed: the scan
    /// runs on the store actor that the next dictation's save needs.
    @MainActor
    private final class Reads {
        private let readInsights: @MainActor (_ now: Date) async throws -> DictationInsights
        private let readRows: @MainActor () async throws -> (recent: [DictationRecord], lastDelivered: DictationID?)
        private let readWaitingCount: @MainActor () async throws -> Int
        private var isInsightsDue = true
        private var insights: (value: DictationInsights, day: Date)?

        init(source: Source) {
            readInsights = source.readInsights
            readRows = source.readRows
            readWaitingCount = source.readWaitingCount
        }

        func insightsChanged() {
            isInsightsDue = true
        }

        func read(at now: Date) async throws -> Figures {
            async let rows = readRows()
            async let waitingCount = readWaitingCount()
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
            let (recent, lastDelivered) = try await rows
            return Figures(
                insights: current, recent: recent, lastDelivered: lastDelivered, retryable: HistoryModel.kept(recent),
                waitingCount: try await waitingCount)
        }
    }
}
