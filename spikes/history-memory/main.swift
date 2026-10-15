// History window memory spike: a status-item app that links the real App/History model and view (WITH_HISTORY) over a
// temporary history of 10,000 synthetic dictations. It opens the window at 32 s, the way `HistoryController` builds it,
// and closes it at 45 s. Without WITH_HISTORY it is the same app with no SwiftUI.
// `--leak-check`: open at 1 s, close at 2 s, then print whether the window, its hosting controller and the model were
// deallocated, and quit.
import AppKit

#if WITH_HISTORY
    import SwiftUI

    /// Stand-ins for the App types the History files use, which pull in the rest of the app.
    enum StatusText {
        static let dictationChord = "⌃⌥⌘"
        static func counted(_ count: Int, _ noun: String) -> String {
            String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)").characters)
        }
    }

    enum LastDictation {
        static func rawText(of record: DictationRecord) -> String? {
            record.cleanedText == nil ? nil : record.transcript
        }
    }
#endif

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?
    #if WITH_HISTORY
        var store: HistoryStore?
        weak var weakWindow: NSWindow?
        weak var weakHost: NSViewController?
        weak var weakModel: HistoryModel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "spike")
        item.menu = NSMenu()
        self.item = item
        #if WITH_HISTORY
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

    #if WITH_HISTORY
        /// 10,000 dictations of about 30 words, as `HistoryStoreTests` measures.
        func fill() async {
            let folder = FileManager.default.temporaryDirectory.appending(path: "history-spike-\(UUID().uuidString)")
            guard let store = try? HistoryStore(url: folder.appending(path: "kotoba.sqlite")) else { return }
            self.store = store
            let words = "please move the standup to thursday and ask the team to review the pull request before lunch"
                .split(separator: " ")
            let apps = [("com.apple.Notes", "Notes"), ("com.apple.mail", "Mail"), ("com.apple.Terminal", "Terminal")]
            for index in 0..<10_000 {
                var record = DictationRecord(
                    id: DictationID(), createdAt: .now - Double(index) * 600,
                    audio: RecordedAudio(file: folder.appending(path: "\(index).flac"), duration: .seconds(8)),
                    transcript: (0..<30).map { words[($0 * 7 + index) % words.count] }.joined(separator: " "),
                    status: .pasted, latency: LatencyLog())
                record.app = DictationApp(bundleID: apps[index % 3].0, name: apps[index % 3].1)
                try? await store.save(record)
            }
        }

        /// As `HistoryController.makeWindow`.
        func open() {
            guard let store else { return }
            let model = HistoryModel(
                source: HistoryModel.Source(
                    page: { try await store.page(matching: $0, after: $1, limit: $2) },
                    record: { try await store.record($0, matching: $1) }, delete: { _ in }, retry: { _ in },
                    paste: { _, _ in true }, copy: { _ in }))
            let controller = NSHostingController(rootView: HistoryView(model: model))
            controller.sceneBridgingOptions = [.toolbars]
            let window = NSWindow(contentViewController: controller)
            window.title = "History"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 560))
            window.orderFront(nil)
            weakWindow = window
            weakHost = controller
            weakModel = model
            print("open: window \(weakWindow != nil), host \(weakHost != nil), model \(weakModel != nil)")
        }
    #endif
}

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.run()
