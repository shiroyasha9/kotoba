import Testing

@testable import KotobaCore

/// Which pane the main window opens at, and which one a selection shows.
struct PaneSelectionTests {
    enum Pane: Hashable, Sendable { case home, history, activity, speech }

    func opened(_ panes: Set<Pane> = [.home, .history, .activity, .speech]) -> PaneSelection<Pane> {
        PaneSelection<Pane>(panes: panes, showing: nil, last: nil, home: .home)
    }

    @Test func aFirstWindowShowsHome() {
        #expect(opened().current == .home)
    }

    @Test func aWindowOpensAtTheLastPaneShown() {
        let selection = PaneSelection<Pane>(panes: [.home, .activity], showing: nil, last: .activity, home: .home)

        #expect(selection.current == .activity)
    }

    @Test func aNamedPaneWinsOverTheLastOne() {
        let selection = PaneSelection<Pane>(
            panes: [.home, .activity, .speech], showing: .speech, last: .activity, home: .home)

        #expect(selection.current == .speech)
    }

    /// History is missing when the history database did not open.
    @Test func aPaneTheWindowLacksFallsBackToTheNextChoice() {
        #expect(
            PaneSelection<Pane>(panes: [.home, .activity], showing: .history, last: .activity, home: .home).current
                == .activity)
        #expect(PaneSelection<Pane>(panes: [.home], showing: .history, last: .activity, home: .home).current == .home)
    }

    @Test func aSelectionShowsItsPane() {
        var selection = opened()

        selection.select(.history)

        #expect(selection.current == .history)
    }

    @Test func aPaneTheWindowLacksIsNotSelected() {
        var selection = opened([.home, .activity])

        selection.select(.history)

        #expect(selection.current == .home)
    }

    /// ⌘-click on the shown sidebar row sends nil.
    @Test func aDeselectKeepsThePaneShown() {
        var selection = opened()
        selection.select(.activity)

        selection.select(nil)

        #expect(selection.current == .activity)
    }
}
