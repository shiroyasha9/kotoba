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
    func openSettings()
    func showAbout()
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

    /// The speech models the menu offers: the OpenRouter ones, plus a direct route only while it is the current one
    /// (the others sit under Advanced in Settings).
    static func routes(current: TranscriptionRoute) -> [MenuChoice] {
        TranscriptionRoute.allCases.filter { !$0.isAdvanced || $0 == current }.map {
            MenuChoice(title: $0.title, value: $0.rawValue, subtitle: $0.note)
        }
    }

    /// Builds the whole menu into `menu`, replacing its items.
    func build(into menu: NSMenu, target: StatusMenuActions?) {
        menu.removeAllItems()
        for item in topItems(target: target) + [.separator()] + settingItems(target: target) + [.separator()] {
            menu.addItem(item)
        }
        menu.addItem(
            .action("Settings…", target: target, action: #selector(StatusMenuActions.openSettings), keyEquivalent: ","))
        menu.addItem(.action("About kotoba", target: target, action: #selector(StatusMenuActions.showAbout)))
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: "Quit kotoba", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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

    /// Menus for the snapshot run's `menu-<name>.txt`: ready, setup not complete, listening, and failed with a
    /// retry waiting.
    static func samples() -> [(name: String, model: Self)] {
        let mics = [MenuChoice(title: "MacBook Pro Microphone", value: "builtin")]
        let context = StatusContext(provider: .openRouter)
        func route(_ route: TranscriptionRoute) -> MenuChoice {
            MenuChoice(title: route.menuTitle, value: route.rawValue)
        }
        var ready = Self(
            status: .text(StatusText.ready), microphones: mics, microphoneInUse: ("builtin", "MacBook Pro Microphone"),
            routes: routes(current: .openRouterMAI), route: route(.openRouterMAI))
        var setup = ready
        setup.status = .finishSetup(Readiness.Missing.setup(.key, .openRouter).setupText)
        var listening = ready
        listening.status = .text(DictationState.recording(isLong: false).statusText(context) ?? "")
        ready.recovered = [MenuChoice(title: "Send the draft to the team by Friday", value: "1")]
        ready.hasLastDictation = true
        ready.hasRawLastDictation = true
        ready.suggestionCount = 2
        var failed = ready
        failed.status = .text(DictationState.failed(DictationID()).statusText(context) ?? "")
        failed.pendingCount = 2
        failed.routes = routes(current: .xaiGrok)
        failed.route = route(.xaiGrok)
        failed.grok = Grok(isFormatOn: true, keepsFillerWords: false)
        var bluetooth = listening
        bluetooth.microphones.append(MenuChoice(title: "AirPods Pro", value: "airpods"))
        bluetooth.microphoneInUse = ("airpods", "AirPods Pro")
        bluetooth.microphoneWarning = .bluetoothMic(interruptsPlayback: true)
        return [
            ("ready", ready), ("setup", setup), ("listening", listening), ("failed", failed), ("bluetooth", bluetooth),
        ]
    }

    /// The menu as text, one item per line (submenu items indented, subtitles after "·"), for snapshot runs.
    func text() -> String {
        let menu = NSMenu()
        menu.autoenablesItems = false
        build(into: menu, target: nil)
        return Self.lines(of: menu, depth: 0).joined(separator: "\n") + "\n"
    }

    private static func lines(of menu: NSMenu, depth: Int) -> [String] {
        menu.items.flatMap { item -> [String] in
            let indent = String(repeating: "    ", count: depth)
            guard !item.isSeparatorItem else { return [indent + "---"] }
            var line = indent + item.title
            if let subtitle = item.subtitle { line += " · " + subtitle }
            if item.state == .on { line += " [on]" }
            if !item.isEnabled { line += " (disabled)" }
            if let submenu = item.submenu { return [line + " ▸"] + lines(of: submenu, depth: depth + 1) }
            return [line]
        }
    }
}

/// The menu bar item: its icon, and its menu, built fresh from `model()` each time it opens.
@MainActor
final class StatusBarItem: NSObject, NSMenuDelegate {
    /// M10 with the kotoba mark (design/icon/): the full mark when ready, a dot while setup is not complete or a
    /// dictation waits for a retry, and a caret that blinks while listening. Template images from
    /// App/Assets.xcassets, so they follow the menu bar's appearance.
    enum Icon {
        case ready
        case needsAttention
        case listening
    }

    var icon = Icon.ready {
        didSet {
            if icon != oldValue { showIcon() }
        }
    }

    /// One blink phase, about half a second each, as a text caret blinks.
    private static let blinkPhase = Duration.milliseconds(530)

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: () -> MenuModel?
    private weak var target: StatusMenuActions?
    /// Runs only while listening; `showIcon` cancels it on any other state.
    private var blink: Task<Void, Never>?

    init(target: StatusMenuActions, model: @escaping () -> MenuModel?) {
        self.target = target
        self.model = model
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        showIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model()?.build(into: menu, target: target)
    }

    /// Loaded once each, so an icon change during a dictation builds no image.
    private static let idle = glyph("MenuBarIdle")
    private static let caretOff = glyph("MenuBarListening")
    private static let attention = glyph("MenuBarAttention")

    private static func glyph(_ name: String) -> NSImage? {
        let image = NSImage(named: name)
        image?.accessibilityDescription = "kotoba"
        return image
    }

    private func showIcon() {
        blink?.cancel()
        blink = nil
        switch icon {
        case .ready:
            item.button?.image = Self.idle
        case .needsAttention:
            item.button?.image = Self.attention
        case .listening:
            item.button?.image = Self.idle
            blink = Task { [weak self] in
                var isCaretOn = true
                while true {
                    do {
                        try await Task.sleep(for: Self.blinkPhase)
                    } catch {
                        return
                    }
                    isCaretOn.toggle()
                    self?.item.button?.image = isCaretOn ? Self.idle : Self.caretOff
                }
            }
        }
    }
}

extension StatusBarItem {
    /// The menu bar glyphs at 2x, in state order: ready, needs attention, listening (caret on), listening (caret
    /// off). Tinted like the menu bar, so each appearance shows its contrast.
    static func snapshots() -> [Snapshot] {
        [
            Snapshot(name: "menubar-icons") {
                let views = [idle, attention, idle, caretOff].map { image in
                    let view = NSImageView(image: image ?? NSImage())
                    view.imageScaling = .scaleProportionallyUpOrDown
                    view.contentTintColor = .labelColor
                    view.widthAnchor.constraint(equalToConstant: 36).isActive = true
                    view.heightAnchor.constraint(equalToConstant: 36).isActive = true
                    return view
                }
                let row = NSStackView(views: views)
                row.spacing = 16
                row.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
                return row
            }
        ]
    }
}
