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
        /// Setup is not complete: an enabled item that fixes the first thing ("Finish Setting Up kotoba…", "Add
        /// Credit…"), with what it is.
        case finishSetup(title: String, subtitle: String)
        /// Ready to dictate: both ways to dictate, each with its chord.
        case ready
        /// A disabled line: the dictation state.
        case text(String)
    }

    /// The owner's chords, as `HotkeyChords` holds them: the ready lines name the dictation chords, and a last
    /// dictation item shows its own chord on the right, as an app menu shows a shortcut, so the menu teaches them.
    struct Chords {
        var handsFree = Chord.defaultHandsFree
        var pushToTalk = Chord.defaultHandsFree
        var pasteLast: Chord?
        var copyLast: Chord? = .defaultCopyLast
        var rewriteLast: Chord?
    }

    var status: Status
    var chords = Chords()
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
        var items = topItems(target: target)
        // Saved dictations are a group of their own, apart from the status and the ways to dictate above them.
        let saved = savedItems(target: target)
        if !saved.isEmpty {
            items += [.separator()] + saved
        }
        if hasLastDictation {
            items += [.separator()] + lastDictationItems(target: target, for: place)
        }
        for item in items + [.separator(), microphoneItem(target: target), .separator()] {
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
        case .finishSetup(let title, let subtitle):
            let item = NSMenuItem.action(title, target: target, action: #selector(StatusMenuActions.finishSetup))
            item.subtitle = subtitle
            items.append(item)
        case .ready:
            // Both ways to dictate with their chords, as lines to read, not to click (owner QA, 2026-10-25: the menu
            // teaches the shortcuts). Push to talk's chord is hands-free's, held, unless it has its own.
            items.append(
                .note(StatusText.shortcutTitle(.handsFree), "Press \(chords.handsFree.title) to start and stop"))
            items.append(
                .note(StatusText.shortcutTitle(.pushToTalk), "Hold \(chords.pushToTalk.title) while you speak"))
        case .text(let text):
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            items.append(item)
        }
        return items
    }

    /// Dictations that wait for a retry, and retried ones to copy.
    private func savedItems(target: StatusMenuActions?) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if pendingCount > 0 {
            items.append(
                .action(
                    "Send \(StatusText.counted(pendingCount, "Saved Dictation"))", target: target,
                    action: #selector(StatusMenuActions.retryFailed)))
        }
        if !recovered.isEmpty {
            let choices = recovered.map { MenuChoice(title: $0.title, value: $0.value, subtitle: "Click to copy") }
            items.append(
                .choices(
                    "Recovered Dictations", choices, selected: nil, target: target,
                    action: #selector(StatusMenuActions.copyRecovered(_:))))
        }
        return items
    }

    /// The last dictation's group under its section header, as Apple's menu bar extras group their items (Wi-Fi's
    /// "Known Network"), so each item is one verb: Paste, Copy, Rewrite, Fix. An item with a key chord shows it on the
    /// right. Paste without cleanup is Paste's ⌥ alternate, as Finder's Close and Close All, so the feature keeps its
    /// one way in; an alternate pairs only with an item of the same key equivalent, so while Paste shows a chord of
    /// its own, it is an item of its own. The Dock's menu leaves it out: nothing shows that the Dock draws alternates,
    /// and the menu bar menu has it.
    private func lastDictationItems(target: StatusMenuActions?, for place: Place) -> [NSMenuItem] {
        let paste = NSMenuItem.action("Paste", target: target, action: #selector(StatusMenuActions.pasteLastDictation))
        let pastesWithChord = paste.showsChord(chords.pasteLast)
        var items: [NSMenuItem] = [.sectionHeader(title: "Last Dictation"), paste]
        if hasRawLastDictation && place == .menuBar {
            let raw = NSMenuItem.action(
                "Paste Without Cleanup", target: target, action: #selector(StatusMenuActions.pasteLastWithoutCleanup))
            if !pastesWithChord {
                raw.keyEquivalentModifierMask = .option
                raw.isAlternate = true
            }
            items.append(raw)
        }
        let copy = NSMenuItem.action("Copy", target: target, action: #selector(StatusMenuActions.copyLastDictation))
        copy.showsChord(chords.copyLast)
        items.append(copy)
        if canRewrite {
            let rewrite = NSMenuItem.action(
                "Rewrite", target: target, action: #selector(StatusMenuActions.rewriteLastDictation))
            rewrite.showsChord(chords.rewriteLast)
            items.append(rewrite)
        }
        items.append(.action("Fix…", target: target, action: #selector(StatusMenuActions.fixLastDictation)))
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

    /// Menus for the snapshot run's `menu-<name>.txt`: ready (a cleaned-up last dictation, Rewrite set up, Copy's
    /// default chord), ready with chords of their own for push to talk, Paste and Rewrite, setup not complete (a Debug
    /// build: no update item), out of credit with dictations saved, recording (with Sparkle busy), failed with a retry
    /// and an update waiting, a Bluetooth mic, and kotoba Dev while the release app runs.
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
        var noCredit = ready
        noCredit.status = status(.idle, .init(firstMissing: .setup(.credit, .openRouter)))
        noCredit.pendingCount = 3
        var listening = ready
        listening.status = status(.init(.recording(isLong: false)))
        listening.updates?.canCheck = false
        ready.recovered = [MenuChoice(title: "Send the draft to the team by Friday", value: "1")]
        ready.hasLastDictation = true
        ready.hasRawLastDictation = true
        ready.canRewrite = true
        var ownChords = ready
        ownChords.chords.pushToTalk = Chord(modifiers: [.rightOption])
        ownChords.chords.pasteLast = Chord(modifiers: [.control, .option], keyCode: KeyCode.ansiV)
        ownChords.chords.rewriteLast = Chord(modifiers: [.option], keyCode: KeyCode.ansi1)
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
            ("ready", ready), ("own-chords", ownChords), ("setup", setup), ("no-credit", noCredit),
            ("listening", listening), ("failed", failed),
            ("bluetooth", bluetooth),
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
            if item.isSectionHeader { line += " (header)" }
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
