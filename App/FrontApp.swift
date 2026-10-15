import AppKit
import Synchronization

/// The front app's process id for the pipeline's submit rule (a Return goes only to the app in front at the stop).
/// App activation notifications keep it, so a read is one atomic load on any thread, with no hop to the main thread.
enum FrontApp {
    /// 0 when unknown.
    private static let processID = Atomic<Int32>(0)
    @MainActor private static var observer: (any NSObjectProtocol)?

    static var current: Int32? {
        let id = processID.load(ordering: .relaxed)
        return id == 0 ? nil : id
    }

    /// Reads the front app now and again at each activation.
    @MainActor
    static func track() {
        processID.store(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0, ordering: .relaxed)
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            processID.store(app?.processIdentifier ?? 0, ordering: .relaxed)
        }
    }
}
