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

    /// Each SwiftUI item (a button, the keycaps) keeps one size while the glass moves along its spring as the pill
    /// appears, in the pill's own panel on each screen. An item that took another size at another place moved itself
    /// back, and AppKit ended the app for the layout that never settled (2026-10-27, hands-free with cleanup on a 1x
    /// display).
    static func morphSizeProblem(of look: PillLook, at anchor: IndicatorAnchor) -> String? {
        // The panels go with each screen's pass: the check run drains no pool until it exits.
        NSScreen.screens.lazy.compactMap { screen in
            autoreleasepool { morphSizeProblem(of: look, at: anchor, on: screen) }
        }
        .first
    }

    private static func morphSizeProblem(of look: PillLook, at anchor: IndicatorAnchor, on screen: NSScreen) -> String?
    {
        let room = IndicatorPlacement.room(
            at: anchor, thickness: Double(PillGeometry.height), in: ScreenRect(screen.visibleFrame))
        let pill = PillView(frame: .zero)
        let panel = makeFloatingPanel(holding: pill, frame: NSRect(room))
        pill.anchor = anchor
        pill.prepareToAppear()
        let from = pill.glass.frame
        pill.appear(look)
        panel.layoutIfNeeded()
        let hosts = pill.stack.arrangedSubviews.filter { pill.hosts.contains($0) }
        let sizes = hosts.map(\.frame.size)
        let move = PillView.GlassMove(from: from, to: pill.capsuleFrame, reducesMotion: false)
        // One step a display frame, until the spring settles.
        let frames = Int((move.spring.swiftUI.settlingDuration * framesPerSecond).rounded(.up))
        for frame in 1...frames {
            pill.glass.frame = move.frame(at: Double(frame) / framesPerSecond)
            panel.layoutIfNeeded()
            if let (host, size) = zip(hosts, sizes).first(where: { $0.frame.size != $1 }) {
                return "\(type(of: host)) goes from \(size) to \(host.frame.size) as the glass moves on "
                    + screen.localizedName
            }
        }
        return nil
    }

    private static let framesPerSecond = 60.0

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

    /// A live phase with no words: a recording that shows only its bars and buttons, or the loading dots.
    var isLive: Bool {
        switch look {
        case .processing: true
        case .recording(let recording): recording.words == nil && recording.timedFrom == nil
        case .idle, .hover, .done, .message: false
        }
    }

    /// The words the pill shows, its time included.
    var shownWords: [String] {
        stack.arrangedSubviews.compactMap { ($0 as? NSTextField)?.stringValue }
    }
}
