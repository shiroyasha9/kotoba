import AppKit
import KotobaCore
import KotobaStorage
import Observation

/// What Home shows: whether kotoba is ready, the chords, a few Insights figures and the newest dictations. Built with
/// each main window; it reads the history when Home appears, and while Home is shown after each history write and when
/// the day changes, so nothing runs at idle or while another pane is shown.
@MainActor
@Observable
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
    private(set) var figures: Figures?
    private(set) var isLoadFailed = false

    @ObservationIgnored private let source: Source?
    /// The read in progress; a write during it asks for one more read after it, so a burst of writes costs at most two
    /// reads.
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var isReadDue = false
    @ObservationIgnored private var isShown = false
    @ObservationIgnored private var icons: [String: NSImage?] = [:]

    init(readiness: Readiness, chords: HotkeyChords, source: Source) {
        self.readiness = readiness
        self.chords = chords
        self.source = source
    }

    /// For snapshots: fixed figures, no store.
    init(readiness: Readiness, chords: HotkeyChords, figures: Figures) {
        self.readiness = readiness
        self.chords = chords
        self.figures = figures
        source = nil
    }

    /// "0.2.2" from the bundle.
    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Words and dictations today: the last chart day when it is today.
    var today: DictationInsights.Day? {
        figures?.insights.days.last.flatMap { Calendar.current.isDateInToday($0.start) ? $0 : nil }
    }

    // MARK: Reading

    /// Home appeared, or the owner asked to try again.
    func show() {
        isShown = true
        readiness.refresh()
        reload()
    }

    func hide() {
        isShown = false
        reading?.cancel()
        reading = nil
    }

    /// The history was written, or the day changed: a shown Home reads again; a hidden one reads when it appears.
    func historyChanged() {
        guard isShown else { return }
        reload()
    }

    private func reload() {
        guard let source else { return }
        guard reading == nil else {
            isReadDue = true
            return
        }
        reading = Task {
            repeat {
                isReadDue = false
                do {
                    let loaded = try await source.read(.now)
                    // `hide()` cancelled it; a newer read may already be running.
                    guard !Task.isCancelled else { return }
                    isLoadFailed = false
                    // Most writes change nothing Home shows: no redraw then.
                    if loaded != figures { figures = loaded }
                } catch {
                    guard !Task.isCancelled else { return }
                    Log.app.error("Cannot read Home: \(error)")
                    isLoadFailed = true
                }
            } while isReadDue && !Task.isCancelled
            // A cancelled read was already replaced by `hide()`, maybe by a newer one: leave that handle alone.
            if !Task.isCancelled { reading = nil }
        }
    }

    // MARK: Actions

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

    /// The app's icon from its bundle, read once per app while Home’s window is open; nil when it is not installed.
    func icon(for app: DictationApp?) -> NSImage? {
        guard let app else { return nil }
        if let icon = icons[app.bundleID] { return icon }
        let icon = InstalledApp.icon(of: app.bundleID)
        icons[app.bundleID] = icon
        return icon
    }
}
