import AppKit
import KotobaCore
import SwiftUI

/// The pill's visual sizes, the values that placement does not use. The sizes placement needs (the idle bar, the
/// longest pill) live in `IndicatorPlacement` and are only read here. The capsule is the buttons' height plus `inset`
/// above and below, so a button's corners follow the capsule's (concentric: the button's radius plus `inset` is the
/// capsule's radius), as in the Screenshot toolbar's capsule (⇧⌘5).
@MainActor
enum PillGeometry {
    /// The idle bar's long and short side, turned 90° at a side edge.
    static let idleLength = CGFloat(IndicatorPlacement.idleBarLength)
    static let idleThickness = CGFloat(IndicatorPlacement.idleBarThickness)
    /// The longest pill: about 34 characters of text beside a button (CODING_STANDARDS.md, "User-facing text" 7).
    static let maxLength = CGFloat(IndicatorPlacement.maxWidth)
    /// Between a button and the capsule's edge.
    static let inset: CGFloat = 6
    /// Between the items in the capsule.
    static let gap: CGFloat = 8
    /// The pill buttons' height on this macOS, measured once, not assumed: a regular text button and a large round
    /// one (24 and 24.5 pt on macOS 27).
    static let controlHeight =
        [PillButton(face: .text("Retry")), PillButton(face: .symbol("xmark", label: ""))]
        .map { NSHostingView(rootView: $0).fittingSize.height }.max() ?? 0
    /// The capsule's short side; placement takes it as the pill's thickness.
    static var height: CGFloat { controlHeight + 2 * inset }
    /// Text, bars and symbols keep a round button's radius from the capsule's end, so they line up with a button's
    /// centre on the pill below or above.
    static var endPadding: CGFloat { controlHeight / 2 }
    /// Room around the glass in its window, so the shadow the glass draws is not cut off at the window edge.
    static let shadowMargin: CGFloat = 16

    /// The level's bars: the waveform's last 0.9 s, one bar per level event.
    static let barCount = 9
    /// A bar's thickness and its shortest length: a dot at silence.
    static let barThickness: CGFloat = 3
    static let barGap: CGFloat = 2
    /// The sweep's wave: the dots grow to this many times their length and back.
    static let sweepScale: CGFloat = 2.6
}
