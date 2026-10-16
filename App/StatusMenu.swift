import AppKit
import KotobaCore
import KotobaProviders

/// The menu bar menu's actions. AppDelegate implements them; a snapshot run builds the menu with no target.
@MainActor
@objc protocol StatusMenuActions {
    func finishSetup()
    func retryFailed()
    func copyRecovered(_ sender: NSMenuItem)
    func chooseMicrophone(_ sender: NSMenuItem)
    func selectRoute(_ sender: NSMenuItem)
    func toggleGrokFormat()
    func toggleGrokFillerWords()
    func fixLastDictation()
    func pasteLastDictation()
    func pasteLastWithoutCleanup()
    func copyLastDictation()
    func openSuggestions()
    func openHistory()
    func openSettings()
    func showAbout()
    func checkForUpdates()
}

/// Everything the menu bar menu shows, as values, so the menu can be built and read without the running app.
@MainActor
struct MenuModel {
    enum Status {
        /// Setup is not complete: an enabled "Finish Setting Up kotoba…" with the first thing to do.
        case finishSetup(String)
        /// A disabled line: the dictation state, or the ready hint.
        case text(String)
    }

    struct Grok {
        var isFormatOn: Bool
        var keepsFillerWords: Bool
    }

    var status: Status
    var pendingCount = 0
    /// Retried transcripts, newest first; `value` is the dictation id.
    var recovered: [MenuChoice] = []
    var microphones: [MenuChoice] = []
    /// The uid and name of the mic kotoba records from.
    var microphoneInUse: (uid: String, name: String)?
    /// Shown at the foot of the Microphone submenu (`InputDevicePolicy.warning`).
    var microphoneWarning: MicrophoneWarning?
    var routes: [MenuChoice] = []
    var route: MenuChoice?
    /// The Grok options, shown when the current speech model is Grok.
    var grok: Grok?
    /// A dictation was pasted or copied; the Last Dictation items hide until then.
    var hasLastDictation = false
    /// The last dictation was cleaned up; "Paste Last Without Cleanup" hides otherwise.
    var hasRawLastDictation = false
    /// Pending dictionary suggestions; the item hides at 0.
    var suggestionCount = 0
    /// The update item's state; nil in a Debug build, which has no updater, so the item hides.
    var updates: Updates?

    struct Updates {
        /// False while Sparkle reads the feed or downloads in the background: "Check for Updates…" is disabled.
        var canCheck = true
        /// A scheduled check found an update the user has not looked at: the item reads "Install Update…".
        var hasWaitingUpdate = false
    }

    /// The speech models the menu offers: the OpenRouter ones, plus a direct route only while it is the current one
    /// (the others sit under Advanced in Settings).
    static func routes(current: TranscriptionRoute) -> [MenuChoice] {
        TranscriptionRoute.allCases.filter { !$0.isAdvanced || $0 == current }.map {
            MenuChoice(title: $0.title, value: $0.rawValue, subtitle: $0.note)
        }
    }

    /// The menu bar icon's menu, or the Dock icon's right-click menu (story 35), which has the same items but Quit: the
    /// Dock adds its own.
    enum Place {
        case menuBar
        case dock
    }

