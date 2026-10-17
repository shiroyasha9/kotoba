import AppKit
import KotobaCore

/// Screen lock, sleep and fast user switching, reported to the pipeline as each happens (`Absence`): notifications
/// only, no work at idle. The lock pair is the distributed `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// (not in Apple's reference, long used by apps that follow the lock); it is delivered at once, also while kotoba
/// is not the active app.
@MainActor
enum AwayWatcher {
    private static var relays: [NotificationRelay] = []
    private static var feed: Task<Void, Never>?

    static func watch(feeding pipeline: DictationPipeline) {
        let (events, sink) = AsyncStream.makeStream(of: (absence: Absence, isAway: Bool).self)
        func relay(_ absence: Absence, isAway: Bool) -> NotificationRelay {
            let relay = NotificationRelay { sink.yield((absence, isAway)) }
            relays.append(relay)
            return relay
        }
        let lock = DistributedNotificationCenter.default()
        for (name, isAway) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            lock.addObserver(
                relay(.screenLocked, isAway: isAway), selector: #selector(NotificationRelay.received),
                name: Notification.Name(name), object: nil, suspensionBehavior: .deliverImmediately)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let watched: [Absence: [(name: Notification.Name, isAway: Bool)]] = [
            .asleep: [(NSWorkspace.willSleepNotification, true), (NSWorkspace.didWakeNotification, false)],
            .sessionInactive: [
                (NSWorkspace.sessionDidResignActiveNotification, true),
                (NSWorkspace.sessionDidBecomeActiveNotification, false),
            ],
        ]
        for (absence, notes) in watched {
            for note in notes {
                workspace.addObserver(
                    relay(absence, isAway: note.isAway), selector: #selector(NotificationRelay.received),
                    name: note.name, object: nil)
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
