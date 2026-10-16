import AppKit
import KotobaCore
import KotobaProviders

// MARK: - Menu

extension AppDelegate: StatusMenuActions {
    func updateIcon() {
        statusItem?.icon =
            if case .recording = state {
                .listening
            } else if !readiness.isComplete || pendingCount > 0 || updater?.hasWaitingUpdate == true {
                .needsAttention
            } else {
                .ready
            }
    }

    func menuModel() -> MenuModel {
        readiness.refresh()
        let status: MenuModel.Status =
            if let launchIssue {
                .text(launchIssue)
            } else if releaseWatcher.showsYield(in: state) {
                .text(StatusText.yieldsToRelease)
            } else if state != .idle {
                .text(state.statusText(statusContext) ?? "")
            } else {
                readiness.firstMissing.map { .finishSetup($0.setupText) } ?? .text(StatusText.ready)
            }
        let route = routeSettings.route
        let input = audio.inputInUse
        return MenuModel(
            status: status,
            pendingCount: pendingCount,
            recovered: recovered,
            microphones: AudioDevices.inputs().map { MenuChoice(title: $0.name, value: $0.uid) },
            microphoneInUse: input.map { ($0.uid, $0.name) },
            microphoneWarning: InputDevicePolicy.warning(
                input: input, outputTransport: AudioDevices.defaultOutputTransport()),
            routes: MenuModel.routes(current: route),
            route: MenuChoice(title: route.menuTitle, value: route.rawValue),
            grok: route.isGrok
                ? MenuModel.Grok(
                    isFormatOn: routeSettings.isGrokFormatOn, keepsFillerWords: routeSettings.keepsGrokFillerWords)
                : nil,
            hasLastDictation: hasLastDictation,
            hasRawLastDictation: hasRawLastDictation,
            suggestionCount: settingsController.dictionary?.suggestions.count ?? 0,
            updates: updater.map { MenuModel.Updates(canCheck: $0.canCheck, hasWaitingUpdate: $0.hasWaitingUpdate) }
        )
    }

    func finishSetup() {
        setup.finishSetup()
    }

    func retryFailed() {
        guard let pipeline else { return }
        Task {
            await pipeline.retryPending()
            await refreshQueues()
        }
    }

    func copyRecovered(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let uuid = UUID(uuidString: raw) else { return }
        copyRecovered(DictationID(rawValue: uuid))
    }

    /// Picking a mic moves it to the top of the order.
    func chooseMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        microphones.choose(uid: uid, name: sender.title)
        Task { await audio.inputMayHaveChanged() }
    }

    func selectRoute(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let route = TranscriptionRoute(rawValue: raw) else {
            return
        }
        routeSettings.route = route
    }

    func toggleGrokFormat() {
        routeSettings.isGrokFormatOn.toggle()
    }

    func toggleGrokFillerWords() {
        routeSettings.keepsGrokFillerWords.toggle()
    }

    func fixLastDictation() {
        fixWindow.show()
    }

    func pasteLastDictation() {
        lastDictation?.perform(.paste)
    }

    func pasteLastWithoutCleanup() {
        lastDictation?.perform(.pasteWithoutCleanup)
    }

    func copyLastDictation() {
        lastDictation?.perform(.copy)
    }

    func submitPhraseChanged(isOn: Bool) {
        submitPhraseChanges.continuation.yield(isOn)
    }

    func openSuggestions() {
        settingsController.show(selecting: .dictionary)
    }

    func openHistory() {
        history?.show()
    }

    func openSettings() {
        settingsController.show()
    }

    func showAbout() {
        // AppKit builds and orders the About panel itself, so there is no window to give `WindowFront.show`.
        // swiftlint:disable:next window_front
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func checkForUpdates() {
        updater?.check()
    }
}
