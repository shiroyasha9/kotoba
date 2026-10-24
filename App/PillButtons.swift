import AppKit
import SwiftUI

// The indicator pill's two buttons: its action ("Undo", "Choose Mic…") and, for VoiceOver, its own click.

/// The pill's action button. The pill's panel never becomes key, and AppKit draws a `.glass` button's title
/// dimmed in a window that is not key, too faint to read on the dark pill; SwiftUI's `controlActiveState`
/// draws it as in the key window.
struct PillButton: View {
    var title = ""
    var onClick: () -> Void = {}

    var body: some View {
        Button(title, action: onClick)
            .buttonStyle(.glass)
            .controlSize(.small)
            .environment(\.controlActiveState, .key)
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
/// view that handles its own mouse events has no control to expose. A view under the pill's content, not an
/// `NSAccessibilityElement`: a view is a main-actor object like the pill, so the pill's hit test can hand it over
/// (`IndicatorPillView.accessibilityHitTest`). It takes no mouse event.
final class PillTapTarget: NSView {
    private weak var pill: IndicatorPillView?

    init(pill: IndicatorPillView) {
        self.pill = pill
        super.init(frame: .zero)
        setAccessibilityElement(false)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PillTapTarget is built in code")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick = pill?.onClick, pill?.content.click != nil else { return false }
        onClick()
        return true
    }
}
