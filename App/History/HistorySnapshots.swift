import AppKit
import KotobaCore

@MainActor
extension Pane {
    /// The page at the window's detail size: rows of each status over two days (yesterday's audio deleted), the first
    /// row being transcribed again, the empty history, a search with no results, a read that failed, and a rewritten
    /// row; then View Changes. Synthetic text only. `windowSnapshots()` in
    /// App/Settings/SettingsSnapshots.swift draws the page in the whole window.
    static func historySnapshots() -> [Snapshot] {
        let rows = HistoryController.sampleRows()
        return [
            ("history-rows", HistoryModel(rows: rows)),
            ("history-transcribing-again", HistoryModel(rows: rows, transcribing: [rows[0].id])),
            ("history-empty", HistoryModel(rows: [])),
            ("history-no-results", HistoryModel(rows: [], search: "invoice")),
            ("history-load-failed", HistoryModel.loadFailed),
            ("history-rewritten", HistoryModel(rows: [HistoryController.samplePolished()] + rows)),
        ].map { name, model in
            MainWindow.snapshot(of: .history(model), named: name, height: 1_200)
        } + ChangesView.snapshots()
    }
}

@MainActor
extension Pane {
    /// History in the whole window at the smallest and the widest size (the default is `window-history-framed`): its
    /// cards and rows in the page column, the selection from card edge to card edge, the scroll bar at the window's
    /// edge (docs/research/history-width.md).
    static func historyWidthSnapshots() -> [Snapshot] {
        let sizes: [(String, NSSize)] = [
            ("small", NSSize(width: PageMetrics.minimumWindowSize.width, height: 532)),
            ("wide", NSSize(width: PageMetrics.maximumWindowWidth, height: PageMetrics.defaultWindowSize.height)),
        ]
        return sizes.map { suffix, size in
            MainWindow.windowSnapshot(
                of: samplePanes(), selecting: .history, named: "window-history-\(suffix)", size: size, isFramed: true)
        }
    }
}

extension HistoryController {
    /// A cleaned dictation that Rewrite rewrote, for History's rewritten row and View Changes.
    static func samplePolished() -> DictationRecord {
        var record = DictationRecord(
            id: DictationID(), createdAt: Snapshots.sampleNow - 60,
            audio: RecordedAudio(file: URL(filePath: "/System/Library/Sounds/Tink.aiff"), duration: .seconds(24)),
            transcript:
                "okay so I want you to look at the the webhook handler in src/billing/webhook.ts because I think "
                + "it's double counting refunds, and um don't touch the Stripe client",
            status: .pasted, latency: LatencyLog())
        record.cleanedText =
            "Okay, so I want you to look at the webhook handler in src/billing/webhook.ts, because I think it's "
            + "double counting refunds. And don't touch the Stripe client."
        record.output = .cleanup(.code)
        record.polishedText =
            "Look at the webhook handler in src/billing/webhook.ts. I think it double counts refunds. Don't touch "
            + "the Stripe client."
        record.app = DictationApp(bundleID: "com.apple.Terminal", name: "Terminal")
        return record
    }

    /// Rows of each status over two days, for the History and Home snapshots.
    static func sampleRows() -> [DictationRecord] {
        let now = Snapshots.sampleNow
        // A file every Mac has stands in for kept audio, so the failed and cancelled rows read "audio saved"; the row of 0
        // seconds is an orphan with no readable audio, which reads "No text" with no Retry.
        let kept = URL(filePath: "/System/Library/Sounds/Tink.aiff")
        func row(
            _ text: String?, minutesAgo: Double, seconds: Int, app: (String, String)?,
            status: DictationRecord.Status = .pasted, isAudioDeleted: Bool = false
        ) -> DictationRecord {
            var record = DictationRecord(
                id: DictationID(), createdAt: now - minutesAgo * 60,
                audio: RecordedAudio(file: kept, duration: .seconds(seconds)),
                transcript: text, status: status, latency: LatencyLog())
            record.app = app.map { DictationApp(bundleID: $0.0, name: $0.1) }
            record.isAudioDeleted = isAudioDeleted
            return record
        }
        var cleaned = row(
            "um so the plan is we ship the beta on friday", minutesAgo: 12, seconds: 9,
            app: ("com.apple.mail", "Mail"))
        cleaned.cleanedText = "The plan: we ship the beta on Friday."
        cleaned.output = .cleanup(.writing)
        return [
            row(
                "Move the standup to Thursday and ask the team to review the pull request before lunch.",
                minutesAgo: 3, seconds: 7, app: ("com.apple.Notes", "Notes")),
            cleaned,
            row(nil, minutesAgo: 25, seconds: 14, app: ("com.apple.Terminal", "Terminal"), status: .failed),
            row(
                "Run the migration on staging first, then check the logs for slow queries.", minutesAgo: 41,
                seconds: 6, app: ("com.apple.Terminal", "Terminal"), status: .recovered),
            row(nil, minutesAgo: 58, seconds: 3, app: ("com.apple.Safari", "Safari"), status: .cancelled),
            row(nil, minutesAgo: 66, seconds: 0, app: nil, status: .cancelled),
            row(
                "Thanks for the notes. I added two questions at the end of the doc, and I think the timeline in "
                    + "section three needs another week for testing on older Macs before we can commit to a date.",
                minutesAgo: 60 * 26, seconds: 21, app: ("com.apple.MobileSMS", "Messages"), isAudioDeleted: true),
            row("See you at six.", minutesAgo: 60 * 27, seconds: 2, app: nil, isAudioDeleted: true),
            // Answered while kotoba quit: saved, not pasted.
            row(
                "Book the room for the review.", minutesAgo: 60 * 28, seconds: 3, app: ("com.apple.Notes", "Notes"),
                status: .notPasted),
        ]
    }
}

