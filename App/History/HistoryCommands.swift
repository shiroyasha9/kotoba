import AppKit
import KotobaCore

/// One action on History's selected rows. The rows' context menu and the menu bar's Dictation menu (as Mail's Message
/// menu) are both built from these, with the same checks, so every action also has a keyboard path.
enum HistoryCommand: CaseIterable {
    case copy
    case copyWithoutCleanup
    case pasteAgain
    case fix
    case retry
    case transcribeAgain
    case play
    case viewChanges
    case showInFinder
    case delete

    /// The context menu's groups: the text, then the audio and the changes, then Delete.
    static let groups: [[Self]] = [
        [.copy, .copyWithoutCleanup, .pasteAgain, .fix],
        [.retry, .transcribeAgain, .play, .viewChanges, .showInFinder],
        [.delete],
    ]

    /// The menu bar's key equivalent, only where macOS has a standard one: Music's and Photos' Show in Finder (⇧⌘R),
    /// Finder's and Photos' delete (⌘⌫). Copy is Edit > Copy (⌘C); Space plays from the list.
    var keyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .showInFinder: ("r", [.command, .shift])
        case .delete: ("\u{8}", [.command])
        default: nil
        }
    }
}

extension HistoryModel {
    func title(of command: HistoryCommand, for records: [DictationRecord]) -> String {
        Self.title(of: command, isPlaying: isPlaying(records))
    }

    static func title(of command: HistoryCommand, isPlaying: Bool) -> String {
        switch command {
        case .copy: "Copy"
        case .copyWithoutCleanup: "Copy Without Cleanup"
        case .pasteAgain: "Paste Again"
        case .fix: "Fix…"
        case .retry: "Retry"
        case .transcribeAgain: "Transcribe Again"
        case .play: isPlaying ? "Stop Audio" : "Play Audio"
        case .viewChanges: "View Changes…"
        case .showInFinder: "Show Audio in Finder"
        case .delete: "Delete…"
        }
    }

    /// Whether the context menu shows the item for these rows: an item that cannot apply to them (Retry on a row with
    /// text) is left out. A row with no text joins the retry queue; one row with text is transcribed again.
    func offers(_ command: HistoryCommand, for records: [DictationRecord]) -> Bool {
        switch command {
        case .copy, .pasteAgain, .delete: !records.isEmpty
        case .copyWithoutCleanup: records.contains { LastDictation.rawText(of: $0) != nil }
        case .fix: canFix(records)
        case .retry: canRetry(records)
        case .transcribeAgain: !canRetry(records) && againRecord(records) != nil
        case .play: isPlaying(records) || audioRecord(records) != nil
        case .viewChanges: canViewChanges(records)
        case .showInFinder: audioRecord(records) != nil
        }
    }

    /// Whether an offered item can run now (Paste Again waits while a dictation is sent).
    func canRun(_ command: HistoryCommand, on records: [DictationRecord]) -> Bool {
        guard offers(command, for: records) else { return false }
        switch command {
        case .copy: return Self.hasText(records)
        case .pasteAgain: return canPasteAgain(records)
        case .transcribeAgain: return canTranscribeAgain(records)
        case .play: return isPlaying(records) || canPlay(records)
        case .delete: return canDelete(records)
        case .copyWithoutCleanup, .fix, .retry, .viewChanges, .showInFinder: return true
        }
    }

    func run(_ command: HistoryCommand, on records: [DictationRecord]) {
        guard canRun(command, on: records) else { return }
        apply(command, on: records)
    }

    private func apply(_ command: HistoryCommand, on records: [DictationRecord]) {
        switch command {
        case .copy: copy(records)
        case .copyWithoutCleanup: copy(records, raw: true)
        case .pasteAgain: pasteAgain(records)
        case .fix: fix(records)
        case .retry: retry(records)
        case .transcribeAgain: transcribeAgain(records)
        case .play: togglePlay(records)
        case .viewChanges: viewChanges(records)
        case .showInFinder: showInFinder(records)
        case .delete: askToDelete(records)
        }
    }

    /// Transcribe Again keeps no copy of the old text: the audio is what can bring a text back.
    static let transcribeAgainHelp =
        "Send the saved audio again and replace this text with the result."
}

/// The menu bar's Dictation menu: History's actions on the selected rows, on while History is shown in the key
/// window, as Mail's Message menu acts on the selected messages. Copy stays in Edit (⌘C). Built once; each item's title
/// and state follow the selection when the menu opens or a key equivalent is pressed (`validateMenuItem`).
@MainActor
final class HistoryMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    let menu = NSMenu(title: "Dictation")
    /// The History page's model while it is shown in the key window; nil otherwise.
    private let shown: @MainActor () -> HistoryModel?
    private let transcribeAgainWith = NSMenu(title: "Transcribe Again With")

    init(shown: @escaping @MainActor () -> HistoryModel?) {
        self.shown = shown
        super.init()
        menu.autoenablesItems = true
        for (index, group) in HistoryCommand.groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for command in group where command != .copy {
                menu.addItem(item(for: command))
                if command == .transcribeAgain {
                    let with = NSMenuItem(title: transcribeAgainWith.title, action: nil, keyEquivalent: "")
                    with.submenu = transcribeAgainWith
                    menu.addItem(with)
                }
            }
        }
        transcribeAgainWith.delegate = self
    }

    private func item(for command: HistoryCommand) -> NSMenuItem {
        let item = NSMenuItem(
            title: HistoryModel.title(of: command, isPlaying: false), action: #selector(runCommand(_:)),
            keyEquivalent: command.keyEquivalent?.key ?? "")
        item.keyEquivalentModifierMask = command.keyEquivalent?.modifiers ?? []
        item.target = self
        item.representedObject = Command(command)
        return item
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let model = shown(), let command = (sender.representedObject as? Command)?.command else { return }
        model.run(command, on: model.selected)
    }

    @objc private func transcribeAgain(with sender: NSMenuItem) {
        guard let model = shown(), let route = sender.representedObject as? String else { return }
        model.transcribeAgain(model.selected, model: route)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let model = shown() else { return false }
        if menuItem.action == #selector(transcribeAgain(with:)) {
            return model.canTranscribeAgain(model.selected)
        }
        guard let command = (menuItem.representedObject as? Command)?.command else { return false }
        menuItem.title = model.title(of: command, for: model.selected)
        return model.canRun(command, on: model.selected)
    }

    /// The submenu opens: one item for each other speech model that can send now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for choice in shown()?.otherSpeechModels ?? [] {
            let item = NSMenuItem(title: choice.title, action: #selector(transcribeAgain(with:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.value
            menu.addItem(item)
        }
    }

    /// `representedObject` holds an object; a Swift enum case is boxed in one.
    private final class Command: NSObject {
        let command: HistoryCommand
        init(_ command: HistoryCommand) { self.command = command }
    }
}
