import AppKit
import KotobaCore

extension HistoryController {
    /// The window's content at its default size: rows of each status over two days, the empty history, and a search
    /// with no results. Synthetic text only. The toolbar and search field belong to the real window and are not in the
    /// images.
    static func snapshots() -> [Snapshot] {
        let panes = [
            ("history-rows", HistoryModel(rows: sampleRows())),
            ("history-empty", HistoryModel(rows: [])),
            ("history-no-results", HistoryModel(rows: [], search: "invoice")),
        ].map { name, model in
            Snapshots.fixedWindow(named: name, size: defaultSize) { HistoryView(model: model) }
        }
        return panes + [windowSnapshot()]
    }

    /// The whole window as the owner sees it: title bar, toolbar with its buttons and the search field, and a selected
    /// failed row (so Retry and Delete are on). The run fails when the content needs more room than the window.
    private static func windowSnapshot() -> Snapshot {
        Snapshot(name: "history-window") {
            let rows = sampleRows()
            let model = HistoryModel(rows: rows)
            model.selection = [rows[2].id]
            return WindowImage(window: window(showing: model), contentSize: defaultSize)
        } check: { view in
            guard let content = (view as? WindowImage)?.shown.contentView else { return nil }
            let fitting = content.fittingSize
            return fitting.width > defaultSize.width + 0.5 || fitting.height > defaultSize.height + 0.5
                ? "the content needs \(fitting), the window is \(defaultSize)" : nil
        }
    }

    private static func sampleRows() -> [DictationRecord] {
        let now = Date.now
        // A file every Mac has stands in for kept audio, so the failed and cancelled rows read "audio saved".
        let kept = URL(filePath: "/System/Library/Sounds/Tink.aiff")
        func row(
            _ text: String?, minutesAgo: Double, seconds: Int, app: (String, String)?,
            status: DictationRecord.Status = .pasted
        ) -> DictationRecord {
            var record = DictationRecord(
                id: DictationID(), createdAt: now - minutesAgo * 60,
                audio: RecordedAudio(file: kept, duration: .seconds(seconds)),
                transcript: text, status: status, latency: LatencyLog())
            record.app = app.map { DictationApp(bundleID: $0.0, name: $0.1) }
            return record
        }
        var cleaned = row(
            "um so the plan is we ship the beta on friday", minutesAgo: 12, seconds: 9,
            app: ("com.apple.mail", "Mail"))
        cleaned.cleanedText = "The plan: we ship the beta on Friday."
        cleaned.mode = .cleanup
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
            row(
                "Thanks for the notes. I added two questions at the end of the doc, and I think the timeline in "
                    + "section three needs another week for testing on older Macs before we can commit to a date.",
                minutesAgo: 60 * 26, seconds: 21, app: ("com.apple.MobileSMS", "Messages")),
            row("See you at six.", minutesAgo: 60 * 27, seconds: 2, app: nil),
        ]
    }
}

/// Draws a real window, frame and toolbar included, which `Snapshots` cannot host as a subview. The window is never
/// ordered on screen; it takes the snapshot's appearance when drawn. Custom: AppKit has no offscreen window image.
private final class WindowImage: NSView {
    let shown: NSWindow

    init(window: NSWindow, contentSize: NSSize) {
        shown = window
        shown.setContentSize(contentSize)
        super.init(frame: NSRect(origin: .zero, size: shown.frame.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func draw(_ dirtyRect: NSRect) {
        shown.appearance = effectiveAppearance
        guard let frameView = shown.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        bitmap.draw(in: bounds)
    }
}
