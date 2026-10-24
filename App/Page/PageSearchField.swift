import AppKit
import SwiftUI

/// A page's search field, in the page and not in a toolbar (a page has no toolbar, so the title bar keeps one height):
/// AppKit's own search field, with its magnifier, its clear button and Esc to clear. Edit > Find… (⌘F) puts the cursor
/// in it (`findRequests`, with `PaneID.hasSearch` on for the page). On a `PageList`, put it in `pinned`, above the rows; on a `PageForm`, put it alone in the header of the section it searches. Custom: SwiftUI's
/// only search field is `.searchable`, which lives in the toolbar or the sidebar.
struct PageSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    @Environment(\.findRequests) private var findRequests

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.stringValue = text
        field.delegate = context.coordinator
        // The requests made before the page appeared are not for this field.
        context.coordinator.findRequests = findRequests
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.findRequests != findRequests {
            context.coordinator.findRequests = findRequests
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var findRequests = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
