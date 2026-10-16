import AppKit

/// The main menu: kotoba, File, Edit, Window and Help. AppKit shows the first item as the app menu, so it comes
/// first; it holds About, Settings…, Hide and Quit (⌘Q) for the Dock app (story 35). The menu bar shows the menu only
/// while kotoba is in the Dock, but its key equivalents work in every kotoba window: without File > Close and the
/// Edit items, ⌘W and ⌘X/C/V/A/Z find no action in a text field and macOS beeps. Find… goes along the responder chain
/// to the key window's delegate; the main window answers it by focusing the shown pane's search field.
///
/// The app menu's own items have no target, so they go along the responder chain to the app delegate
/// (`StatusMenuActions`). Its update item is the menu bar menu's (`MenuModel.updateItem`), built again from the same
/// model each time the app menu opens: "Install Update…" while an update waits, disabled while Sparkle is busy.
@MainActor
final class MainMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    let services = NSMenu(title: "Services")
    let window = NSMenu(title: "Window")
    /// No items: AppKit adds its Search field.
    let help = NSMenu(title: "Help")
    /// The update item's state, as the menu bar menu reads it; nil in a Debug build, which has no updater.
    private let updates: @MainActor () -> MenuModel.Updates?
    private weak var target: StatusMenuActions?
    private var updateItem: NSMenuItem?

    init(target: StatusMenuActions?, updates: @escaping @MainActor () -> MenuModel.Updates?) {
        self.target = target
        self.updates = updates
        super.init()
        let name = Install.displayName
        let app = NSMenu(title: name)
        app.delegate = self
        app.addItem(withTitle: "About \(name)", action: #selector(StatusMenuActions.showAbout), keyEquivalent: "")
        if let updates = updates() {
            let item = MenuModel.updateItem(updates, target: target)
            app.addItem(item)
            updateItem = item
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(StatusMenuActions.openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = app.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        app.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(
            withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        for (title, submenu) in [
            (name, app), ("File", file), ("Edit", Self.edit()), ("Window", window), ("Help", help),
        ] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
        }
    }

    /// The app menu opens: its update item follows the updater's state now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let old = updateItem, let updates = updates() else { return }
        let item = MenuModel.updateItem(updates, target: target)
        let index = menu.index(of: old)
        menu.removeItem(at: index)
        menu.insertItem(item, at: index)
        updateItem = item
    }

    /// Sets the menu as the app's main menu, with its Services, Window and Help menus.
    func install() {
        NSApp.mainMenu = menu
        NSApp.servicesMenu = services
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
    }

    private static func edit() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "Find")
        let findItem = find.addItem(
            withTitle: "Find…", action: #selector(NSResponder.performTextFinderAction(_:)), keyEquivalent: "f")
        findItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        edit.addItem(withTitle: "Find", action: nil, keyEquivalent: "").submenu = find
        return edit
    }
}
