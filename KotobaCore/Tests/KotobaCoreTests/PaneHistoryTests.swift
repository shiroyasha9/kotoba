import Testing

@testable import KotobaCore

/// Which pane the main window opens at, and how Back and Forward move through the shown panes.
struct PaneHistoryTests {
    enum Pane: Hashable, Sendable { case home, history, usage, speech }

    func opened(_ panes: Set<Pane> = [.home, .history, .usage, .speech]) -> PaneHistory<Pane> {
        PaneHistory<Pane>(panes: panes, showing: nil, last: nil, home: .home)
    }

    @Test func aFirstWindowShowsHome() {
        #expect(opened().current == .home)
    }

    @Test func aWindowOpensAtTheLastPaneShown() {
        let history = PaneHistory<Pane>(panes: [.home, .usage], showing: nil, last: .usage, home: .home)

        #expect(history.current == .usage)
        #expect(history.back.isEmpty)
    }

    @Test func aNamedPaneWinsOverTheLastOne() {
        let history = PaneHistory<Pane>(panes: [.home, .usage, .speech], showing: .speech, last: .usage, home: .home)

        #expect(history.current == .speech)
        #expect(history.back.isEmpty)
    }

    /// History is missing when the history database did not open.
    @Test func aPaneTheWindowLacksFallsBackToTheNextChoice() {
        #expect(
            PaneHistory<Pane>(panes: [.home, .usage], showing: .history, last: .usage, home: .home).current == .usage)
        #expect(PaneHistory<Pane>(panes: [.home], showing: .history, last: .usage, home: .home).current == .home)
    }

    @Test func backAndForwardRetraceTheShownPanes() {
        var history = opened()
        history.select(.history)
        history.select(.usage)

        history.goBack()
        #expect(history.current == .history)
        history.goBack()
        #expect(history.current == .home)
        #expect(history.back.isEmpty)
        history.goForward()
        history.goForward()
        #expect(history.current == .usage)
        #expect(history.forward.isEmpty)
        #expect(history.back == [.home, .history])
    }

    @Test func aNewPaneAfterBackEmptiesForward() {
        var history = opened()
        history.select(.history)
        history.goBack()

        history.select(.speech)

        #expect(history.forward.isEmpty)
        #expect(history.back == [.home])
    }

    @Test func selectingTheShownPaneAddsNoStep() {
        var history = opened()

        history.select(.home)

        #expect(history.back.isEmpty)
    }

    @Test func aPaneTheWindowLacksIsNotSelected() {
        var history = opened([.home, .usage])

        history.select(.history)

        #expect(history.current == .home)
        #expect(history.back.isEmpty)
    }

    /// ⌘-click on the shown sidebar row sends nil.
    @Test func aDeselectKeepsThePaneShown() {
        var history = opened()
        history.select(.usage)

        history.select(nil)

        #expect(history.current == .usage)
        #expect(history.back == [.home])
    }

    @Test func backAndForwardAtTheEndsChangeNothing() {
        var history = opened()

        history.goBack()
        history.goForward()

        #expect(history == opened())
    }
}
