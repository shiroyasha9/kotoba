import AppKit
import KotobaCore
import KotobaProviders

/// The menu bar menu's actions. AppDelegate implements them; a snapshot run builds the menu with no target. The app
/// menu (`MainMenu`) sends About and Settings… here too.
@MainActor
@objc protocol StatusMenuActions {
    func finishSetup()
    func retryFailed()
    func copyRecovered(_ sender: NSMenuItem)
    func chooseMicrophone(_ sender: NSMenuItem)
    func fixLastDictation()
    func pasteLastDictation()
    func pasteLastWithoutCleanup()
    func copyLastDictation()
    func rewriteLastDictation()
    func openKotoba()
    func openSettings()
    func showAbout()
    func checkForUpdates()
}

/// Everything the menu bar menu shows, as values, so the menu can be built and read without the running app. The menu
/// holds what a user reaches for while another app is in front (docs/research/ui-redesign.md, "Status menu"): the
/// status line, the last dictation, the microphone, and the way into the window; everything else lives there.
@MainActor
struct MenuModel {
    enum Status {
        /// Setup is not complete: an enabled "Finish Setting Up kotoba…" with the first thing to do.
        case finishSetup(String)
        /// A disabled line: the dictation state, or the ready hint.
        case text(String)
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
    /// A dictation was pasted or copied; the Last Dictation items hide until then.
    var hasLastDictation = false
    /// The last dictation was cleaned up: "Paste Last Without Cleanup" is Paste's ⌥ alternate.
    var hasRawLastDictation = false
    /// Rewrite is set up (it runs on OpenRouter, so an OpenRouter key is saved); "Rewrite Last Dictation" hides
    /// otherwise.
    var canRewrite = false
    /// The update item's state; nil in a Debug build, which has no updater, so the item hides.
    var updates: Updates?

    struct Updates {
        /// False while Sparkle reads the feed or downloads in the background: "Check for Updates…" is disabled.
        var canCheck = true
        /// A scheduled check found an update the user has not looked at: the item reads "Install Update…".
        var hasWaitingUpdate = false
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
        for item in topItems(target: target) + [.separator(), microphoneItem(target: target), .separator()] {
            menu.addItem(item)
        }
        menu.addItem(
            .action("Open \(Install.displayName)…", target: target, action: #selector(StatusMenuActions.openKotoba)))
        // The update item stays here: with "Show in Dock" off there is no app menu until a window opens, and a waiting
        // update has no other place to show.
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
            items += lastDictationItems(target: target)
        }
        return items
    }

    /// Paste, copy, rewrite or fix the last dictation. Paste without cleanup stays one item: the ⌥ alternate of Paste,
    /// as Finder's Close and Close All, so the menu keeps the plan's few items and the feature keeps its one way in.
    private func lastDictationItems(target: StatusMenuActions?) -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            .action("Paste Last Dictation", target: target, action: #selector(StatusMenuActions.pasteLastDictation))
        ]
        if hasRawLastDictation {
            let raw = NSMenuItem.action(
                "Paste Last Without Cleanup", target: target,
                action: #selector(StatusMenuActions.pasteLastWithoutCleanup))
            raw.keyEquivalentModifierMask = .option
            raw.isAlternate = true
            items.append(raw)
        }
        items.append(
            .action("Copy Last Dictation", target: target, action: #selector(StatusMenuActions.copyLastDictation)))
        if canRewrite {
            items.append(
                .action(
                    "Rewrite Last Dictation", target: target,
                    action: #selector(StatusMenuActions.rewriteLastDictation)))
        }
        items.append(
            .action("Fix Last Dictation…", target: target, action: #selector(StatusMenuActions.fixLastDictation)))
        return items
    }

    /// The connected mics, the one in use checked; picking one puts it first in the Microphone page's list.
    private func microphoneItem(target: StatusMenuActions?) -> NSMenuItem {
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
        return microphone
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

    /// Menus for the snapshot run's `menu-<name>.txt`: ready (a cleaned-up last dictation, Rewrite set up), setup not
    /// complete (a Debug build: no update item),
    /// recording (with Sparkle busy), failed with a retry and an update waiting, a Bluetooth mic, and kotoba Dev while
    /// the release app runs.
    static func samples() -> [(name: String, model: Self)] {
        let mics = [MenuChoice(title: "MacBook Pro Microphone", value: "builtin")]
        // Each status line comes from the shell, as the running app's does, so a sample shows its priorities.
        func status(_ state: DictationState = .idle, _ facts: ShellStatus.Facts<Readiness.Missing> = .init()) -> Status
        {
            var shell = ShellStatus()
            _ = shell.dictationChanged(state)
            return shell.view(facts).status.line(StatusContext(provider: .openRouter))
        }
        var ready = Self(
            status: status(), microphones: mics, microphoneInUse: ("builtin", "MacBook Pro Microphone"),
            updates: Updates())
        var setup = ready
        setup.updates = nil
        setup.status = status(.idle, .init(firstMissing: .setup(.key, .openRouter)))
        var listening = ready
        listening.status = status(.init(.recording(isLong: false)))
        listening.updates?.canCheck = false
        ready.recovered = [MenuChoice(title: "Send the draft to the team by Friday", value: "1")]
        ready.hasLastDictation = true
        ready.hasRawLastDictation = true
        ready.canRewrite = true
        var yielding = ready
        yielding.status = status(.idle, .init(isYielding: true))
        var failed = ready
        failed.status = status(.init(.idle, notice: .failed(DictationID())))
        failed.pendingCount = 2
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
    /// One item per line (submenu items indented, subtitles after "·", then the key equivalent; an alternate names the
    /// modifier that shows it), for snapshot runs.
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
            if item.isAlternate { line += " (alternate with " + shortcut(of: item) + ")" }
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
