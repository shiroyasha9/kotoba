import AppKit
import ApplicationServices
import Carbon
import KotobaCore
import Synchronization

/// Polish's selector (`PastedTextSelector`): finds the text kotoba pasted in the focused field through Accessibility
/// and selects it, so the next ⌘V replaces it. It uses the Accessibility grant the paste already has. Each call runs
/// on a short-lived thread of its own (`SessionThread`), never the main thread, so a hung app cannot stall the UI;
/// nothing runs between Polish requests. The text stays in memory and is never logged.
///
/// It selects only in an editable field (its value and selection can be set): a terminal's text area is read-only,
/// and a ⌘V there pastes at the prompt, not over a selection. The selection is read back before it counts, so an app
/// that reports success and selects nothing (Electron's false successes) leaves the old selection, and Polish tries
/// Backspace or the clipboard (`PolishPlacement`).
final class AXPastedTextSelector: PastedTextSelector {
    /// Longer fields are not read (UTF-16 units): a whole document read through Accessibility takes long.
    private static let maxLength = 200_000

    /// The field, the selection the last `select` replaced, and the one it set, for `restoreSelection`.
    private struct Change: @unchecked Sendable {
        // @unchecked: AXUIElement is a CF type that is safe to use from any thread; Swift does not mark it Sendable.
        let field: AXUIElement
        let old: CFRange
        let set: CFRange
        let text: String
    }

    private let lastChange = Mutex<Change?>(nil)

    func select(_ text: String, in app: DictationApp?) async -> SelectionResult {
        lastChange.withLock { $0 = nil }
        guard let front = FrontAppObserver.current, front.processID != FrontAppObserver.ownProcessID,
            app == nil || app?.bundleID == front.app?.bundleID
        else { return .untouched }
        let (result, change) = await run { Self.select(text, pid: front.processID) } ?? (.untouched, nil)
        lastChange.withLock { $0 = change }
        Log.app.info("Polish: the text to replace is \(String(describing: result), privacy: .public)")
        return result
    }

    /// Only while the field still has exactly the selection `select` set: a change since then (a key, a paste) makes
    /// the old range point at other text.
    func restoreSelection() async {
        guard let change = lastChange.withLock({ $0.take() }) else { return }
        _ = await run {
            let now = AXFocusedField.selectedRange(of: change.field)
            guard now?.location == change.set.location, now?.length == change.set.length,
                Self.attribute(kAXSelectedTextAttribute, of: change.field) as? String == change.text
            else { return }
            _ = Self.setSelectedRange(change.old, of: change.field)
        }
    }

    /// Runs `work` on a short-lived thread of its own.
    private func run<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result? {
        let thread = await SessionThread.start()
        defer { thread.stop() }
        return await thread.run(work)
    }

    /// On the session thread. A selection that cannot be read back as `text` is put back; `.changed` when that fails
    /// too, so Polish never presses Backspace at an insertion point it moved.
    private static func select(_ text: String, pid: pid_t) -> (SelectionResult, Change?) {
        let interval = KotobaCore.Log.signposter.beginInterval("polish select")
        defer { KotobaCore.Log.signposter.endInterval("polish select", interval) }
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else { return (.untouched, nil) }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXFocusedField.timeout)
        guard let element = attribute(kAXFocusedUIElementAttribute, of: application, as: AXUIElementGetTypeID())
        else { return (.untouched, nil) }
        let field = unsafeDowncast(element, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(field, AXFocusedField.timeout)
        // The length first: it is one number, and the value is copied whole.
        guard attribute(kAXSubroleAttribute, of: field) as? String != kAXSecureTextFieldSubrole,
            isSettable(kAXValueAttribute, of: field), isSettable(kAXSelectedTextRangeAttribute, of: field),
            let length = AXFocusedField.characterCount(of: field), length <= maxLength,
            let value = attribute(kAXValueAttribute, of: field) as? String,
            let range = onlyRange(of: text, in: value), let old = AXFocusedField.selectedRange(of: field)
        else { return (.untouched, nil) }
        if setSelectedRange(range, of: field), attribute(kAXSelectedTextAttribute, of: field) as? String == text {
            return (.selected, Change(field: field, old: old, set: range, text: text))
        }
        _ = setSelectedRange(old, of: field)
        let now = AXFocusedField.selectedRange(of: field)
        return (now?.location == old.location && now?.length == old.length ? .untouched : .changed, nil)
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
