import AppKit
import KotobaCore

extension HistoryController {
    /// The window's content at its default size: rows of each status over two days (yesterday's audio deleted), the
    /// empty history, and a search with no results. Synthetic text only. The toolbar and search field belong to the
    /// real window and are not in the images.
    static func snapshots() -> [Snapshot] {
        let panes = [
            ("history-rows", HistoryModel(rows: sampleRows())),
            ("history-empty", HistoryModel(rows: [])),
            ("history-no-results", HistoryModel(rows: [], search: "invoice")),
        ].map { name, model in
            Snapshots.fixedWindow(named: name, size: defaultSize) { HistoryView(model: model) }
        }
        return panes + windowSnapshots()
    }

    /// The whole window as the owner sees it: title bar, toolbar with its buttons and the search field, and a selected
    /// row: one with text (Copy, Paste Again and Delete on), a failed one (Retry and Delete on) and one with no audio
    /// (Delete on only). The run fails when the content needs more room than the window.
    private static func windowSnapshots() -> [Snapshot] {
        [("history-window", 0), ("history-window-failed", 2), ("history-window-no-audio", 5)].map { name, selected in
            windowSnapshot(named: name, selecting: selected)
        }
    }

    private static func windowSnapshot(named name: String, selecting selected: Int) -> Snapshot {
        Snapshots.window(named: name, contentSize: defaultSize) {
            let rows = sampleRows()
            let model = HistoryModel(rows: rows)
            model.selection = [rows[selected].id]
            return window(showing: model)
        }
    }

    private static func sampleRows() -> [DictationRecord] {
        let now = Date.now
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
        ]
    }
}
