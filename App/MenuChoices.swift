import AppKit

/// One option in a menu-bar submenu.
struct MenuChoice {
    let title: String
    /// Carried as the item's `representedObject`, for the action to read.
    let value: String
    var subtitle: String?
}

extension NSMenuItem {
    /// A submenu of `choices` with the `selected` value checked, as the menu bar's pickers use.
    @MainActor
    static func choices(
        _ title: String,
        subtitle: String? = nil,
        _ choices: [MenuChoice],
        selected: String?,
        target: AnyObject?,
        action: Selector
    ) -> NSMenuItem {
        let submenu = NSMenu()
        for choice in choices {
            let item = NSMenuItem(title: choice.title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = choice.value
            item.state = choice.value == selected ? .on : .off
            item.subtitle = choice.subtitle
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.subtitle = subtitle
        parent.submenu = submenu
        return parent
    }

    /// A plain action item.
    @MainActor
    static func action(_ title: String, target: AnyObject?, action: Selector, keyEquivalent: String = "") -> NSMenuItem
    {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        return item
    }

    /// An on/off item.
    @MainActor
    static func toggle(
        _ title: String, isOn: Bool, target: AnyObject?, action: Selector
    ) -> NSMenuItem {
        let item = Self.action(title, target: target, action: action)
        item.state = isOn ? .on : .off
        return item
    }
}

extension NSMenu {
    /// A main menu with the standard File > Close and Edit items. An `LSUIElement` app shows no menu bar, but without
    /// these key equivalents Cmd-W, Cmd-X/C/V/A/Z and Cmd-F find no action and the windows beep. Find… goes along the
    /// responder chain to the key window's delegate; the History window answers it by focusing its search field.
    @MainActor
    static func hiddenMain() -> NSMenu {
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
        let main = NSMenu()
        for (title, menu) in [("File", file), ("Edit", edit)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        return main
    }
}
