import SwiftUI

// A page's controls in the window toolbar, always in view as in Mail, Notes and Passwords (owner QA 1, Q12): its search,
// and its buttons (Dictionary's + and Import). The window keeps its toolbar on every page (`MainView`), so a page with
// toolbar items does not change the title bar's height.

extension View {
    /// The page's search field in the window toolbar, at its trailing end. Edit > Find… (⌘F) puts the cursor in it (set
    /// `PaneID.hasSearch` for the page so Find is on).
    func pageSearch(text: Binding<String>, prompt: String) -> some View {
        modifier(PageSearch(text: text, prompt: prompt))
    }

    /// The page's buttons in the window toolbar, before its search: a symbol button with its title as the help tag and
    /// VoiceOver label (`Button("Add Word", systemImage: "plus")`), or a menu.
    func pageToolbar<Items: View>(@ViewBuilder _ items: @escaping () -> Items) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                items()
            }
        }
    }
}

private struct PageSearch: ViewModifier {
    @Binding var text: String
    let prompt: String
    @Environment(\.findRequests) private var findRequests
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .searchable(text: $text, placement: .toolbar, prompt: Text(prompt))
            .searchFocused($isFocused)
            .onChange(of: findRequests) { isFocused = true }
    }
}
