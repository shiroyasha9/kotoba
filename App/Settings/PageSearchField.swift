import AppKit
import SwiftUI

/// The system search field in a page, as the first row of the list it filters: a page has no toolbar, so it cannot
/// use `.searchable` (CODING_STANDARDS.md, Pages). Each change of `focusRequests` (Edit > Find…, ⌘F) puts the cursor in
/// it. Custom: SwiftUI has no search field outside a toolbar or sidebar.
struct PageSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let focusRequests: Int

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusRequests != focusRequests {
            context.coordinator.focusRequests = focusRequests
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, focusRequests: focusRequests)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        /// The request already answered: the field takes focus only on a new one, not when it appears.
        var focusRequests: Int

        init(text: Binding<String>, focusRequests: Int) {
            self.text = text
            self.focusRequests = focusRequests
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
