import AppKit
import KotobaCore

// The pill's checks in the snapshot run (`IndicatorPanel.snapshots`).

extension IndicatorPanel {
    /// A recording shown while the pill is hidden draws every item, also the items that faded out on screen at the
    /// end of the dictation before it (an empty capsule at the start of a recording, owner QA 4 U3). The pill's window
    /// says it is on screen for that dictation, so its look changes fade as on screen, without a window on screen.
    static func reshowProblem(of look: PillLook) -> String? {
        guard case .recording = look else { return nil }
        let window = ClaimedWindow(
            contentRect: NSRect(x: 0, y: 0, width: PillGeometry.maxLength, height: PillGeometry.height),
            styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let pill = PillView(frame: .zero)
        window.contentView = pill
        pill.look = look
        window.claimsVisible = true
        pill.look = .processing(.transcribing)
        pill.look = .done
        window.claimsVisible = false
        pill.look = .idle
        pill.look = look
        let unseen = pill.stack.arrangedSubviews.filter { $0.alphaValue < 1 }
        return unseen.isEmpty
            ? nil
            : "a recording shown after a dictation draws \(unseen.count) of its \(pill.stack.arrangedSubviews.count) "
                + "items transparent: \(unseen.map { "\(type(of: $0))" })"
    }

    /// A window that says it is on screen while it is not, so the pill's look changes run their on-screen path.
    private final class ClaimedWindow: NSWindow {
        var claimsVisible = false
        override var isVisible: Bool { claimsVisible }
    }
}

// MARK: Checks

extension PillView {
    /// Every layer under the pill with a running animation: the idle-cost check wants none at idle.
    var animatedLayers: [CALayer] {
        // A view's layer is also its parent view's sublayer, so each layer counts once.
        var seen = Set<ObjectIdentifier>()
        func walk(_ layer: CALayer) -> [CALayer] {
            guard seen.insert(ObjectIdentifier(layer)).inserted else { return [] }
            let own = (layer.animationKeys() ?? []).isEmpty ? [] : [layer]
            return own + (layer.sublayers ?? []).flatMap(walk)
        }
        func walk(_ view: NSView) -> [CALayer] {
            (view.layer.map(walk) ?? []) + view.subviews.flatMap(walk)
        }
        return walk(self)
    }

    /// The content is longer than the capsule, so an item sits outside it. Valid after layout.
    var isOverflowing: Bool {
        let content = stack.arrangedSubviews.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        return !content.isNull && !stack.bounds.insetBy(dx: -0.5, dy: -0.5).contains(content)
    }

    /// The content needs more than the longest pill, so its words cannot all show.
    var isTooLong: Bool {
        contentLength > PillGeometry.maxLength + 0.5
    }

    /// The words or the time are narrower than their text, so they end in "…" or are cut. Valid after layout.
    var isTextTruncated: Bool {
        stack.arrangedSubviews.contains {
            guard let text = $0 as? NSTextField else { return false }
            return text.intrinsicContentSize.width > text.frame.width + 0.5
        }
    }

    /// A live phase with no words: a recording that shows only its bars and buttons, or the sweep.
    var isLive: Bool {
        switch look {
        case .processing: true
        case .recording(let recording): recording.words == nil && recording.timedFrom == nil
        case .idle, .hover, .done, .message, .dragged: false
        }
    }

    /// The words the pill shows, its time included.
    var shownWords: [String] {
        stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
    }
}
