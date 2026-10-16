import Foundation

/// A selector target for an observer API with no block form: a distributed notification asked for at once
/// (`suspensionBehavior: .deliverImmediately`). AppKit holds distributed notifications while the app is not active
/// (NSDistributedNotificationCenter.h), and kotoba is rarely the active app.
final class NotificationRelay: NSObject, Sendable {
    private let onReceive: @Sendable () -> Void

    init(_ onReceive: @escaping @Sendable () -> Void) {
        self.onReceive = onReceive
    }

    @objc func received(_ notification: Notification) {
        onReceive()
    }
}