    /// Builds the whole menu into `menu`, replacing its items.
    func build(into menu: NSMenu, target: StatusMenuActions?, for place: Place = .menuBar) {
        menu.removeAllItems()
        for item in topItems(target: target) + [.separator()] + settingItems(target: target) + [.separator()] {
            menu.addItem(item)
        }
        menu.addItem(.action("History…", target: target, action: #selector(StatusMenuActions.openHistory)))
        menu.addItem(
            .action("Settings…", target: target, action: #selector(StatusMenuActions.openSettings), keyEquivalent: ","))
        menu.addItem(
            .action("About \(Install.displayName)", target: target, action: #selector(StatusMenuActions.showAbout)))
        if let updates {
            menu.addItem(Self.updateItem(updates, target: target))
        }
        guard place == .menuBar else { return }
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit \(Install.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
            ))
    }

    private func topItems(target: StatusMenuActions?) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        switch status {
        case .finishSetup(let missing):
            let item = NSMenuItem.action(
                "Finish Setting Up kotoba…", target: target, action: #selector(StatusMenuActions.finishSetup))
            item.subtitle = missing
            items.append(item)
        case .text(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            items.append(item)
        }
        if pendingCount > 0 {
            items.append(
                .action(
                    "Retry \(StatusText.counted(pendingCount, "Saved Dictation"))", target: target,
                    action: #selector(StatusMenuActions.retryFailed)))
        }
        if !recovered.isEmpty {
            let choices = recovered.map { MenuChoice(title: $0.title, value: $0.value, subtitle: "Click to copy") }
            items.append(
                .choices(
                    "Recovered Dictations", choices, selected: nil, target: target,
                    action: #selector(StatusMenuActions.copyRecovered(_:))))
        }
        if hasLastDictation {
            items.append(
                .action(
                    "Paste Last Dictation", target: target, action: #selector(StatusMenuActions.pasteLastDictation)))
            if hasRawLastDictation {
                items.append(
                    .action(
                        "Paste Last Without Cleanup", target: target,
                        action: #selector(StatusMenuActions.pasteLastWithoutCleanup)))
            }
            items.append(
                .action("Copy Last Dictation", target: target, action: #selector(StatusMenuActions.copyLastDictation)))
            items.append(
                .action("Fix Last Dictation…", target: target, action: #selector(StatusMenuActions.fixLastDictation)))
        }
        if suggestionCount > 0 {
            items.append(
                .action(
                    "\(StatusText.counted(suggestionCount, "Word Suggestion"))…", target: target,
                    action: #selector(StatusMenuActions.openSuggestions)))
        }
        return items
    }

    private func settingItems(target: StatusMenuActions?) -> [NSMenuItem] {
        let microphone = NSMenuItem.choices(
            "Microphone", subtitle: microphoneInUse?.name ?? "None", microphones,
            selected: microphoneInUse?.uid, target: target,
            action: #selector(StatusMenuActions.chooseMicrophone(_:)))
        if let microphoneWarning, let submenu = microphone.submenu {
            let warning = NSMenuItem(title: StatusText.title(microphoneWarning), action: nil, keyEquivalent: "")
            warning.subtitle = StatusText.detail(microphoneWarning)
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            warning.isEnabled = false
            submenu.addItem(.separator())
            submenu.addItem(warning)
        }
        var items = [microphone]
        let model = NSMenuItem.choices(
            "Speech Model", subtitle: route?.title, routes, selected: route?.value, target: target,
            action: #selector(StatusMenuActions.selectRoute(_:)))
        if let grok, let submenu = model.submenu {
            submenu.addItem(.separator())
            submenu.addItem(
                .toggle(
                    "Format Numbers and Units", isOn: grok.isFormatOn, target: target,
                    action: #selector(StatusMenuActions.toggleGrokFormat)))
            submenu.addItem(
                .toggle(
                    "Keep Filler Words", isOn: grok.keepsFillerWords, target: target,
                    action: #selector(StatusMenuActions.toggleGrokFillerWords)))
        }
        items.append(model)
        return items
    }

    /// "Check for Updates…" or "Install Update…", in this menu and in the app menu (`MainMenu`). Without an action the
    /// menu disables the item, as it does the status line.
    static func updateItem(_ updates: Updates, target: StatusMenuActions?) -> NSMenuItem {
        let item = NSMenuItem.action(
            updates.hasWaitingUpdate ? "Install Update…" : "Check for Updates…", target: target,
            action: #selector(StatusMenuActions.checkForUpdates))
        if !updates.canCheck {
            item.action = nil
            item.isEnabled = false
        }
        return item
    }

    /// Menus for the snapshot run's `menu-<name>.txt`: ready, setup not complete (a Debug build: no update item),
    /// listening (with Sparkle busy), failed with a retry and an update waiting, and a Bluetooth mic.
    static func samples() -> [(name: String, model: Self)] {
        let mics = [MenuChoice(title: "MacBook Pro Microphone", value: "builtin")]
        let context = StatusContext(provider: .openRouter)
        func route(_ route: TranscriptionRoute) -> MenuChoice {
            MenuChoice(title: route.menuTitle, value: route.rawValue)
        }
        var ready = Self(
            status: .text(StatusText.ready), microphones: mics, microphoneInUse: ("builtin", "MacBook Pro Microphone"),
            routes: routes(current: .openRouterMAI), route: route(.openRouterMAI), updates: Updates())
        var setup = ready
        setup.updates = nil
        setup.status = .finishSetup(Readiness.Missing.setup(.key, .openRouter).setupText)
        var listening = ready
        listening.status = .text(DictationState.recording(isLong: false).statusText(context) ?? "")
        listening.updates?.canCheck = false
        ready.recovered = [MenuChoice(title: "Send the draft to the team by Friday", value: "1")]
        ready.hasLastDictation = true
        ready.hasRawLastDictation = true
        ready.suggestionCount = 2
        var yielding = ready
        yielding.status = .text(StatusText.yieldsToRelease)
        var failed = ready
        failed.status = .text(DictationState.failed(DictationID()).statusText(context) ?? "")
        failed.pendingCount = 2
        failed.routes = routes(current: .xaiGrok)
        failed.route = route(.xaiGrok)
        failed.grok = Grok(isFormatOn: true, keepsFillerWords: false)
        failed.updates?.hasWaitingUpdate = true
        var bluetooth = listening
        bluetooth.microphones.append(MenuChoice(title: "AirPods Pro", value: "airpods"))
        bluetooth.microphoneInUse = ("airpods", "AirPods Pro")
        bluetooth.microphoneWarning = .bluetoothMic(interruptsPlayback: true)
        return [
            ("ready", ready), ("setup", setup), ("listening", listening), ("failed", failed), ("bluetooth", bluetooth),
            ("yielding", yielding),
        ]
    }

    /// The menu as text (`NSMenu.outline`), for snapshot runs.
    func text(for place: Place = .menuBar) -> String {
        let menu = NSMenu()
        menu.autoenablesItems = false
        build(into: menu, target: nil, for: place)
        return menu.outline()
    }
}

extension NSMenu {
    /// One item per line (submenu items indented, subtitles after "·", then the key equivalent), for snapshot runs.
    func outline() -> String {
        Self.lines(of: self, depth: 0).joined(separator: "\n") + "\n"
    }

    private static func lines(of menu: NSMenu, depth: Int) -> [String] {
        menu.items.flatMap { item -> [String] in
            let indent = String(repeating: "    ", count: depth)
            guard !item.isSeparatorItem else { return [indent + "---"] }
            var line = indent + item.title
            if let subtitle = item.subtitle { line += " · " + subtitle }
            if !item.keyEquivalent.isEmpty { line += " " + shortcut(of: item) }
            if item.state == .on { line += " [on]" }
            if !item.isEnabled { line += " (disabled)" }
            if let submenu = item.submenu { return [line + " ▸"] + lines(of: submenu, depth: depth + 1) }
            return [line]
        }
    }

    /// "⌥⌘H", as the menu draws it.
    private static func shortcut(of item: NSMenuItem) -> String {
        let flags = item.keyEquivalentModifierMask
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return symbols.filter { flags.contains($0.0) }.map(\.1).joined() + item.keyEquivalent.uppercased()
    }
}
