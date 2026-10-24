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
}
