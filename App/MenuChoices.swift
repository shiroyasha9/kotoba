import AppKit
import KotobaCore

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

    /// A line to read, not to click: a title and its subtitle, as the menu's ready lines.
    @MainActor
    static func note(_ title: String, _ subtitle: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.subtitle = subtitle
        item.isEnabled = false
        return item
    }

    /// Shows `chord` on the right as the item's key equivalent, as an app menu shows a shortcut, so the menu teaches
    /// it; true when it does. A menu draws only a key with ⌃⌥⇧⌘, so a modifier-only, mouse, fn or one-side chord
    /// ("right ⌥") shows nothing. The tap swallows a key chord's key, so an open menu never sees it twice.
    @MainActor
    @discardableResult
    func showsChord(_ chord: Chord?) -> Bool {
        guard let chord, let key = Self.keyEquivalent(of: chord), !chord.modifiers.contains(.function) else {
            return false
        }
        let kinds: [(ModifierKeys, NSEvent.ModifierFlags)] = [
            (.control, .control), (.option, .option), (.shift, .shift), (.command, .command),
        ]
        var mask: NSEvent.ModifierFlags = []
        for (kind, flag) in kinds {
            let sides = chord.modifiers.intersection(kind)
            if sides.isEmpty { continue }
            guard sides == kind else { return false }
            mask.insert(flag)
        }
        keyEquivalent = key
        keyEquivalentModifierMask = mask
        return true
    }

    /// The character a menu takes for the chord's key: what the key types (`Chord.keycaps`), or the function key's
    /// code. Nil for a key a menu cannot show.
    private static func keyEquivalent(of chord: Chord) -> String? {
        guard chord.keyCode != nil, let name = chord.keycaps.last else { return nil }
        if let special = specialKeys[name] { return special }
        if name.count == 1 { return name.lowercased() }
        guard name.hasPrefix("F"), let number = Int(name.dropFirst()), (1...20).contains(number) else { return nil }
        return functionKey(NSF1FunctionKey + number - 1)
    }

    private static let specialKeys: [String: String] = [
        "Space": " ", "↩": "\r", "⇥": "\t", "⌫": "\u{8}", "⎋": "\u{1b}",
        "←": functionKey(NSLeftArrowFunctionKey), "→": functionKey(NSRightArrowFunctionKey),
        "↑": functionKey(NSUpArrowFunctionKey), "↓": functionKey(NSDownArrowFunctionKey),
    ].compactMapValues { $0 }

    /// AppKit's private-use character for a function key (`NSF1FunctionKey`, `NSUpArrowFunctionKey`).
    private static func functionKey(_ code: Int) -> String? {
        UnicodeScalar(code).map { String(Character($0)) }
    }
}
