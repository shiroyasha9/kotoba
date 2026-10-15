import Foundation
import ServiceManagement

/// Opens kotoba at login through `SMAppService.mainApp`. The onboarding Done step and the General pane read and set
/// it. Linking ServiceManagement loads it at launch (measured +16-80 KB on a test binary; see memory-spike.md).
@MainActor
enum LaunchAtLogin {
    /// Why the setting is not in effect; the toggle shows `text` under it.
    enum Problem: Equatable {
        /// Registered, but System Settings > General > Login Items still blocks it.
        case needsApproval
        case failed

        var text: String {
            switch self {
            case .needsApproval: "Allow kotoba in System Settings > General > Login Items."
            case .failed: "Could not change this setting. Try again in System Settings > General > Login Items."
            }
        }
    }

    static var isOn: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// The problem to show before any change: only a pending approval.
    static var problem: Problem? {
        needsApproval ? .needsApproval : nil
    }

    /// Registers or unregisters the app. Returns what keeps the choice from taking effect, or nil.
    @discardableResult
    static func change(to isOn: Bool) -> Problem? {
        let service = SMAppService.mainApp
        do {
            if isOn, service.status != .enabled {
                try service.register()
            } else if !isOn, service.status != .notRegistered {
                try service.unregister()
            }
        } catch {
            Log.app.error("Cannot change launch at login: \(error)")
            if !needsApproval {
                return .failed
            }
        }
        return problem
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
