import AppKit
import SwiftUI

// The indicator pill's two buttons: its action ("Undo", "Choose Mic…") and, for VoiceOver, its own click.

/// The pill's action button. The pill's panel never becomes key, and AppKit draws a `.glass` button's title
/// dimmed in a window that is not key, too faint to read on the dark pill; SwiftUI's `controlActiveState`
/// draws it as in the key window.
struct PillButton: View {
    var title = ""
    var onClick: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let button = Button(title, action: onClick)
            .buttonStyle(.glass)
            .controlSize(.small)
            .environment(\.controlActiveState, .key)
        // Offscreen the window server's glass treatment is missing, so in dark the title draws near black; on
        // screen it draws in the label color, which the dark snapshot takes instead. Light draws right as is.
        if Snapshots.isRunning, colorScheme == .dark {
            button.foregroundStyle(Color(nsColor: .labelColor))
        } else {
            button
        }
    }
}

/// Acts on the first click in a window that is not key, so a pill action works without activating kotoba. For VoiceOver
/// it is the action's button itself ("Choose Mic…"), a sibling of the pill's own click, with the same action path as a
/// click: offscreen and before the panel shows, SwiftUI exposes no button inside a hosting view.
final class FirstClickHostingView: NSHostingView<PillButton> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        rootView.title
    }

    override func accessibilityChildren() -> [Any]? {
        []
    }

    /// The button itself, not SwiftUI's views inside it.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        self
    }

    override func accessibilityPerformPress() -> Bool {
        rootView.onClick()
        return true
    }
}

/// The pill's click as a VoiceOver button over the whole pill; a press is the click (`onClick`). Custom: an AppKit
/// view that handles its own mouse events has no control to expose.
final class PillTapElement: NSAccessibilityElement {
    private weak var pill: IndicatorPillView?

    init(pill: IndicatorPillView) {
        self.pill = pill
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityParent(pill)
    }

    override func accessibilityFrame() -> NSRect {
        guard let pill else { return .zero }
        return NSAccessibility.screenRect(fromView: pill, rect: pill.bounds)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick = pill?.onClick, pill?.content.click != nil else { return false }
        onClick()
        return true
    }
}
