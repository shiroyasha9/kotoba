import Testing

@testable import KotobaCore

struct AppPresenceTests {
    /// Stands in for an NSWindow: only its identity counts.
    private final class Window {}

    @Test(arguments: [(true, true), (true, false), (false, true)])
    func aSavedChoiceIsKept(showsInDock: Bool, showsMenuBarIcon: Bool) {
        let presence = AppPresence(showsInDock: showsInDock, showsMenuBarIcon: showsMenuBarIcon)
        #expect(presence.showsInDock == showsInDock)
        #expect(presence.showsMenuBarIcon == showsMenuBarIcon)
    }

    /// A saved state with both off (an edit of the defaults by hand) gets the menu bar icon back.
    @Test func bothOffAtLaunchShowsTheMenuBarIcon() {
        let presence = AppPresence(showsInDock: false, showsMenuBarIcon: false)
        #expect(!presence.showsInDock)
        #expect(presence.showsMenuBarIcon)
    }

    @Test func eitherIconCanGoWhileTheOtherStays() {
        var presence = AppPresence(showsInDock: true, showsMenuBarIcon: true)
        #expect(presence.canHideDockIcon && presence.canHideMenuBarIcon)
        presence.setShowsInDock(false)
        #expect(!presence.showsInDock && presence.showsMenuBarIcon)

        presence = AppPresence(showsInDock: true, showsMenuBarIcon: true)
        presence.setShowsMenuBarIcon(false)
        #expect(presence.showsInDock && !presence.showsMenuBarIcon)
    }

    @Test func theLastIconCannotGo() {
        var presence = AppPresence(showsInDock: false, showsMenuBarIcon: true)
        #expect(!presence.canHideMenuBarIcon)
        presence.setShowsMenuBarIcon(false)
        #expect(presence.showsMenuBarIcon)

        presence = AppPresence(showsInDock: true, showsMenuBarIcon: false)
        #expect(!presence.canHideDockIcon)
        presence.setShowsInDock(false)
        #expect(presence.showsInDock)
    }

    @Test func showInDockOnKeepsKotobaInTheDock() {
        let window = Window()
        var presence = AppPresence(showsInDock: true, showsMenuBarIcon: true)
        #expect(presence.isInDock)
        presence.windowOpened(ObjectIdentifier(window))
        presence.windowClosed(ObjectIdentifier(window))
        presence.deactivated()
        #expect(presence.isInDock)
    }

    /// Show in Dock off (owner, 2026-10-16): in the Dock from the click that asks for a window until its last window
    /// closes.
    @Test func showInDockOffIsInTheDockWhileAWindowIsOpen() {
        let main = Window()
        let fix = Window()
        var presence = AppPresence(showsInDock: false, showsMenuBarIcon: true)
        #expect(!presence.isInDock)

        presence.windowRequested()
        #expect(presence.isInDock)
        presence.windowOpened(ObjectIdentifier(main))
        presence.deactivated()
        #expect(presence.isInDock)

        presence.windowRequested()
        presence.windowOpened(ObjectIdentifier(fix))
        presence.windowClosed(ObjectIdentifier(main))
        #expect(presence.isInDock)
        presence.windowClosed(ObjectIdentifier(fix))
        #expect(!presence.isInDock)
    }

    /// A request that shows no window keeps the Dock icon only while kotoba is active.
    @Test func aRequestWithNoWindowEndsWhenKotobaIsNoLongerActive() {
        var presence = AppPresence(showsInDock: false, showsMenuBarIcon: true)
        presence.windowRequested()
        #expect(presence.isInDock)
        presence.deactivated()
        #expect(!presence.isInDock)
    }

    @Test func aWindowShownAgainCountsOnce() {
        let main = Window()
        var presence = AppPresence(showsInDock: false, showsMenuBarIcon: true)
        presence.windowOpened(ObjectIdentifier(main))
        presence.windowOpened(ObjectIdentifier(main))
        presence.windowClosed(ObjectIdentifier(main))
        #expect(!presence.isInDock)
    }

    @Test func turningShowInDockOffWithAWindowOpenWaitsForItToClose() {
        let main = Window()
        var presence = AppPresence(showsInDock: true, showsMenuBarIcon: true)
        presence.windowOpened(ObjectIdentifier(main))
        presence.setShowsInDock(false)
        #expect(presence.isInDock)
        presence.windowClosed(ObjectIdentifier(main))
        #expect(!presence.isInDock)
    }

    @Test func aUserLaunchOpensTheMainWindowAndALoginLaunchNone() {
        #expect(AppPresence.window(at: .user, needsOnboarding: false) == .main)
        #expect(AppPresence.window(at: .login, needsOnboarding: false) == nil)
    }

    /// Onboarding opens at every launch until it is done, as before story 35: kotoba cannot dictate without it.
    @Test func onboardingComesFirstUntilItIsDone() {
        #expect(AppPresence.window(at: .user, needsOnboarding: true) == .onboarding)
        #expect(AppPresence.window(at: .login, needsOnboarding: true) == .onboarding)
    }

    @Test func aReopenAfterOnboardingShowsTheMainWindow() {
        #expect(
            AppPresence.reopenWindow(needsOnboarding: false, isOnboardingOpen: false, isOnboardingDone: true) == .main)
        // "Finish Setting Up kotoba…" opened onboarding again after its Done.
        #expect(
            AppPresence.reopenWindow(needsOnboarding: false, isOnboardingOpen: true, isOnboardingDone: true) == .main)
    }

    /// Owner QA 2, R5: onboarding was minimised on Try It (both grants and a key, so a launch would not open it) and a
    /// Dock click opened the main window.
    @Test func aReopenDuringOnboardingBringsBackOnboarding() {
        #expect(
            AppPresence.reopenWindow(needsOnboarding: false, isOnboardingOpen: true, isOnboardingDone: false)
                == .onboarding)
        // Closed before setup was done: a launch would open it, and so does a reopen.
        #expect(
            AppPresence.reopenWindow(needsOnboarding: true, isOnboardingOpen: false, isOnboardingDone: false)
                == .onboarding)
    }

    /// Closed once setup was done but before Done: a launch would open the main window, and so does a reopen.
    @Test func aReopenAfterOnboardingClosedWhenSetUpShowsTheMainWindow() {
        #expect(
            AppPresence.reopenWindow(needsOnboarding: false, isOnboardingOpen: false, isOnboardingDone: false) == .main)
    }

    @Test func theBadgeCountsWaitingDictationsAndHidesAtZero() {
        #expect(AppPresence.badge(waiting: 0) == nil)
        #expect(AppPresence.badge(waiting: 1) == "1")
        #expect(AppPresence.badge(waiting: 12) == "12")
    }
}
