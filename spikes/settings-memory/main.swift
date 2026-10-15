// Settings window memory spike: a status-item app that links the real App/Settings code (WITH_SETTINGS), opens the
// Dictionary pane at 32 s and closes it at 45 s. Without WITH_SETTINGS it is the same app with no SwiftUI.
// `--leak-check`: open at 1 s, close at 2 s, then print whether the window, its hosting controller and the pane's
// model were deallocated, and quit.
import AppKit

@MainActor
final class Spike: NSObject, NSApplicationDelegate {
    var item: NSStatusItem?
    #if WITH_SETTINGS
    let settings = SettingsWindow()
    var model: DictionaryModel?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "spike")
        item.menu = NSMenu()
        self.item = item
        #if WITH_SETTINGS
        if CommandLine.arguments.contains("--leak-check") {
            leakCheck()
            return
        }
        Timer.scheduledTimer(withTimeInterval: 32, repeats: false) { _ in
            MainActor.assumeIsolated { self.open() }
        }
        Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { _ in
            MainActor.assumeIsolated { NSApp.windows.first { $0.title == "kotoba Settings" }?.close() }
        }
        #endif
    }

    #if WITH_SETTINGS
    func open() {
        let url = FileManager.default.temporaryDirectory.appending(path: "settings-spike-\(UUID().uuidString).sqlite")
        guard let store = try? DictionaryStore(url: url) else { return }
        var dictionary = PersonalDictionary(terms: (0..<36).map { "Term number \($0)" })
        dictionary.rules = [
            ReplacementRule(find: "cloud code", replacement: "Claude Code"),
            ReplacementRule(find: "open router", replacement: "OpenRouter"),
        ]
        let model = DictionaryModel(dictionary: dictionary, store: store) { _ in }
        self.model = model
        settings.show([.dictionary(model)])
    }

    weak var weakWindow: NSWindow?
    weak var weakHost: NSViewController?
    weak var weakModel: DictionaryModel?

    func leakCheck() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated {
                self.open()
                let window = NSApp.windows.first { $0.title == "kotoba Settings" }
                self.weakWindow = window
                self.weakHost = window?.contentViewController
                self.weakModel = self.model
                // Like a per-open pane model (Providers, Microphone): only the window holds it now.
                self.model = nil
                print("open: window \(window != nil), host \(self.weakHost != nil), model \(self.weakModel != nil)")
            }
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated { self.weakWindow?.close() }
        }
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

let app = NSApplication.shared
let delegate = Spike()
app.delegate = delegate
app.run()
