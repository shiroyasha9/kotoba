import AppKit
import KotobaCore
import KotobaProviders

// MARK: - Menu

extension AppDelegate: StatusMenuActions {
    func updateIcon() {
        statusItem?.icon = shell.view(shellFacts).icon
    }

    func menuModel() -> MenuModel {
        readiness.refresh()
        let input = audio.inputInUse
        return MenuModel(
            status: shell.view(shellFacts).status.line(statusContext),
            pendingCount: shell.queues.waitingCount,
            recovered: shell.queues.recovered.map { MenuChoice(title: $0.title, value: $0.id.rawValue.uuidString) },
            microphones: AudioDevices.inputs().map { MenuChoice(title: $0.name, value: $0.uid) },
            microphoneInUse: input.map { ($0.uid, $0.name) },
            microphoneWarning: InputDevicePolicy.warning(
                input: input, outputTransport: AudioDevices.defaultOutputTransport()),
            hasLastDictation: shell.queues.hasLastDictation,
            hasRawLastDictation: shell.queues.hasRawLastDictation,
            canRewrite: vault.hasKey(for: .openRouter),
            updates: updates
        )
    }

    /// The update item's state for the menu bar menu and the app menu; nil in a Debug build, which has no updater.
    var updates: MenuModel.Updates? {
        updater.map { MenuModel.Updates(canCheck: $0.canCheck, hasWaitingUpdate: $0.hasWaitingUpdate) }
    }

    func finishSetup() {
        setup.finishSetup()
    }

    func retryFailed() {
        guard let pipeline else { return }
        Task {
            await pipeline.retryPending()
            refreshQueues()
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

    func rewriteLastDictation() {
        lastDictation?.perform(.polish)
    }

    func pasteSettingChanged(_ change: PasteSetting) {
        pasteSettingChanges.continuation.yield(change)
    }

    /// "Open kotoba…": the window on the page it showed last, Home the first time.
    func openKotoba() {
        mainWindow.show()
    }

    func openSettings() {
        mainWindow.showSettings()
    }

    func showAbout() {
        WindowFront.activateForAboutPanel()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    func checkForUpdates() {
        updater?.check()
    }
}