@MainActor
extension Pane {
    /// History's rows when they come in after the page is on screen, as in the app: the first page is read after the
    /// window opens, a new dictation comes into an empty history, and Try Again reads after a failed read. The run fails
    /// when a row keeps a height that the list changes when asked to measure it again (owner QA 1, Q8: on the first
    /// open after launch, every row drew as one cut line until a page switch built the list again). No image: the check
    /// measures the rows again, which hides what it finds.
    static func historyArrivalChecks() -> [Snapshot] {
        ArrivingHistory.Arrival.allCases.map { arrival in
            var problem: String?
            var snapshot = Snapshot(name: "history-arrival-\(arrival.rawValue)") {
                let history = ArrivingHistory(arrival)
                let model = HistoryModel(source: history.source, audio: .sample())
                let panes: [Pane] = [.home(.sample), .history(model)]
                let window = MainWindow.window(
                    showing: MainView(panes: panes, selection: Selection(panes: panes, showing: .history)))
                window.setContentSize(PageMetrics.defaultWindowSize)
                // The page is on screen with what it shows first: its first read waits, or it came back empty or failed.
                ArrivingHistory.wait { history.isWaiting || model.isLoaded }
                Snapshots.settle()
                window.layoutIfNeeded()
                history.arrive(in: model)
                ArrivingHistory.wait { model.rows.count == history.rows.count }
                Snapshots.settle()
                window.layoutIfNeeded()
                // Measured here, before the run's fit check: a window's fitting size measures every row again.
                problem =
                    model.rows.count == history.rows.count
                    ? ArrivingHistory.staleRows(in: window)
                    : "\(model.rows.count) of \(history.rows.count) rows came in"
                window.close()
                return NSView()
            } check: { _ in
                problem
            }
            snapshot.hasImage = false
            return snapshot
        }
    }
}

/// A history whose rows come in while the page is shown, for `Pane.historyArrivalChecks`.
@MainActor
private final class ArrivingHistory {
    enum Arrival: String, CaseIterable {
        /// The first page comes in after the page is on screen.
        case firstOpen = "first-open"
        /// The first dictation comes into an empty history.
        case firstDictation = "first-dictation"
        /// Try Again after a read that failed.
        case tryAgain = "try-again"
    }

    private struct ReadFailed: Error {}

    private let arrival: Arrival
    private(set) var rows: [DictationRecord] = []
    private var isFailing = false
    private var isHeld = false
    private var held: CheckedContinuation<Void, Never>?

    /// The first read waits for `arrive`.
    var isWaiting: Bool { held != nil }

    /// Turns the run loop until `isDone`, for at most 2 s: a read's answer reaches the page a few turns later, and the
    /// bound stops a read that never answers (the check then names what did not come).
    static func wait(until isDone: () -> Bool) {
        let deadline = Date.now + 2
        while !isDone(), Date.now < deadline {
            RunLoop.main.run(mode: .default, before: .now + 0.01)
        }
    }

    /// What the page shows first: no rows yet (the first read waits), an empty history, or a failed read.
    init(_ arrival: Arrival) {
        self.arrival = arrival
        switch arrival {
        case .firstOpen:
            rows = HistoryController.sampleRows()
            isHeld = true
        case .firstDictation: rows = []
        case .tryAgain: isFailing = true
        }
    }

    /// The rows come in, as the app's history sends them.
    func arrive(in model: HistoryModel) {
        switch arrival {
        case .firstOpen:
            isHeld = false
            held?.resume()
            held = nil
        case .firstDictation:
            let record = HistoryController.sampleRows()[0]
            rows = [record]
            Task { await model.apply(.saved(record.id, isUsageAdded: false)) }
        case .tryAgain:
            isFailing = false
            rows = HistoryController.sampleRows()
            model.tryAgain()
        }
    }

    var source: HistoryModel.Source {
        HistoryModel.Source(
            page: { [self] _, after, _ in
                if isHeld {
                    await withCheckedContinuation { held = $0 }
                }
                if isFailing { throw ReadFailed() }
                return after == nil ? rows : []
            },
            record: { [self] id, _ in rows.first { $0.id == id } },
            delete: { _ in false }, retry: { _ in }, paste: { _, _ in false }, copy: { _ in },
            transcribeAgain: { _, _ in false }, otherSpeechModels: { [] }, fix: { _ in })
    }

    /// The rows of the page's list (the window's one table that selects several rows: not the sidebar, not the cards)
    /// whose height changes when the list measures them again; nil when none does.
    static func staleRows(in window: NSWindow) -> String? {
        func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }
        guard let content = window.contentView,
            let table = tables(in: content).first(where: \.allowsMultipleSelection)
        else {
            return "the page shows no list"
        }
        let rows = 0..<table.numberOfRows
        let heights = rows.map { table.rect(ofRow: $0).height }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: rows))
        Snapshots.settle()
        window.layoutIfNeeded()
        let stale = rows.filter { table.rect(ofRow: $0).height != heights[$0] }
        return stale.isEmpty
            ? nil
            : "rows \(stale) kept heights \(stale.map { heights[$0] }), measured again "
                + "\(stale.map { table.rect(ofRow: $0).height })"
    }
}
