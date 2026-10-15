import AppKit
import KotobaCore
import Synchronization

/// The front app, for the pipeline's submit rule (a Return goes only to the app in front at the stop) and for the
/// history (each dictation keeps the app it went to). App activation notifications keep it, so a read is one short
/// lock on any thread, with no hop to the main thread.
enum FrontAppObserver {
    private static let front = Mutex<FrontApp?>(nil)
    @MainActor private static var observer: (any NSObjectProtocol)?

    static var current: FrontApp? {
        front.withLock { $0 }
    }

    /// Reads the front app now and again at each activation.
    @MainActor
    static func track() {
        store(NSWorkspace.shared.frontmostApplication)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            store(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
    }

    private static func store(_ app: NSRunningApplication?) {
        let value = app.map { app in
            FrontApp(
                processID: app.processIdentifier,
                app: app.bundleIdentifier.map { DictationApp(bundleID: $0, name: app.localizedName) })
        }
        front.withLock { $0 = value }
    }
}
