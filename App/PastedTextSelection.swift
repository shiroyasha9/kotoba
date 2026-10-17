import AppKit
import ApplicationServices
import Carbon
import KotobaCore

/// Polish's selector (`PastedTextSelector`): finds the text kotoba pasted in the focused field through Accessibility
/// and selects it, so the next ⌘V replaces it. It uses the Accessibility grant the paste already has. Each call runs
/// on a short-lived thread of its own (`SessionThread`), never the main thread, so a hung app cannot stall the UI;
/// nothing runs between Polish requests. The text stays in memory and is never logged.
///
/// It selects only in an editable field (its value and selection can be set): a terminal's text area is read-only,
/// and a ⌘V there pastes at the prompt, not over a selection. The selection is read back before it counts, so an app
/// that reports success and selects nothing (Electron's false successes) leaves the old selection, and Polish tries
/// Backspace or the clipboard (`PolishPlacement`).
struct AXPastedTextSelector: PastedTextSelector {
    /// Longer fields are not read (UTF-16 units): a whole document read through Accessibility takes long.
    private static let maxLength = 200_000

    func select(_ text: String, in app: DictationApp?) async -> Bool {
        guard let front = FrontAppObserver.current, front.processID != ProcessInfo.processInfo.processIdentifier,
            app == nil || app?.bundleID == front.app?.bundleID
        else { return false }
        let thread = await SessionThread.start()
        defer { thread.stop() }
        let isSelected = await thread.run { Self.select(text, pid: front.processID) } ?? false
        Log.app.info("Polish: the text to replace is \(isSelected ? "selected" : "not found", privacy: .public)")
        return isSelected
    }

    /// On the session thread.
    private static func select(_ text: String, pid: pid_t) -> Bool {
        let interval = KotobaCore.Log.signposter.beginInterval("polish select")
        defer { KotobaCore.Log.signposter.endInterval("polish select", interval) }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return false }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXFocusedField.timeout)
        guard let element = attribute(kAXFocusedUIElementAttribute, of: application, as: AXUIElementGetTypeID())
        else { return false }
        let field = unsafeDowncast(element, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(field, AXFocusedField.timeout)
        // The length first: it is one number, and the value is copied whole.
        guard attribute(kAXSubroleAttribute, of: field) as? String != kAXSecureTextFieldSubrole,
            isSettable(kAXValueAttribute, of: field), isSettable(kAXSelectedTextRangeAttribute, of: field),
            let length = AXFocusedField.characterCount(of: field), length <= maxLength,
            let value = attribute(kAXValueAttribute, of: field) as? String,
            let range = onlyRange(of: text, in: value), let old = AXFocusedField.selectedRange(of: field)
        else { return false }
        guard setSelectedRange(range, of: field) else { return false }
        if attribute(kAXSelectedTextAttribute, of: field) as? String == text { return true }
        _ = setSelectedRange(old, of: field)
        return false
    }

    private static func attribute(_ name: String, of element: AXUIElement, as typeID: CFTypeID? = nil) -> CFTypeRef? {
        AXFocusedField.attribute(name, of: element, as: typeID)
    }

    /// The UTF-16 range of `text` in `value` when it is there exactly once: a second copy could be the owner's own.
    private static func onlyRange(of text: String, in value: String) -> CFRange? {
        let ranges = value.ranges(of: text)
        guard ranges.count == 1, let found = ranges.first else { return nil }
        let range = NSRange(found, in: value)
        return CFRange(location: range.location, length: range.length)
    }

    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    private static func setSelectedRange(_ range: CFRange, of element: AXUIElement) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
    }
}
