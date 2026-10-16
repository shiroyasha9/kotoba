import Sparkle

/// Sparkle 2 (docs/release.md): reads the appcast once a day while automatic checks are on, and on "Check for
/// Updates…". Started at launch so a check that comes due starts on time; it does no other work at idle.
@MainActor
final class Updater: NSObject {
    /// The updater for the release install. A development build (`make build`, `Install`) gets none: it is never
    /// offered a release, and the menu item and the Updates section hide.
    static func forThisBuild() -> Updater? {
        Install.isRelease ? Updater() : nil
    }

    /// A scheduled check found an update. kotoba is not the active app, so Sparkle's alert opens behind other windows;
    /// the menu bar icon shows a dot and the menu offers "Install Update…" until the user looks at the alert.
    private(set) var hasWaitingUpdate = false {
        didSet {
            if hasWaitingUpdate != oldValue { onWaitingUpdateChange?() }
        }
    }

    var onWaitingUpdateChange: (@MainActor () -> Void)?

    /// Lazy only because it needs `self` as its delegate; `init` builds it, which starts the updater.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)

    private override init() {
        super.init()
        _ = controller
    }

    /// False while Sparkle reads the feed or downloads an update in the background; the menu item is disabled then.
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Starts a check, or brings an update that is already shown to the front. Sparkle activates kotoba itself.
    func check() {
        controller.checkForUpdates(nil)
    }
}

// Sparkle calls these on the main thread.
extension Updater: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            hasWaitingUpdate = true
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        hasWaitingUpdate = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        hasWaitingUpdate = false
    }
}
