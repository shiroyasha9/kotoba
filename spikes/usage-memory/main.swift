// Usage pane memory spike: a status-item app that links the real Settings window and Usage pane (WITH_USAGE) over a
// temporary history of 10,000 synthetic dictations (12,000 ledger entries). It opens Settings on the Usage pane at 32 s, the way
// `SettingsController` builds it, and closes it at 45 s. Without WITH_USAGE it is the same app with no SwiftUI.
// `--leak-check`: open at 1 s, close at 2 s, then print whether the window, its hosting controller and the model were
// deallocated, and quit.
import AppKit

#if WITH_USAGE
    import SwiftUI

    /// Stand-in for the App type the Usage pane uses, which pulls in the rest of the app.
    enum StatusText {
        static func counted(_ count: Int, _ noun: String) -> String {
            String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
        }
    }
#endif

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?
    #if WITH_USAGE
        let settings = SettingsWindow()
        var store: HistoryStore?
        weak var weakWindow: NSWindow?
        weak var weakHost: NSViewController?
        weak var weakModel: UsageModel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "spike")
        item.menu = NSMenu()
        self.item = item
        #if WITH_USAGE
            let isLeakCheck = CommandLine.arguments.contains("--leak-check")
            Task {
                await fill()
                Timer.scheduledTimer(withTimeInterval: isLeakCheck ? 1 : 32, repeats: false) { _ in
                    MainActor.assumeIsolated { self.open() }
                }
                Timer.scheduledTimer(withTimeInterval: isLeakCheck ? 2 : 45, repeats: false) { _ in
                    MainActor.assumeIsolated { self.weakWindow?.close() }
                }
                guard isLeakCheck else { return }
                Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
                    MainActor.assumeIsolated {
                        print(
                            "2 s after close, still alive: window \(self.weakWindow != nil), host \(self.weakHost != nil), "
                                + "model \(self.weakModel != nil)")
                        exit(0)
                    }
                }
            }
        #endif
    }

    #if WITH_USAGE
        /// 10,000 dictations of 13 words over the last 70 days, in three apps, two speech models and a cleanup model.
        func fill() async {
            let folder = FileManager.default.temporaryDirectory.appending(path: "usage-spike-\(UUID().uuidString)")
            guard let store = try? HistoryStore(url: folder.appending(path: "kotoba.sqlite")) else { return }
            self.store = store
            let apps = [("com.apple.Notes", "Notes"), ("com.apple.mail", "Mail"), ("com.apple.Terminal", "Terminal")]
            for index in 0..<10_000 {
                var record = DictationRecord(
                    id: DictationID(), createdAt: .now - Double(index) * 600,
                    audio: RecordedAudio(file: folder.appending(path: "\(index).flac"), duration: .seconds(8)),
                    transcript: "please move the standup to thursday and ask the team to review it",
                    model: index % 3 == 0 ? "x-ai/grok-stt-1.0" : "microsoft/mai-transcribe-2",
                    status: .pasted, latency: LatencyLog())
                record.app = DictationApp(bundleID: apps[index % 3].0, name: apps[index % 3].1)
                record.usage = [
                    UsageEntry(
                        time: record.createdAt, dictation: record.id, kind: .speech, model: record.model ?? "",
                        audio: .seconds(8), deliveredWords: 13, spokenWords: 13, cost: .reported(Decimal(222) / 1_000_000), app: record.app)
                ]
                if index % 5 == 0 {
                    record.usage.append(
                        UsageEntry(
                            time: record.createdAt, dictation: record.id, kind: .cleanup,
                            model: "google/gemini-3.5-flash-lite", deliveredWords: -1, cost: .reported(Decimal(300) / 1_000_000),
                            app: record.app))
                }
                try? await store.save(record)
            }
        }

        /// As `SettingsController.panes()`: a new model per open.
        func open() {
            guard let store else { return }
            let model = UsageModel { try await store.usage(from: $0, to: .distantFuture) }
            settings.show([.usage(model)])
            weakWindow = NSApp.windows.first { $0.contentViewController != nil }
            weakHost = weakWindow?.contentViewController
            weakModel = model
            print("open: window \(weakWindow != nil), host \(weakHost != nil), model \(weakModel != nil)")
        }
    #endif
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.run()
