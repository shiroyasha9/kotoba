// Insights pane memory spike: a status-item app that links the real Settings window and Insights pane over a temporary
// history of 10,000 synthetic dictations (12,000 ledger entries) and a temporary dictionary with 17 learned words. It
// opens Settings on the Insights pane at 32 s, the way `SettingsController` builds it, and closes it at 45 s. The two
// builds differ only in the chart (`build.sh`), so their difference is the cost of Swift Charts.
import AppKit
import SwiftUI

/// Stand-in for the App type the Insights pane uses, which pulls in the rest of the app.
enum StatusText {
    static func counted(_ count: Int, _ noun: String) -> String {
        String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
    }
}

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?
    let settings = SettingsWindow()
    var history: HistoryStore?
    var dictionary: DictionaryStore?
    weak var weakWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "spike")
        item.menu = NSMenu()
        self.item = item
        Task {
            await fill()
            Timer.scheduledTimer(withTimeInterval: 32, repeats: false) { _ in
                MainActor.assumeIsolated { self.open() }
            }
            Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
                MainActor.assumeIsolated { self.weakWindow?.close() }
            }
        }
    }

    /// 10,000 dictations of 13 words over the last 70 days in three apps, a cleanup on every fifth.
    func fill() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "insights-spike-\(UUID().uuidString)")
        do {
            let history = try HistoryStore(url: folder.appending(path: "kotoba.sqlite"), audio: folder)
            let dictionary = try DictionaryStore(url: folder.appending(path: "dictionary.sqlite"))
            let apps = [("com.apple.Notes", "Notes"), ("com.apple.mail", "Mail"), ("com.apple.Terminal", "Terminal")]
            var entries: [UsageEntry] = []
            for index in 0..<10_000 {
                let id = DictationID()
                let time = Date.now - Double(index) * 600
                let app = DictationApp(bundleID: apps[index % 3].0, name: apps[index % 3].1)
                entries.append(
                    UsageEntry(
                        time: time, dictation: id, kind: .speech, model: "microsoft/mai-transcribe-2",
                        audio: .seconds(8), deliveredWords: 13, spokenWords: 13,
                        cost: .reported(Decimal(222) / 1_000_000),
                        app: app))
                if index % 5 == 0 {
                    entries.append(
                        UsageEntry(
                            time: time, dictation: id, kind: .cleanup, model: "google/gemini-3.5-flash-lite",
                            deliveredWords: -1, cost: .reported(Decimal(300) / 1_000_000), app: app))
                }
            }
            for start in stride(from: 0, to: entries.count, by: 1_000) {
                try await history.addUsage(Array(entries[start..<min(start + 1_000, entries.count)]))
            }
            let learned = (0..<17).map {
                SuggestionCandidate(
                    heard: "heard\($0)", corrected: "Word\($0)", proposes: .term, origin: $0 < 14 ? .edit : .fix)
            }
            try await dictionary.save(
                learned.reduce(PersonalDictionary()) { $0.adding($1) }, recordingAdded: learned)
            self.history = history
            self.dictionary = dictionary
        } catch {
            print("fill failed: \(error)")
        }
    }

    /// As `SettingsController.panes()`: a new model per open. Prints the first read's time.
    func open() {
        guard let history, let dictionary else { return }
        let model = InsightsModel { now in
            let clock = ContinuousClock()
            let start = clock.now
            async let learned = dictionary.learnedWords()
            let figures = InsightsModel.Figures(
                history: try await history.insights(at: now, in: .current), learned: try await learned)
            print("read: \(clock.now - start), streak \(figures.history.streak), words \(figures.history.words)")
            return figures
        }
        settings.show([.insights(model)])
        weakWindow = NSApp.windows.first { $0.contentViewController != nil }
    }
}

// Line-buffered, so the read time reaches the log before measure.sh stops the process.
setvbuf(stdout, nil, _IOLBF, 0)
let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.run()
