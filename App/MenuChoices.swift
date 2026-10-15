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
    /// A main menu with only the standard Edit items. An `LSUIElement` app shows no menu bar, but without
    /// these key equivalents Cmd-X/C/V/A/Z find no action and the Settings text fields beep.
    @MainActor
    static func editOnlyMain() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(editItem)
        return main
    }
}
