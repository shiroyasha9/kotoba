import AppKit
import KotobaCore

/// The menu bar item: its icon, and its menu, built fresh from `model()` each time it opens.
@MainActor
final class StatusBarItem: NSObject, NSMenuDelegate {
    /// M10 with the kotoba mark (design/icon/): the full mark when ready, a dot when it needs attention, and a caret
    /// that blinks while listening (`ShellStatus.Icon`). Template images from App/Assets.xcassets, so they follow the
    /// menu bar's appearance.
    var icon = ShellStatus.Icon.ready {
        didSet {
            if icon != oldValue { showIcon() }
        }
    }

    /// "Show in menu bar" (`DockAndMenuBar`). A hidden icon does not blink.
    var isShown: Bool {
        get { item.isVisible }
        set {
            guard newValue != item.isVisible else { return }
            item.isVisible = newValue
            showIcon()
        }
    }

    /// One blink phase, about half a second each, as a text caret blinks.
    private static let blinkPhase = Duration.milliseconds(530)

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: () -> MenuModel?
    private weak var target: StatusMenuActions?
    /// Runs only while listening; `showIcon` cancels it on any other state.
    private var blink: Task<Void, Never>?

    init(target: StatusMenuActions, model: @escaping () -> MenuModel?) {
        self.target = target
        self.model = model
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        showIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model()?.build(into: menu, target: target)
    }

    /// Loaded once each, so an icon change during a dictation builds no image. The snapshot run draws them too.
    static let idle = glyph("MenuBarIdle")
    static let caretOff = glyph("MenuBarListening")
    static let attention = glyph("MenuBarAttention")

    private static func glyph(_ name: String) -> NSImage? {
        let image = NSImage(named: name)
        image?.accessibilityDescription = Install.displayName
        return image
    }

    private func showIcon() {
        blink?.cancel()
        blink = nil
        switch icon {
        case .ready:
            item.button?.image = Self.idle
        case .needsAttention:
            item.button?.image = Self.attention
        case .listening:
            item.button?.image = Self.idle
            guard item.isVisible else { return }
            blink = Task { [weak self] in
                var isCaretOn = true
                while true {
                    do {
                        try await Task.sleep(for: Self.blinkPhase)
                    } catch {
                        return
                    }
                    isCaretOn.toggle()
                    self?.item.button?.image = isCaretOn ? Self.idle : Self.caretOff
                }
            }
        }
    }
}
