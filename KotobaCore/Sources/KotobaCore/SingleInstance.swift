import Foundation

/// Two copies of one install (the installed app and one opened from the DMG or an old download) would both hear the
/// chord, record, upload and paste the same speech, and each would take the other's live recording for an orphan.
/// The copy that launched first keeps running; a later one hands over to it and quits before it opens the history. A
/// development build and the release are two installs (two bundle ids); `InstallYield` decides between them.
public enum SingleInstance {
    public struct Copy: Sendable, Equatable {
        public let processID: Int32
        /// When the process started; nil when unknown.
        public let launchedAt: Date?

        public init(processID: Int32, launchedAt: Date?) {
            self.processID = processID
            self.launchedAt = launchedAt
        }

        /// One order that every copy computes alike: launch time, then process id; an unknown launch time comes first.
        var order: (Date, Int32) { (launchedAt ?? .distantPast, processID) }
    }

    /// The copy `launching` hands over to, or nil when it keeps running. Two copies that launch together each see the
    /// other; the shared order keeps exactly one.
    public static func handOver(from launching: Copy, others: [Copy]) -> Copy? {
        guard let first = others.min(by: { $0.order < $1.order }), first.order < launching.order else { return nil }
        return first
    }
}
