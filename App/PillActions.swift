import AppKit
import KotobaCore
import KotobaProviders

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
    /// Puts back the text from before Polish (`DictationPipeline.undoPolish`).
    case undoPolish(DictationID)
    case retryPolish
    /// OpenRouter's credits page: Polish runs there whatever the speech model.
    case addOpenRouterCredit

    var title: String {
        switch self {
        case .undo, .undoLearned, .undoPolish: "Undo"
        case .retry, .retryPolish: "Retry"
        case .addKey: "Add Key…"
        case .openSpeechSettings: "Settings…"
        case .addCredit, .addOpenRouterCredit: "Add Credit…"
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
        case .undo, .undoPolish, .retryPolish:
            performOnPipeline(action)
        case .retry:
            retryFailed()
        case .addKey, .openSpeechSettings, .chooseMicrophone:
            mainWindow.show(selecting: action.settingsPane)
        case .addCredit:
            NSWorkspace.shared.open(routeSettings.route.account.creditsPage)
        case .copy:
            guard case .recovered(let id) = shell.dictation else { return }
            copyRecovered(id)
        case .allowPasting:
            setup.allowPasting()
        case .openMicrophoneSettings:
            readiness.openSettings(.microphone)
        case .undoLearned(let id):
            learner.undo(id)
        case .addOpenRouterCredit:
            NSWorkspace.shared.open(ProviderAccount.openRouter.creditsPage)
        }
    }

    /// Esc's Undo, Polish's Undo and Polish's Retry: the pipeline does them.
    private func performOnPipeline(_ action: PillAction) {
        guard let pipeline else { return }
        switch action {
        case .undoPolish(let id): Task { await pipeline.undoPolish(id) }
        case .retryPolish: Task { await pipeline.polishLast() }
        default: Task { await pipeline.undo() }
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
