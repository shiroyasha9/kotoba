import AppKit
import KotobaCore
import Synchronization

/// The front app, for the pipeline's submit rule (a Return goes only to the app in front at the stop) and for the
/// history (each dictation keeps the app it went to), and the last app in front other than kotoba, where the History
/// window's Paste Again goes. App activation notifications keep both, so a read is one short lock on any thread, with
/// no hop to the main thread.
enum FrontAppObserver {
    private struct Apps {
        var front: FrontApp?
        var lastOther: Int32?
    }

    private static let apps = Mutex(Apps())
    static let ownProcessID = ProcessInfo.processInfo.processIdentifier
    @MainActor private static var observer: (any NSObjectProtocol)?

    static var current: FrontApp? {
        apps.withLock { $0.front }
    }

    /// The process id of the last app other than kotoba that was in front; nil when none was since launch.
    static var lastOtherProcessID: Int32? {
        apps.withLock { $0.lastOther }
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
        apps.withLock { apps in
            apps.front = value
            if let id = value?.processID, id != ownProcessID {
                apps.lastOther = id
            }
        }
    }
}
