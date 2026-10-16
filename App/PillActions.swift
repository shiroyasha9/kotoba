import AppKit
import KotobaCore

// MARK: - Pill actions

/// The one button a pill can carry. AppDelegate maps each action to its handler.
enum PillAction: Sendable, Equatable {
    case undo
    case retry
    case addKey
    case openSpeechSettings
    case addCredit
    case copy
    case allowPasting
    case openMicrophoneSettings
    /// Opens Settings > Microphone, from the no-sound warning.
    case chooseMicrophone
    /// Removes the words that auto-learn just added to the dictionary, found by the learn's id.
    case undoLearned(UUID)

    var title: String {
        switch self {
        case .undo, .undoLearned: "Undo"
        case .retry: "Retry"
        case .addKey: "Add Key…"
        case .openSpeechSettings: "Settings…"
        case .addCredit: "Add Credit…"
        case .copy: "Copy"
        case .allowPasting: "Allow Pasting…"
        case .openMicrophoneSettings: "Open System Settings…"
        case .chooseMicrophone: "Choose Mic…"
        }
    }
}

extension AppDelegate {
    func perform(_ action: PillAction) {
        switch action {
        case .undo:
            guard let pipeline else { return }
            Task { await pipeline.undo() }
        case .retry:
            retryFailed()
        case .addKey, .openSpeechSettings, .chooseMicrophone:
            mainWindow.show(selecting: action.settingsPane)
        case .addCredit:
            NSWorkspace.shared.open(routeSettings.route.account.creditsPage)
        case .copy:
            guard case .recovered(let id) = state else { return }
            copyRecovered(id)
        case .allowPasting:
            setup.allowPasting()
        case .openMicrophoneSettings:
            readiness.openSettings(.microphone)
        case .undoLearned(let id):
            learner.undo(id)
        }
    }

    func copyRecovered(_ id: DictationID) {
        guard let pipeline else { return }
        Task {
            guard let record = await pipeline.retries.recovered().first(where: { $0.id == id }) else { return }
            await pipeline.retries.copy(record)
        }
    }
}

extension PillAction {
    /// The Settings pane the button opens; nil for a button that opens none.
    var settingsPane: PaneID? {
        switch self {
        case .addKey, .openSpeechSettings: .speech
        case .chooseMicrophone: .microphones
        default: nil
        }
    }
}
