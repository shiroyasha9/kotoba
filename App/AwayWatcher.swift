import AppKit
import KotobaCore

/// Screen lock, sleep and fast user switching, reported to the pipeline as each happens (`Absence`): notifications
/// only, no work at idle. The lock pair is the distributed `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// (not in Apple's reference, long used by apps that follow the lock); it is delivered at once, also while kotoba
/// is not the active app.
@MainActor
enum AwayWatcher {
    private static var relays: [NotificationRelay] = []
    private static var observers: [any NSObjectProtocol] = []
    private static var feed: Task<Void, Never>?

    static func watch(feeding pipeline: DictationPipeline) {
        let (events, sink) = AsyncStream.makeStream(of: (absence: Absence, isAway: Bool).self)
        for (name, isAway) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let relay = NotificationRelay { sink.yield((.screenLocked, isAway)) }
            relays.append(relay)
            DistributedNotificationCenter.default().addObserver(
                relay, selector: #selector(NotificationRelay.received), name: Notification.Name(name), object: nil,
                suspensionBehavior: .deliverImmediately)
        }
        let watched: [Absence: [(name: Notification.Name, isAway: Bool)]] = [
            .asleep: [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)],
            .sessionInactive: [
                (NSWorkspace.sessionDidResignActiveNotification, true),
                (NSWorkspace.sessionDidBecomeActiveNotification, false),
            ],
        ]
        let workspace = NSWorkspace.shared.notificationCenter
        for (absence, notes) in watched {
            for note in notes {
                let report: @Sendable (Notification) -> Void = { _ in sink.yield((absence, note.isAway)) }
                observers.append(workspace.addObserver(forName: note.name, object: nil, queue: nil, using: report))
            }
        }
        // One consumer keeps the reports in order.
        feed = Task {
            for await event in events {
                if event.isAway {
                    await pipeline.absenceBegan(event.absence)
                } else {
                    await pipeline.absenceEnded(event.absence)
                }
            }
        }
    }
}
