import AppKit
import KotobaCore

// MARK: - Pill actions

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
